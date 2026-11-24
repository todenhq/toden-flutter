package co.toden.flutter

import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/**
 * The presence device's rules, pure (user token design rev 4, sections 6b, 14).
 *
 * After an address verification answers 202, Dart has this plugin make a P-256
 * key the OS will never export ([PresenceDeviceKey], Android Keystore, StrongBox
 * when the phone has it) and registers its public half with Toden. From then
 * on this background code gets its own 1-hour presence token by signing a
 * timestamped request, and every queued day is sealed with that key, so a
 * late report still counts for its own day.
 *
 * Pure, so the JVM tests replay test/presence_seal_vectors.json, shared with
 * the RN SDK's device-rules.ts, Dart's presence_device.dart and the iOS
 * PresenceDevice.swift.
 */
object PresenceDeviceRules {
  /** At most one refresh per device in this long. */
  const val REFRESH_INTERVAL_MS = 30L * 60 * 1000
  /** After 409 `no_live_watch` (a pending device or a dormant chain). */
  const val BACK_OFF_MS = 6L * 60 * 60 * 1000

  fun registrationText(externalUserId: String, publicKey: String, signedAt: Long): String =
    "toden-presence-device-v1\n$externalUserId\n$publicKey\n$signedAt"

  fun refreshText(deviceId: String, externalUserId: String, signedAt: Long): String =
    "toden-presence-refresh-v1\n$deviceId\n$externalUserId\n$signedAt"

  /** The seal signs the observation's report-digest row, exactly as it is posted. */
  fun sealText(deviceId: String, externalUserId: String, observation: JSONObject, observedAtMillis: Long): String =
    "toden-presence-seal-v1\n$deviceId\n$externalUserId\n" +
      "${PresenceReportProof.rowText(PresenceReportProof.rowOf(observation))}\n$observedAtMillis"

  /** `observedAt` on the wire: UTC with milliseconds, as JavaScript writes it. */
  fun isoMillis(millis: Long): String {
    val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
    format.timeZone = TimeZone.getTimeZone("UTC")
    return format.format(java.util.Date(millis))
  }

  /** Always after the last one sent: the server takes only a strictly increasing value. */
  fun nextSignedAt(correctedNow: Long, lastSent: Long?): Long =
    if (lastSent == null) correctedNow else maxOf(correctedNow, lastSent + 1)

  /** Server minus device, from a response's Date header; null keeps the offset. */
  fun clockOffsetFrom(date: String?, deviceNowMillis: Long): Long? {
    if (date.isNullOrEmpty()) return null
    return try {
      val format = SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss zzz", Locale.US)
      format.timeZone = TimeZone.getTimeZone("GMT")
      format.isLenient = false
      format.parse(date)!!.time - deviceNowMillis
    } catch (_: Exception) {
      null
    }
  }

  enum class Registration { REGISTERED, REFUSED, LIMIT, DELETE_KEY, RETRY_CLOCK, KEEP }
  enum class Refresh { STORE, DELETE_KEY, RETRY_CLOCK, RETRY_SIGNED_AT, BACK_OFF, KEEP }

  fun registrationOutcome(status: Int?, code: String?): Registration = when {
    status == 201 || status == 200 -> Registration.REGISTERED
    status == 403 && code == "device_registration_refused" -> Registration.REFUSED
    status == 422 && code == "device_not_genuine" -> Registration.REFUSED
    status == 409 && code == "presence_device_limit" -> Registration.LIMIT
    status == 403 && code == "presence_device_invalid" -> Registration.DELETE_KEY
    status == 422 && code == "invalid_device_key" -> Registration.DELETE_KEY
    status == 400 && code == "clock_skew" -> Registration.RETRY_CLOCK
    else -> Registration.KEEP
  }

  /** The code decides; only 403 `presence_device_invalid` ends the key. */
  fun refreshOutcome(status: Int?, code: String?): Refresh = when {
    status == 201 || status == 200 -> Refresh.STORE
    status == 403 && code == "presence_device_invalid" -> Refresh.DELETE_KEY
    status == 400 && code == "clock_skew" -> Refresh.RETRY_CLOCK
    status == 409 && code == "stale_signed_at" -> Refresh.RETRY_SIGNED_AT
    status == 409 && code == "no_live_watch" -> Refresh.BACK_OFF
    else -> Refresh.KEEP
  }

  fun refreshDue(nowMillis: Long, lastRefreshAt: Long?, backOffUntil: Long?): Boolean {
    if (backOffUntil != null && nowMillis < backOffUntil) return false
    return lastRefreshAt == null || nowMillis - lastRefreshAt >= REFRESH_INTERVAL_MS
  }

  /**
   * The days a 2xx may take off the queue: on a watch held past its deadline,
   * only the days up to the deadline (a reviewer's extension may still let the
   * later ones count).
   */
  fun removableAfterSend(sent: List<JSONObject>, heldDeadlineDay: String?): List<JSONObject> =
    if (heldDeadlineDay == null) sent else sent.filter { it.optString("day") <= heldDeadlineDay }

  /** The error code of a JSON error answer (v1 envelope or flat). */
  fun errorCode(body: String?): String? = try {
    val json = JSONObject(body ?: return null)
    when (val error = json.opt("error")) {
      is JSONObject -> error.opt("code") as? String
      is String -> error
      else -> json.opt("code") as? String
    }
  } catch (_: Exception) {
    null
  }
}

/**
 * What this phone holds for its presence device, in noBackupFilesDir: the
 * key's alias and public half, and once Toden registered it, its id. Never the
 * private key, which stays in the Keystore.
 */
