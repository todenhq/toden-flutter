package co.toden.flutter

import android.util.Log
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * The presence device's two requests (user token design rev 4, section 6b):
 * registration, from the foreground right after an address verification's
 * 202, and the background refresh that gets a 1-hour presence token by
 * signing a timestamped request. Blocking HTTP: every caller is off the main
 * thread. The rules are [PresenceDeviceRules] and [PresenceDeviceRecords],
 * which the JVM tests pin.
 */
object PresenceDeviceClient {
  private const val TAG = "TodenPresence"

  /**
   * One device request at a time in this process. A geofence receiver, a
   * check-in, the foreground service and the channel can all reach here at
   * once; two refreshes would each sign and send, and a registration and a
   * refresh would each write back the record they started from.
   */
  private val requests = ReentrantLock()

  data class Answer(val status: Int?, val date: String?, val body: String?)

  private fun post(url: String, apiKey: String, body: JSONObject, userToken: String? = null): Answer {
    var connection: HttpURLConnection? = null
    return try {
      connection = URL(url).openConnection() as HttpURLConnection
      connection.requestMethod = "POST"
      connection.connectTimeout = 8000
      connection.readTimeout = 8000
      connection.doOutput = true
      connection.setRequestProperty("Content-Type", "application/json")
      connection.setRequestProperty("Authorization", "Bearer $apiKey")
      if (userToken != null) connection.setRequestProperty(PresenceUserToken.HEADER, userToken)
      OutputStreamWriter(connection.outputStream).use { it.write(body.toString()) }
      val status = connection.responseCode
      val stream = if (status in 200..299) connection.inputStream else connection.errorStream
      val text = stream?.bufferedReader()?.use { it.readText() }
      Answer(status, connection.getHeaderField("Date"), text)
    } catch (_: Exception) {
      Answer(null, null, null)
    } finally {
      connection?.disconnect()
    }
  }

  /** A response's clock, kept for the next signature. */
  private fun withClock(record: PresenceDeviceRecord, answer: Answer, deviceNow: Long): PresenceDeviceRecord =
    PresenceDeviceRules.clockOffsetFrom(answer.date, deviceNow)?.let { record.copy(clockOffset = it) } ?: record

  /**
   * Registers this phone's presence device for [externalUserId]: a new
   * non-exportable key, unless one is kept from an attempt with no answer.
   * Answers the outcome's name for Dart: `registered`, `refused`, `limit`,
   * `delete_key`, `keep`, `no_key`, `needs_token` (asked with no user token
   * and one is needed), or `user_token_invalid` (Dart fetches a fresh token
   * and calls once more).
   */
  fun register(
    store: PresenceStore,
    baseUrl: String,
    apiKey: String,
    externalUserId: String,
    userToken: String?,
    presenceToken: String,
  ): String = requests.withLock { registerLocked(store, baseUrl, apiKey, externalUserId, userToken, presenceToken) }

  private fun registerLocked(
    store: PresenceStore,
    baseUrl: String,
    apiKey: String,
    externalUserId: String,
    userToken: String?,
    presenceToken: String,
  ): String {
    val held = store.readDevice()
    val limitUntil = held?.limitUntil
    if (held != null && held.externalUserId == externalUserId && !held.registered &&
      limitUntil != null && System.currentTimeMillis() < limitUntil
    ) {
      return "limit"
    }
    var record = when (val step = PresenceDeviceRecords.registrationStep(held, externalUserId, presenceToken)) {
      is PresenceDeviceRecords.Step.Registered -> return "registered"
      is PresenceDeviceRecords.Step.Refused -> return "refused"
      is PresenceDeviceRecords.Step.Reuse -> step.record
      is PresenceDeviceRecords.Step.NewKey -> {
        step.discard?.let { PresenceDeviceKey.delete(it) }
        store.deleteDevice()
        // The key first: a phone with none answers no_key before the host mints.
        val created = PresenceDeviceKey.create() ?: return "no_key"
        PresenceDeviceRecord(externalUserId, created.alias, created.publicKey, created.keyStorage).also {
          // Kept before sending, so an answer that never comes reuses this key.
          store.saveDevice(it)
        }
      }
    }
    // Dart asks first with no token, so a phone already registered never
    // costs the host a mint.
    if (userToken == null) return "needs_token"
    val alias = record.alias!!
    val publicKey = record.publicKey!!
    for (attempt in 0..1) {
      val deviceNow = System.currentTimeMillis()
      val signedAt = PresenceDeviceRules.nextSignedAt(deviceNow + record.clockOffset, record.lastSignedAt)
      val proof = PresenceDeviceKey.sign(alias, PresenceDeviceRules.registrationText(externalUserId, publicKey, signedAt))
        ?: return "keep"
      record = record.copy(lastSignedAt = signedAt)
      store.saveDevice(record)
      val body = JSONObject()
        .put("externalUserId", externalUserId)
        .put("publicKey", publicKey)
        .put("platform", "android")
        .put("keyStorage", record.keyStorage ?: "tee")
        .put("signedAt", signedAt)
        .put("proof", proof)
        .put("presenceToken", presenceToken)
      DeviceIntelHandler.androidId(store.appContext)?.let { body.put("device", JSONObject().put("stableId", it)) }
      val answer = post("$baseUrl/api/v1/address/presence/devices", apiKey, body, userToken)
      // A logout while the request was out: leave the device gone.
      if (!PresenceDeviceRecords.stillHeld(record, store.readDevice())) return "keep"
      record = withClock(record, answer, deviceNow)
      val code = PresenceDeviceRules.errorCode(answer.body)
      when (PresenceDeviceRules.registrationOutcome(answer.status, code)) {
        PresenceDeviceRules.Registration.REGISTERED -> {
          val id = try {
            JSONObject(answer.body ?: "{}").optString("id").takeIf { it.isNotEmpty() }
          } catch (_: Exception) {
            null
          } ?: return "keep".also { store.saveDevice(record) }
          store.saveDevice(
            record.copy(deviceId = id, refusedFor = null, registeredFor = PresenceDeviceRecords.tokenDigest(presenceToken)),
          )
          return "registered"
        }
        PresenceDeviceRules.Registration.REFUSED -> {
          // No refresh: this phone runs as before. A new verification's token may try again.
          PresenceDeviceKey.delete(alias)
          store.saveDevice(
            PresenceDeviceRecord(externalUserId, refusedFor = PresenceDeviceRecords.tokenDigest(presenceToken), clockOffset = record.clockOffset),
          )
          return "refused"
        }
        PresenceDeviceRules.Registration.LIMIT -> {
          // The cap frees up when the customer revokes a device or a check
          // ends: a later foreground tries again, after a back-off.
          Log.w(TAG, "presence_device_limit: this user already has the most presence devices")
          PresenceDeviceKey.delete(alias)
          store.saveDevice(
            PresenceDeviceRecord(
              externalUserId,
              clockOffset = record.clockOffset,
              limitUntil = System.currentTimeMillis() + PresenceDeviceRules.BACK_OFF_MS,
            ),
          )
          return "limit"
        }
        PresenceDeviceRules.Registration.DELETE_KEY -> {
          PresenceDeviceKey.delete(alias)
          store.deleteDevice()
          return "delete_key"
        }
        PresenceDeviceRules.Registration.RETRY_CLOCK -> {
          store.saveDevice(record)
          if (attempt == 0) continue
          return "keep"
        }
        PresenceDeviceRules.Registration.KEEP -> {
          store.saveDevice(record)
          return if (code == "user_token_invalid") "user_token_invalid" else "keep"
        }
      }
    }
    return "keep"
  }

