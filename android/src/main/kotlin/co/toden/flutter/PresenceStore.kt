package co.toden.flutter

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Persistence for the background presence tier: the armed config, the open
 * ENTER timestamp, and the pending per-day queue. SharedPreferences because
 * the geofence receiver runs with no Flutter engine — this must be readable
 * from a cold broadcast. Only per-day aggregates are ever stored; a location
 * trace never exists anywhere. Mirrors the RN SDK's background-store.ts.
 */
class PresenceStore(context: Context) {
  companion object {
    /**
     * One lock for every read-modify-write of the queue and the token file.
     * Each caller builds its own PresenceStore, on a receiver's worker, the
     * channel's executor or the token-flush thread, so the lock is process wide.
     */
    private val LOCK = Any()
  }

  val appContext: Context = context.applicationContext
  private val prefs: SharedPreferences =
    context.applicationContext.getSharedPreferences("myaza_kyc_presence", Context.MODE_PRIVATE)

  data class Config(
    val lat: Double,
    val lng: Double,
    val radius: Double,
    val baseUrl: String,
    val apiKey: String,
    val externalUserId: String,
    /** The Google Cloud project Play Integrity proofs are made for. */
    val playIntegrityProject: String? = null,
    val emulator: Boolean = false,
    /** From the 202 of the verification that captured the pin. Kept in
     *  noBackupFilesDir, never in these prefs, which Auto Backup copies. */
    val presenceToken: String? = null,
    /** The file holds it but cannot be read yet: the flush waits. */
    val presenceTokenHeld: Boolean = false,
  )

  fun saveConfig(config: Config) = synchronized(LOCK) {
    val json = JSONObject()
      .put("lat", config.lat)
      .put("lng", config.lng)
      .put("radius", config.radius)
      .put("baseUrl", config.baseUrl)
      .put("apiKey", config.apiKey)
      .put("externalUserId", config.externalUserId)
      .put("playIntegrityProject", config.playIntegrityProject ?: JSONObject.NULL)
      .put("emulator", config.emulator)
    // A new pin drops the old token, wherever it was kept.
    deleteHmacToken()
    val token = config.presenceToken
    // No-backup storage first; the prefs (which Auto Backup copies) only if that fails.
    json.put("presenceToken", if (token != null && !saveHmacToken(config.externalUserId, token)) token else JSONObject.NULL)
    prefs.edit().putString("config", json.toString()).putBoolean("armed", true).apply()
  }

  /** The token arrives after the fence may already be armed, and Dart keeps
   *  it here for the foreground reporter too, so it is saved whether or not a
   *  config is armed. Leaves `armed` alone; a config for another user keeps
   *  its own. Answers whether no-backup storage took it (Dart then keeps no copy). */
  fun updatePresenceToken(externalUserId: String, token: String): Boolean = synchronized(LOCK) {
    val saved = saveHmacToken(externalUserId, token)
    val raw = prefs.getString("config", null) ?: return@synchronized saved
    try {
      val json = JSONObject(raw)
      if (json.getString("externalUserId") == externalUserId) {
        json.put("presenceToken", if (saved) JSONObject.NULL else token)
        prefs.edit().putString("config", json.toString()).apply()
      }
    } catch (_: Exception) {
      // An unreadable config has nothing to update.
    }
    saved
  }

  /** This user's token for the Dart reporter, and whether storage held it back. */
  fun presenceToken(externalUserId: String): Pair<String?, Boolean> = synchronized(LOCK) {
    when (val stored = readHmacToken()) {
      is PresenceHmacToken.Stored.Locked -> Pair(null, true)
      is PresenceHmacToken.Stored.Kept -> Pair(stored.token.takeIf { stored.externalUserId == externalUserId }, false)
      else -> Pair(null, false)
    }
  }

  /** A new pin, a cleared pin or a stand-down for this user drops the token. */
  fun forgetPresenceToken(externalUserId: String) = synchronized(LOCK) {
    val stored = readHmacToken()
    if (stored is PresenceHmacToken.Stored.Kept && stored.externalUserId == externalUserId) deleteHmacToken()
  }