data class PresenceDeviceRecord(
  val externalUserId: String,
  val alias: String? = null,
  val publicKey: String? = null,
  val keyStorage: String? = null,
  val deviceId: String? = null,
  /**
   * SHA-256 of the HMAC presenceToken a registration was refused (or capped)
   * for: no new attempt until a new verification's 202 brings another token.
   */
  val refusedFor: String? = null,
  val lastSignedAt: Long? = null,
  val lastRefreshAt: Long? = null,
  val backOffUntil: Long? = null,
  /** Server minus device, from the last core Date header. */
  val clockOffset: Long = 0,
  /**
   * After 409 `presence_device_limit`: no new attempt before this. The cap
   * frees up when the customer revokes a device or a check ends.
   */
  val limitUntil: Long? = null,
  /**
   * SHA-256 of the HMAC presenceToken this device registered with. Core binds
   * a device to that token's verification, so a new verification's token
   * needs a new key and a new registration.
   */
  val registeredFor: String? = null,
) {
  val hasKey: Boolean get() = alias != null && publicKey != null
  val registered: Boolean get() = hasKey && deviceId != null
}

/** The device record's file format and the decisions around it, pure. */
object PresenceDeviceRecords {
  fun encode(r: PresenceDeviceRecord): String = JSONObject()
    .put("externalUserId", r.externalUserId)
    .put("alias", r.alias ?: JSONObject.NULL)
    .put("publicKey", r.publicKey ?: JSONObject.NULL)
    .put("keyStorage", r.keyStorage ?: JSONObject.NULL)
    .put("deviceId", r.deviceId ?: JSONObject.NULL)
    .put("refusedFor", r.refusedFor ?: JSONObject.NULL)
    .put("lastSignedAt", r.lastSignedAt ?: JSONObject.NULL)
    .put("lastRefreshAt", r.lastRefreshAt ?: JSONObject.NULL)
    .put("backOffUntil", r.backOffUntil ?: JSONObject.NULL)
    .put("clockOffset", r.clockOffset)
    .put("limitUntil", r.limitUntil ?: JSONObject.NULL)
    .put("registeredFor", r.registeredFor ?: JSONObject.NULL)
    .toString()

  fun decode(raw: String): PresenceDeviceRecord? = try {
    val j = JSONObject(raw)
    fun str(k: String) = j.opt(k) as? String
    fun long(k: String) = (j.opt(k) as? Number)?.toLong()
    PresenceDeviceRecord(
      externalUserId = j.getString("externalUserId"),
      alias = str("alias"),
      publicKey = str("publicKey"),
      keyStorage = str("keyStorage"),
      deviceId = str("deviceId"),
      refusedFor = str("refusedFor"),
      lastSignedAt = long("lastSignedAt"),
      lastRefreshAt = long("lastRefreshAt"),
      backOffUntil = long("backOffUntil"),
      clockOffset = long("clockOffset") ?: 0,
      limitUntil = long("limitUntil"),
      registeredFor = str("registeredFor"),
    )
  } catch (_: Exception) {
    null
  }

  /** Lowercase hex SHA-256 of a presenceToken: the refusal marker, never the token. */
  fun tokenDigest(token: String): String =
    java.security.MessageDigest.getInstance("SHA-256")
      .digest(token.toByteArray(Charsets.UTF_8))
      .joinToString("") { "%02x".format(it) }

  sealed class Step {
    /** Registered already: nothing to send. */
    object Registered : Step()
    /** Refused (or capped) for this very token: wait for a new verification. */
    object Refused : Step()
    /** A key kept from an attempt with no answer: send it again (one key, one registration). */
    data class Reuse(val record: PresenceDeviceRecord) : Step()
    /** Make a new key; [discard] is a key held for another user, to delete first. */
    data class NewKey(val discard: String?) : Step()
  }

  fun registrationStep(record: PresenceDeviceRecord?, externalUserId: String, presenceToken: String): Step = when {
    record == null -> Step.NewKey(null)
    record.externalUserId != externalUserId -> Step.NewKey(record.alias)
    record.registered ->
      if (record.registeredFor == tokenDigest(presenceToken)) Step.Registered else Step.NewKey(record.alias)
    record.refusedFor == tokenDigest(presenceToken) -> Step.Refused
    record.hasKey -> Step.Reuse(record)
    else -> Step.NewKey(null)
  }

  /**
   * Whether [current] is still the device a request was sent for: the same
   * user, key and registration. A logout, or another run's delete or new key,
   * while the request was out means its answer must not write the old record
   * back (or keep a token for a user who signed out).
   */
  fun stillHeld(sent: PresenceDeviceRecord, current: PresenceDeviceRecord?): Boolean =
    current != null && current.externalUserId == sent.externalUserId &&
      current.alias == sent.alias && current.deviceId == sent.deviceId
}

/**
 * Seals a chunk at post time: each queued entry that has its `observedAtMillis`
 * (stamped, on the corrected clock, whenever its aggregate changed) gets a
 * `seal` over its wire row exactly as posted. An entry the key cannot sign
 * goes unsealed, never dropped: core judges it as an unsealed report.
 */
object PresenceSeal {
  /** True when at least one entry was sealed, so the body needs `sealDeviceId`. */
  fun apply(
    queued: List<JSONObject>,
    observations: org.json.JSONArray,
    deviceId: String,
    externalUserId: String,
    sign: (String) -> String?,
  ): Boolean {
    var any = false
    for (i in 0 until minOf(queued.size, observations.length())) {
      val observedAt = queued[i].optLong("observedAtMillis", -1L)
      if (observedAt <= 0) continue
      val wire = observations.getJSONObject(i)
      val signature = sign(PresenceDeviceRules.sealText(deviceId, externalUserId, wire, observedAt)) ?: continue
      wire.put("seal", JSONObject().put("observedAt", PresenceDeviceRules.isoMillis(observedAt)).put("signature", signature))
      any = true
    }
    return any
  }
}
