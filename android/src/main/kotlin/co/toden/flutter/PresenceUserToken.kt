package co.toden.flutter

import org.json.JSONArray
import org.json.JSONObject

/**
 * User tokens for scoped publishable keys (Toden design 0020, section 14), as
 * the background flush needs them. Native code never calls the host's provider
 * and never renews a token: Dart hands one over after its identity check
 * (setPresenceUserToken), and [PresenceStore] keeps it in noBackupFilesDir.
 *
 * Pure rules only, so the JVM tests can replay test/user_token_vectors.json:
 *  - User tokens not in use: post exactly as before, with no header.
 *  - In use: only a fresh token for the armed user is sent. A missing, expired
 *    or stale token, another user's, or an unreadable store means no post, and
 *    the queue is kept.
 * Mirrors the iOS PresenceUserToken.swift and the RN SDK's secure-token.ts.
 */
object PresenceUserToken {
  const val HEADER = "X-Toden-User-Token"

  data class Record(
    val externalUserId: String,
    val token: String,
    val expiresAtMillis: Long,
    val stale: Boolean,
  )

  sealed class Read {
    object Missing : Read()
    object Locked : Read()
    data class Stored(val record: Record) : Read()
  }

  sealed class Decision {
    object NoHeader : Decision()
    object Skip : Decision()
    data class Use(val token: String) : Decision()
  }

  fun decide(inUse: Boolean, read: Read, externalUserId: String, nowMillis: Long): Decision {
    if (!inUse) return Decision.NoHeader
    val record = (read as? Read.Stored)?.record ?: return Decision.Skip
    if (record.externalUserId != externalUserId || record.stale) return Decision.Skip
    return if (nowMillis < record.expiresAtMillis) Decision.Use(record.token) else Decision.Skip
  }

  /**
   * The record to save after the server refused [sentToken], or null. Only the
   * token that was sent goes stale: one a silent push stored while the refused
   * flush was out stays good.
   */
  fun staleAfterRefusal(read: Read, sentToken: String): Record? {
    val record = (read as? Read.Stored)?.record ?: return null
    return if (record.token == sentToken && !record.stale) record.copy(stale = true) else null
  }

  private val SHAPE = Regex("^ut_(live|test|dev)_[A-Za-z0-9_-]{43}$")

  /** A value the server could accept at all; anything else is never stored. */
  fun wellFormed(token: String): Boolean = SHAPE.matches(token)

  private val KEY_ENV = Regex("^(?:pk|sk)_(live|test|dev)_")
  private val ISO = Regex("^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})(?:\\.(\\d{1,3}))?Z$")

  /** A mint-shaped answer's `expiresAt` (always UTC, as core writes it), or null. */
  fun parseExpiresAt(value: String): Long? {
    val m = ISO.matchEntire(value) ?: return null
    val (y, mo, d, h, mi, se) = m.destructured
    val calendar = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"))
    calendar.clear()
    calendar.set(y.toInt(), mo.toInt() - 1, d.toInt(), h.toInt(), mi.toInt(), se.toInt())
    val millis = m.groupValues[7].padEnd(3, '0').toInt()
    return calendar.timeInMillis + millis
  }

  /**
   * A token core minted or refreshed, as a record the flush may send, or null.
   * The same identity check Dart runs on a provider's answer (user_token.dart),
   * because a background refresh has no Dart to run it.
   */
  fun checkMinted(body: JSONObject, externalUserId: String, apiKey: String, nowMillis: Long): Record? {
    val token = body.opt("token") as? String ?: return null
    val user = body.opt("externalUserId") as? String ?: return null
    val purpose = body.opt("purpose") as? String ?: return null
    val expiresAt = body.opt("expiresAt") as? String ?: return null
    if (user != externalUserId || purpose != "presence") return null
    val shape = SHAPE.matchEntire(token) ?: return null
    val env = KEY_ENV.find(apiKey) ?: return null
    if (shape.groupValues[1] != env.groupValues[1]) return null
    val expires = parseExpiresAt(expiresAt) ?: return null
    if (expires <= nowMillis) return null
    return Record(externalUserId, token, expires, stale = false)
  }