  fun loadConfig(): Config? = synchronized(LOCK) {
    val raw = prefs.getString("config", null) ?: return@synchronized null
    try {
      val json = JSONObject(raw)
      val user = json.getString("externalUserId")
      val legacy = if (json.isNull("presenceToken")) null else json.optString("presenceToken").takeIf { it.isNotEmpty() }
      val stored = readHmacToken()
      var token: String? = null
      var held = false
      when (val step = PresenceHmacToken.step(legacy, stored, user)) {
        is PresenceHmacToken.Step.Use -> {
          token = step.token
          // The no-backup file already holds it: the backed-up copy goes.
          if (legacy != null && PresenceHmacToken.has(stored, user)) {
            prefs.edit().putString("config", json.put("presenceToken", JSONObject.NULL).toString()).apply()
          }
        }
        is PresenceHmacToken.Step.MoveFromDefaults -> {
          token = step.token
          // Written, read back, and only then deleted from the prefs.
          if (saveHmacToken(user, step.token) && readHmacToken() == PresenceHmacToken.Stored.Kept(user, step.token)) {
            prefs.edit().putString("config", json.put("presenceToken", JSONObject.NULL).toString()).apply()
          }
        }
        is PresenceHmacToken.Step.Held -> held = true
      }
      Config(
        lat = json.getDouble("lat"),
        lng = json.getDouble("lng"),
        radius = json.optDouble("radius", 250.0),
        baseUrl = json.getString("baseUrl"),
        apiKey = json.getString("apiKey"),
        externalUserId = user,
        playIntegrityProject = json.optString("playIntegrityProject").takeIf { it.isNotEmpty() && it != "null" },
        emulator = json.optBoolean("emulator", false),
        presenceToken = token,
        presenceTokenHeld = held,
      )
    } catch (_: Exception) {
      null
    }
  }

  // ── The HMAC presenceToken: a file in noBackupFilesDir (design rev 4, R65) ──

  private val hmacFile: File get() = File(appContext.noBackupFilesDir, "toden_presence_token.json")
  private val hmacTmp: File get() = File(appContext.noBackupFilesDir, "toden_presence_token.json.tmp")

  private fun saveHmacToken(externalUserId: String, token: String): Boolean = try {
    hmacTmp.writeText(JSONObject().put("externalUserId", externalUserId).put("token", token).toString())
    hmacTmp.renameTo(hmacFile)
  } catch (_: Exception) {
    false
  }

  /** Unreadable (credential storage before the first unlock) is `Locked`. */
  private fun readHmacToken(): PresenceHmacToken.Stored = try {
    if (!hmacFile.isFile) {
      PresenceHmacToken.Stored.Missing
    } else {
      val json = JSONObject(hmacFile.readText())
      PresenceHmacToken.Stored.Kept(json.getString("externalUserId"), json.getString("token"))
    }
  } catch (_: Exception) {
    PresenceHmacToken.Stored.Locked
  }

  private fun deleteHmacToken() {
    try {
      hmacFile.delete()
      hmacTmp.delete()
    } catch (_: Exception) {
      // Nothing to delete.
    }
  }

  fun clear() = synchronized(LOCK) {
    prefs.edit().clear().apply()
    deleteUserToken()
    deleteHmacToken()
  }

  // ── User token: a file in noBackupFilesDir, never these prefs ─────────────
  // The prefs are backed up with the app; noBackupFilesDir never is, and the
  // file is private to the app. The flag below is not a secret.

  private val userTokenFile: File get() = File(appContext.noBackupFilesDir, "toden_presence_user_token.json")

  var userTokensInUse: Boolean
    get() = prefs.getBoolean("userTokens", false)
    set(value) {
      prefs.edit().putBoolean("userTokens", value).apply()
    }

  private val userTokenTmp: File get() = File(appContext.noBackupFilesDir, "toden_presence_user_token.json.tmp")

  fun saveUserToken(record: PresenceUserToken.Record): Boolean = synchronized(LOCK) {
    try {
      userTokenTmp.writeText(PresenceUserToken.encode(record))
      userTokenTmp.renameTo(userTokenFile)
    } catch (_: Exception) {
      false
    }
  }

  /** An unreadable file is `Locked`: the flush keeps its queue. */
  fun readUserToken(): PresenceUserToken.Read = synchronized(LOCK) {
    try {
      val file = userTokenFile
      if (!file.isFile) {
        PresenceUserToken.Read.Missing
      } else {
        PresenceUserToken.decode(file.readText())?.let { PresenceUserToken.Read.Stored(it) }
          ?: PresenceUserToken.Read.Missing
      }
    } catch (_: Exception) {
      PresenceUserToken.Read.Locked
    }
  }

  /** The server refused [sentToken]: only that token goes stale. */
  fun markUserTokenStale(sentToken: String) = synchronized(LOCK) {
    PresenceUserToken.staleAfterRefusal(readUserToken(), sentToken)?.let { saveUserToken(it) }
    Unit
  }