  /**
   * A fresh presence token for the flush when this phone holds a registered
   * device and a refresh is due. True when one was stored. When another
   * device request is running, answers false at once: the queue is kept, and
   * the flush that is refreshing posts it.
   */
  fun refreshIfDue(store: PresenceStore, config: PresenceStore.Config): Boolean {
    if (!requests.tryLock()) return false
    return try {
      refreshLocked(store, config)
    } finally {
      requests.unlock()
    }
  }

  private fun refreshLocked(store: PresenceStore, config: PresenceStore.Config): Boolean {
    val start = store.readDevice() ?: return false
    if (!start.registered || start.externalUserId != config.externalUserId) return false
    val now = System.currentTimeMillis()
    if (!PresenceDeviceRules.refreshDue(now, start.lastRefreshAt, start.backOffUntil)) return false
    var record = start
    val deviceId = record.deviceId!!
    for (attempt in 0..1) {
      val deviceNow = System.currentTimeMillis()
      val signedAt = PresenceDeviceRules.nextSignedAt(deviceNow + record.clockOffset, record.lastSignedAt)
      val signature = PresenceDeviceKey.sign(
        record.alias!!, PresenceDeviceRules.refreshText(deviceId, config.externalUserId, signedAt),
      ) ?: return false
      // Kept before sending: a signedAt once sent is never sent again.
      record = record.copy(lastSignedAt = signedAt)
      store.saveDevice(record)
      val body = JSONObject()
        .put("deviceId", deviceId)
        .put("externalUserId", config.externalUserId)
        .put("signedAt", signedAt)
        .put("signature", signature)
      val answer = post("${config.baseUrl}/api/v1/address/presence/devices/token", config.apiKey, body)
      // A logout while the request was out: no record back, no token kept.
      if (!PresenceDeviceRecords.stillHeld(record, store.readDevice())) return false
      record = withClock(record, answer, deviceNow)
      if (answer.status != null) record = record.copy(lastRefreshAt = deviceNow)
      when (PresenceDeviceRules.refreshOutcome(answer.status, PresenceDeviceRules.errorCode(answer.body))) {
        PresenceDeviceRules.Refresh.STORE -> {
          store.saveDevice(record.copy(backOffUntil = null))
          val minted = try {
            PresenceUserToken.checkMinted(JSONObject(answer.body ?: "{}"), config.externalUserId, config.apiKey, System.currentTimeMillis())
          } catch (_: Exception) {
            null
          } ?: return false
          if (!store.saveUserToken(minted)) return false
          store.userTokensInUse = true
          return true
        }
        PresenceDeviceRules.Refresh.DELETE_KEY -> {
          PresenceDeviceKey.delete(record.alias!!)
          store.deleteDevice()
          return false
        }
        PresenceDeviceRules.Refresh.RETRY_CLOCK, PresenceDeviceRules.Refresh.RETRY_SIGNED_AT -> {
          store.saveDevice(record)
          if (attempt == 0) continue
          return false
        }
        PresenceDeviceRules.Refresh.BACK_OFF -> {
          store.saveDevice(record.copy(backOffUntil = deviceNow + PresenceDeviceRules.BACK_OFF_MS))
          return false
        }
        PresenceDeviceRules.Refresh.KEEP -> {
          store.saveDevice(record)
          return false
        }
      }
    }
    return false
  }
}