  fun encode(record: Record): String = JSONObject()
    .put("externalUserId", record.externalUserId)
    .put("token", record.token)
    .put("expiresAtMillis", record.expiresAtMillis)
    .put("stale", record.stale)
    .toString()

  fun decode(raw: String): Record? = try {
    val json = JSONObject(raw)
    Record(
      externalUserId = json.getString("externalUserId"),
      token = json.getString("token"),
      expiresAtMillis = json.getLong("expiresAtMillis"),
      stale = json.optBoolean("stale", false),
    )
  } catch (_: Exception) {
    null
  }
}

/**
 * The background queue's flush rules: oldest day first, at most 31 days a
 * request (the server's limit). A 2xx removes its chunk; a 400 can never
 * succeed, so its chunk is dropped; anything else keeps the queue and stops.
 * Days are never dropped by age alone. Mirrors PresenceFlush in the iOS
 * PresenceUserToken.swift and the RN SDK's flush.ts.
 */
object PresenceFlush {
  const val CHUNK_DAYS = 31

  enum class Outcome { SENT, DROP, KEEP }

  fun chunks(queue: JSONArray): List<List<JSONObject>> {
    val entries = (0 until queue.length()).map { queue.getJSONObject(it) }
    return entries.sortedBy { it.optString("day") }.chunked(CHUNK_DAYS)
  }

  /** `null`: nothing came back. */
  fun outcome(status: Int?): Outcome = when {
    status == null -> Outcome.KEEP
    status in 200..299 -> Outcome.SENT
    status == 400 -> Outcome.DROP
    else -> Outcome.KEEP
  }

  data class Result(
    /** Still queued, oldest first. */
    val remaining: List<JSONObject>,
    /** The server answered with a refusal (not 2xx, not 400). */
    val refused: Boolean,
    /** Taken by a 2xx. On a held watch only some may leave the queue. */
    val sent: List<JSONObject> = emptyList(),
    /** Refused with a 400, which can never succeed. */
    val dropped: List<JSONObject> = emptyList(),
  )

  /** Posts chunk by chunk, blocking, until one is kept. */
  fun run(queue: JSONArray, post: (List<JSONObject>) -> Int?): Result {
    val all = chunks(queue)
    val sent = mutableListOf<JSONObject>()
    val dropped = mutableListOf<JSONObject>()
    for ((index, chunk) in all.withIndex()) {
      val status = post(chunk)
      when (outcome(status)) {
        Outcome.KEEP -> return Result(all.drop(index).flatten(), refused = status != null, sent = sent, dropped = dropped)
        Outcome.SENT -> sent += chunk
        Outcome.DROP -> dropped += chunk
      }
    }
    return Result(emptyList(), refused = false, sent = sent, dropped = dropped)
  }
}

/**
 * The HMAC presenceToken's move from the prefs (which Auto Backup copies) to
 * noBackupFilesDir (user token design rev 4, R65). Pure, so the JVM tests pin
 * every branch. Mirrors the iOS PresenceHmacToken and the RN SDK's store.ts.
 */
object PresenceHmacToken {
  sealed class Stored {
    object Missing : Stored()
    object Locked : Stored()
    data class Kept(val externalUserId: String, val token: String) : Stored()
  }

  sealed class Step {
    /** Send this (null: no token). */
    data class Use(val token: String?) : Step()
    /** Write it to no-backup storage, read it back, then delete the prefs copy. */
    data class MoveFromDefaults(val token: String) : Step()
    /** Storage cannot be read yet and nothing else holds a token: wait. */
    object Held : Step()
  }

  fun step(prefsToken: String?, stored: Stored, externalUserId: String): Step = when {
    stored is Stored.Kept && stored.externalUserId == externalUserId -> Step.Use(stored.token)
    stored is Stored.Locked -> if (prefsToken != null) Step.Use(prefsToken) else Step.Held
    prefsToken != null -> Step.MoveFromDefaults(prefsToken)
    else -> Step.Use(null)
  }

  fun has(stored: Stored, externalUserId: String): Boolean =
    stored is Stored.Kept && stored.externalUserId == externalUserId
}