  fun deleteUserToken() = synchronized(LOCK) {
    try {
      userTokenFile.delete()
      userTokenTmp.delete()
    } catch (_: Exception) {
      // Nothing to delete.
    }
    Unit
  }

  /** Logout or stand-down for this user: no token, no flag. */
  fun clearUserToken(externalUserId: String) = synchronized(LOCK) {
    val stored = readUserToken() as? PresenceUserToken.Read.Stored
    if (stored != null && stored.record.externalUserId != externalUserId) return@synchronized
    userTokensInUse = false
    deleteUserToken()
  }

  // ── Presence device: a file in noBackupFilesDir, never these prefs ────────
  // The key's alias, its public half and the registration id. A restored
  // backup must never carry them to another phone, whose Keystore has no key.

  private val deviceFile: File get() = File(appContext.noBackupFilesDir, "toden_presence_device.json")
  private val deviceTmp: File get() = File(appContext.noBackupFilesDir, "toden_presence_device.json.tmp")

  fun readDevice(): PresenceDeviceRecord? = synchronized(LOCK) {
    try {
      if (deviceFile.isFile) PresenceDeviceRecords.decode(deviceFile.readText()) else null
    } catch (_: Exception) {
      null
    }
  }

  fun saveDevice(record: PresenceDeviceRecord): Boolean = synchronized(LOCK) {
    try {
      deviceTmp.writeText(PresenceDeviceRecords.encode(record))
      deviceTmp.renameTo(deviceFile)
    } catch (_: Exception) {
      false
    }
  }

  /** Read, change and write under the lock, so a refresh and a registration never interleave. */
  fun updateDevice(change: (PresenceDeviceRecord) -> PresenceDeviceRecord?) = synchronized(LOCK) {
    val current = readDevice() ?: return@synchronized
    val next = change(current)
    if (next == null) deleteDevice() else saveDevice(next)
  }

  fun deleteDevice() = synchronized(LOCK) {
    try {
      deviceFile.delete()
      deviceTmp.delete()
    } catch (_: Exception) {
      // Nothing to delete.
    }
    Unit
  }

  /** Logout: the key, its registration and its marks, for this user only. */
  fun forgetDevice(externalUserId: String) = synchronized(LOCK) {
    val record = readDevice() ?: return@synchronized
    if (record.externalUserId != externalUserId) return@synchronized
    record.alias?.let { PresenceDeviceKey.delete(it) }
    deleteDevice()
  }

  /**
   * The watch's deadline day (yyyy-MM-dd, UTC) while it is in progress past
   * it, held for late sealed reports; null otherwise. Set by Dart from the
   * watch status. Not a secret.
   */
  var heldDeadlineDay: String?
    get() = prefs.getString("heldDeadlineDay", null)
    set(value) {
      prefs.edit().apply { if (value == null) remove("heldDeadlineDay") else putString("heldDeadlineDay", value) }.apply()
    }

  /** When an entry's aggregate last changed, on the clock the seals use. */
  private fun observedNow(): Long = System.currentTimeMillis() + (readDevice()?.clockOffset ?: 0L)

  /** Removes posted entries; days queued while the requests were out stay. */
  fun removeFromQueue(posted: List<JSONObject>) = synchronized(LOCK) {
    if (posted.isEmpty()) return@synchronized
    val gone = posted.map { it.toString() }.toSet()
    val current = pendingQueue()
    val next = JSONArray()
    for (i in 0 until current.length()) {
      val o = current.getJSONObject(i)
      if (o.toString() !in gone) next.put(o)
    }
    prefs.edit().putString("queue", next.toString()).apply()
  }

  /** The foreground-service tier's durable intent: the boot receiver restarts
   *  the service when this is set, and a refused startForeground clears it. */
  var serviceEnabled: Boolean
    get() = prefs.getBoolean("serviceEnabled", false)
    set(value) {
      prefs.edit().putBoolean("serviceEnabled", value).apply()
    }

  /** The persistent notification's content — the host's words, persisted so
   *  a START_STICKY restart or a boot can rebuild it with no Dart running. */
  data class NotificationConfig(
    val title: String,
    val body: String,
    val channelId: String,
    val channelName: String,
    val channelDescription: String?,
    val color: Int?,
  )

  fun saveNotification(n: NotificationConfig) {
    val json = JSONObject()
      .put("title", n.title)
      .put("body", n.body)
      .put("channelId", n.channelId)
      .put("channelName", n.channelName)
      .put("channelDescription", n.channelDescription ?: JSONObject.NULL)
      .put("color", n.color ?: JSONObject.NULL)
    prefs.edit().putString("notification", json.toString()).apply()
  }

