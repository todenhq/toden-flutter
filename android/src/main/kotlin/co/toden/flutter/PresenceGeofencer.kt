package co.toden.flutter

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * Arms/disarms the OS geofence and owns the flush wire. Shared by the channel
 * handler (enable/disable), the boot receiver (re-arm after restart) and the
 * geofence receiver (flush on exit) — one implementation, three callers.
 */
object PresenceGeofencer {
  const val GEOFENCE_ID = "myaza-kyc-presence"

  private fun pendingIntent(context: Context): PendingIntent {
    val intent = Intent(context, PresenceGeofenceReceiver::class.java)
    val mutable =
      if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
    return PendingIntent.getBroadcast(
      context, 4471, intent, PendingIntent.FLAG_UPDATE_CURRENT or mutable,
    )
  }

  /** Registers the fence. The caller has already obtained the always
   *  permission Dart-side; a SecurityException here means it was revoked
   *  since, which reports as a plain failure. */
  @SuppressLint("MissingPermission")
  fun arm(context: Context, config: PresenceStore.Config, onDone: (Boolean) -> Unit) {
    try {
      val fence = Geofence.Builder()
        .setRequestId(GEOFENCE_ID)
        .setCircularRegion(config.lat, config.lng, config.radius.toFloat())
        .setExpirationDuration(Geofence.NEVER_EXPIRE)
        .setTransitionTypes(
          Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT,
        )
        .build()
      val request = GeofencingRequest.Builder()
        // Being at home when the fence arms should stamp immediately.
        .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
        .addGeofence(fence)
        .build()
      LocationServices.getGeofencingClient(context)
        .addGeofences(request, pendingIntent(context))
        .addOnSuccessListener { onDone(true) }
        .addOnFailureListener { onDone(false) }
    } catch (_: Exception) {
      onDone(false)
    }
  }

  fun disarm(context: Context) {
    try {
      LocationServices.getGeofencingClient(context).removeGeofences(pendingIntent(context))
    } catch (_: Exception) {
      // Not armed, or play services absent — either way, disarmed.
    }
  }

  /**
   * Posts the pending queue, oldest day first in chunks of 31 ([PresenceFlush]).
   * Blocking HTTP on purpose — every caller is already off the main thread (a
   * receiver's goAsync worker or the channel handler's executor). With user
   * tokens in use, a missing, expired or stale token means no post and the
   * queue is kept; a refusal keeps the queue and marks the token stale, so the
   * app fetches a new one when it is next opened (or a silent push hands one).
   */
  fun flushQueue(store: PresenceStore) {
    val config = store.loadConfig() ?: return
    // Before the first unlock no-backup storage holds the presenceToken back:
    // wait, rather than post without it.
    if (config.presenceTokenHeld) return
    val pending = store.pendingQueue()
    if (pending.length() == 0) return
    fun decide(): PresenceUserToken.Decision {
      val inUse = store.userTokensInUse
      return PresenceUserToken.decide(
        inUse,
        if (inUse) store.readUserToken() else PresenceUserToken.Read.Missing,
        config.externalUserId,
        System.currentTimeMillis(),
      )
    }
    var decision = decide()
    // No usable token: a registered presence device signs for a fresh one.
    if (decision is PresenceUserToken.Decision.Skip && PresenceDeviceClient.refreshIfDue(store, config)) {
      decision = decide()
    }
    val userToken = when (decision) {
      is PresenceUserToken.Decision.Skip -> return
      is PresenceUserToken.Decision.NoHeader -> null
      is PresenceUserToken.Decision.Use -> decision.token
    }
    val result = PresenceFlush.run(pending) { chunk ->
      post(store, config, chunk, userToken).also { status ->
        // A 400 can never succeed, so the chunk is dropped; say so (never the token).
        if (status == 400) Log.w("TodenPresence", "the server refused ${chunk.size} queued days (400); dropped")
      }
    }
    if (result.refused && userToken != null) store.markUserTokenStale(userToken)
    // On a watch held past its deadline, days after it stay queued: a
    // reviewer's extension may still let them count.
    store.removeFromQueue(PresenceDeviceRules.removableAfterSend(result.sent, store.heldDeadlineDay) + result.dropped)
  }

  /** One chunk; the status, or null when nothing came back. */
  private fun post(
    store: PresenceStore,
    config: PresenceStore.Config,
    chunk: List<JSONObject>,
    userToken: String?,
  ): Int? {
    val observations = sourcedGeofence(JSONArray(chunk), config.emulator)
    // Seals are read only beside a user token, so a post without one is
    // exactly as before.
    val device = store.readDevice()?.takeIf { it.registered && it.externalUserId == config.externalUserId }
    val sealed = userToken != null && device != null &&
      PresenceSeal.apply(chunk, observations, device.deviceId!!, config.externalUserId) { text ->
        PresenceDeviceKey.sign(device.alias!!, text)
      }
    val body = PresenceWire.body(config.externalUserId, config.presenceToken, observations)
    if (sealed) body.put("sealDeviceId", device!!.deviceId)
    // Best-effort: what cannot be proved is left off and the report still goes.
    PresenceReportProof.addTo(body, store.appContext, config, observations)
    var connection: HttpURLConnection? = null
    return try {
      connection = URL("${config.baseUrl}/api/v1/address/observations")
        .openConnection() as HttpURLConnection
      connection.requestMethod = "POST"
      connection.connectTimeout = 8000
      connection.readTimeout = 8000
      connection.doOutput = true
      connection.setRequestProperty("Content-Type", "application/json")
      connection.setRequestProperty("Authorization", "Bearer ${config.apiKey}")
      if (userToken != null) connection.setRequestProperty(PresenceUserToken.HEADER, userToken)
      OutputStreamWriter(connection.outputStream).use { it.write(body.toString()) }
      connection.responseCode
    } catch (_: Exception) {
      // Best-effort: the queue is kept and the next transition retries it.
      null
    } finally {
      connection?.disconnect()
    }
  }

  private fun sourcedGeofence(queue: JSONArray, emulator: Boolean): JSONArray {
    val out = JSONArray()
    for (i in 0 until queue.length()) {
      val o = queue.getJSONObject(i)
      val wire = JSONObject()
        .put("day", o.getString("day"))
        .put("source", "geofence")
        .put("dwellMinutes", o.getInt("dwellMinutes"))
        .put("nightPresent", o.getBoolean("nightPresent"))
        .put("samples", o.getInt("samples"))
      // A mocked fix's day rides its flag through to the server.
      // A copy: the queue entry itself must stay as stored, so a posted day
      // can be found and removed from the queue afterwards.
      val integrity = JSONObject(o.optJSONObject("integrity")?.toString() ?: "{}")
      if (emulator) integrity.put("emulator", true)
      if (integrity.length() > 0) wire.put("integrity", integrity)
      out.put(wire)
    }
    return out
  }
}