  fun loadNotification(): NotificationConfig {
    val fallback = NotificationConfig(
      title = "Address verification in progress",
      body = "Open the app to see your progress.",
      channelId = "myaza_kyc_presence",
      channelName = "Address verification",
      channelDescription = null,
      color = null,
    )
    val raw = prefs.getString("notification", null) ?: return fallback
    return try {
      val json = JSONObject(raw)
      NotificationConfig(
        title = json.optString("title", fallback.title),
        body = json.optString("body", fallback.body),
        channelId = json.optString("channelId", fallback.channelId),
        channelName = json.optString("channelName", fallback.channelName),
        channelDescription = if (json.isNull("channelDescription")) null else json.optString("channelDescription"),
        color = if (json.isNull("color")) null else json.optInt("color"),
      )
    } catch (_: Exception) {
      fallback
    }
  }

  var armed: Boolean
    get() = prefs.getBoolean("armed", false)
    set(value) {
      prefs.edit().putBoolean("armed", value).apply()
    }

  var enterAt: Long?
    get() = prefs.getLong("enterAt", -1L).takeIf { it > 0 }
    set(value) {
      if (value == null) prefs.edit().remove("enterAt").remove("stayStart").apply()
      else prefs.edit().putLong("enterAt", value).apply()
    }

  /** When the open stay began; check-ins move `enterAt` on, never this. */
  var stayStart: Long?
    get() = prefs.getLong("stayStart", -1L).takeIf { it > 0 && enterAt != null }
    set(value) = prefs.edit().putLong("stayStart", value ?: -1L).apply()

  /** Merge fresh day aggregates into the queue: same day → sum dwell, OR
   *  night, sum samples. The RN tier's mergeIntoQueue, verbatim. */
  fun queueDays(days: List<PresenceFold.DayAggregate>) = synchronized(LOCK) {
    val observed = observedNow()
    val byDay = LinkedHashMap<String, JSONObject>()
    val existing = JSONArray(prefs.getString("queue", "[]") ?: "[]")
    for (i in 0 until existing.length()) {
      val o = existing.getJSONObject(i)
      byDay[o.getString("day")] = o
    }
    for (d in days) {
      val prior = byDay[d.day]
      if (prior == null) {
        byDay[d.day] = JSONObject()
          .put("day", d.day)
          .put("dwellMinutes", d.dwellMinutes)
          .put("nightPresent", d.nightPresent)
          .put("samples", 1)
          .put("observedAtMillis", observed)
      } else {
        prior.put("dwellMinutes", prior.getInt("dwellMinutes") + d.dwellMinutes)
        prior.put("nightPresent", prior.getBoolean("nightPresent") || d.nightPresent)
        prior.put("samples", prior.getInt("samples") + 1)
        // A changed day is sealed again, as of now.
        prior.put("observedAtMillis", observed)
      }
    }
    val next = JSONArray()
    byDay.values.forEach { next.put(it) }
    prefs.edit().putString("queue", next.toString()).apply()
  }

  /** A mocked fix's day: merged into the queue with no dwell and the
   *  mock-location flag set — evidence OF fraud is worth more to the watch
   *  than silence. The flag survives a later merge (the RN tier's rule). */
  fun queueFlagged(day: String, nightPresent: Boolean) = synchronized(LOCK) {
    val observed = observedNow()
    val byDay = LinkedHashMap<String, JSONObject>()
    val existing = pendingQueue()
    for (i in 0 until existing.length()) {
      val o = existing.getJSONObject(i)
      byDay[o.getString("day")] = o
    }
    val prior = byDay[day]
    val integrity = JSONObject().put("mockLocation", true)
    if (prior == null) {
      byDay[day] = JSONObject()
        .put("day", day)
        .put("dwellMinutes", 0)
        .put("nightPresent", nightPresent)
        .put("samples", 1)
        .put("integrity", integrity)
        .put("observedAtMillis", observed)
    } else {
      prior.put("nightPresent", prior.getBoolean("nightPresent") || nightPresent)
      prior.put("samples", prior.getInt("samples") + 1)
      prior.put("integrity", integrity)
      prior.put("observedAtMillis", observed)
    }
    val next = JSONArray()
    byDay.values.forEach { next.put(it) }
    prefs.edit().putString("queue", next.toString()).apply()
  }

  fun pendingQueue(): JSONArray = try {
    JSONArray(prefs.getString("queue", "[]") ?: "[]")
  } catch (_: Exception) {
    JSONArray()
  }

  fun clearQueue() = synchronized(LOCK) {
    prefs.edit().putString("queue", "[]").apply()
  }
}
