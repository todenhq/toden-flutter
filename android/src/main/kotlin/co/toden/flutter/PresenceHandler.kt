package co.toden.flutter

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result
import kotlin.concurrent.thread

/**
 * Channel side of the background presence tier (`kyc_sdk_flutter/presence`).
 * Dart owns the permission escalation, but the step up to "Allow all the
 * time" is asked natively ([PresenceAlwaysPermission]): geolocator's own
 * request is ignored by Android 11 and later. This side persists the reporter
 * config and arms/disarms the fence.
 */
class PresenceHandler(private val context: Context) {
  /** Returns true when the call was one of ours. */
  fun handle(call: MethodCall, result: Result): Boolean {
    when (call.method) {
      "enablePresence" -> {
        val lat = call.argument<Double>("lat")
        val lng = call.argument<Double>("lng")
        val baseUrl = call.argument<String>("baseUrl")
        val apiKey = call.argument<String>("apiKey")
        val externalUserId = call.argument<String>("externalUserId")
        if (lat == null || lng == null || baseUrl == null || apiKey == null || externalUserId == null) {
          result.success(false)
          return true
        }
        val store = PresenceStore(context)
        val config = PresenceStore.Config(
          lat = lat,
          lng = lng,
          radius = (call.argument<Number>("radius") ?: 250).toDouble(),
          baseUrl = baseUrl,
          apiKey = apiKey,
          externalUserId = externalUserId,
          playIntegrityProject = call.argument<String>("playIntegrityProject"),
          emulator = call.argument<Boolean>("emulator") == true,
          presenceToken = call.argument<String>("presenceToken"),
        )
        PresenceGeofencer.arm(context, config) { ok ->
          if (ok) {
            store.saveConfig(config)
            PresenceCheckInWorker.schedule(context)
          } else {
            store.armed = false
          }
          result.success(ok)
        }
      }
      // An app-open reading the Dart reporter already took. Inside, it records
      // the running stay now instead of when the person leaves. A no-op unless
      // the background tier is armed. Off the main thread: it may flush.
      "presenceCheckIn" -> {
        val lat = call.argument<Double>("lat")
        val lng = call.argument<Double>("lng")
        val timestamp = call.argument<Number>("timestamp")?.toLong()
        val store = PresenceStore(context)
        val config = store.loadConfig()
        if (lat == null || lng == null || timestamp == null || !store.armed || config == null) {
          result.success(false)
          return true
        }
        val fix = PresenceSampler.Fix(
          lat = lat,
          lng = lng,
          accuracy = call.argument<Number>("accuracy")?.toDouble(),
          timestamp = timestamp,
          mocked = call.argument<Boolean>("mocked"),
        )
        thread(name = "myaza-presence-checkin") { PresenceCheckInWorker.applyCheckIn(store, config, fix) }
        result.success(true)
      }
      "disablePresence" -> {
        PresenceCheckInWorker.cancel(context)
        PresenceGeofencer.disarm(context)
        PresenceStore(context).clear()
        result.success(null)
      }
      // True: no-backup storage has it, and Dart keeps no copy in its
      // documents file, which Auto Backup copies.
      "setPresenceToken" -> {
        val externalUserId = call.argument<String>("externalUserId")
        val token = call.argument<String>("presenceToken")
        result.success(
          externalUserId != null && token != null && PresenceStore(context).updatePresenceToken(externalUserId, token),
        )
      }
      "readPresenceToken" -> {
        val externalUserId = call.argument<String>("externalUserId")
        if (externalUserId == null) {
          result.success(null)
        } else {
          val (token, held) = PresenceStore(context).presenceToken(externalUserId)
          result.success(mapOf("token" to token, "held" to held))
        }
      }
      "forgetPresenceToken" -> {
        call.argument<String>("externalUserId")?.let { PresenceStore(context).forgetPresenceToken(it) }
        result.success(null)
      }
      // Called only after Dart's identity check; checked again here against
      // the armed user, so a token for anyone else is never kept.
      "setPresenceUserToken" -> {
        val externalUserId = call.argument<String>("externalUserId")
        val token = call.argument<String>("token")
        val expiresAt = call.argument<Number>("expiresAtMillis")?.toLong()
        val store = PresenceStore(context)
        val config = store.loadConfig()
        if (externalUserId == null || token == null || expiresAt == null || config == null ||
          config.externalUserId != externalUserId || !PresenceUserToken.wellFormed(token)
        ) {
          result.success(false)
          return true
        }
        val saved = store.saveUserToken(PresenceUserToken.Record(externalUserId, token, expiresAt, stale = false))
        if (saved) {
          store.userTokensInUse = true
          // The days held while there was no token go now.
          thread(name = "myaza-presence-token-flush") { PresenceGeofencer.flushQueue(store) }
        }
        result.success(saved)
      }
      // setUserToken after a cold start (a silent push): the user and key the
      // background tier reports for. The key is publishable by design.
      "presenceArmedReporter" -> {
        val store = PresenceStore(context)
        val config = if (store.armed || store.serviceEnabled) store.loadConfig() else null
        result.success(config?.let { mapOf("externalUserId" to it.externalUserId, "apiKey" to it.apiKey) })
      }
      // Right after an address verification's 202, from Dart, which fetched
      // the presence user token. Network, so off the main thread.
      "registerPresenceDevice" -> {
        val baseUrl = call.argument<String>("baseUrl")
        val apiKey = call.argument<String>("apiKey")
        val externalUserId = call.argument<String>("externalUserId")
        val userToken = call.argument<String>("userToken")
        val presenceToken = call.argument<String>("presenceToken")
        if (baseUrl == null || apiKey == null || externalUserId == null || presenceToken == null) {
          result.success("keep")
          return true
        }
        val main = android.os.Handler(android.os.Looper.getMainLooper())
        thread(name = "myaza-presence-device") {
          val outcome = try {
            PresenceDeviceClient.register(PresenceStore(context), baseUrl, apiKey, externalUserId, userToken, presenceToken)
          } catch (_: Exception) {
            "keep"
          }
          main.post { result.success(outcome) }
        }
      }
      "setPresenceHeldDeadline" -> {
        PresenceStore(context).heldDeadlineDay = call.argument<String>("day")
        result.success(null)
      }
      "forgetPresenceDevice" -> {
        call.argument<String>("externalUserId")?.let { PresenceStore(context).forgetDevice(it) }
        result.success(null)
      }
      "clearPresenceUserToken" -> {
        val externalUserId = call.argument<String>("externalUserId")
        if (externalUserId != null) PresenceStore(context).clearUserToken(externalUserId)
        result.success(null)
      }
      "isPresenceArmed" -> result.success(PresenceStore(context).armed)
      // The open stay, for the host to show: when the person arrived and when
      // the next check-in can record it. Null with no stay open.
      "presenceStay" -> {
        val store = PresenceStore(context)
        val enterAt = store.enterAt
        result.success(
          if (!store.armed || enterAt == null) null
          else mapOf(
            "since" to (store.stayStart ?: enterAt),
            "nextReportAt" to PresenceFold.nextCheckpointAt(enterAt, store.stayStart),
          ),
        )
      }
      "enablePresenceService" -> {
        val lat = call.argument<Double>("lat")
        val lng = call.argument<Double>("lng")
        val baseUrl = call.argument<String>("baseUrl")
        val apiKey = call.argument<String>("apiKey")
        val externalUserId = call.argument<String>("externalUserId")
        val notification = call.argument<Map<String, Any?>>("notification")
        if (lat == null || lng == null || baseUrl == null || apiKey == null ||
          externalUserId == null || notification == null
        ) {
          result.success("failed")
          return true
        }
        if (!serviceDeclared()) {
          result.success("not_declared")
          return true
        }
        val store = PresenceStore(context)
        store.saveConfig(
          PresenceStore.Config(
            lat = lat,
            lng = lng,
            radius = (call.argument<Number>("radius") ?: 250).toDouble(),
            baseUrl = baseUrl,
            apiKey = apiKey,
            externalUserId = externalUserId,
            playIntegrityProject = call.argument<String>("playIntegrityProject"),
            emulator = call.argument<Boolean>("emulator") == true,
            presenceToken = call.argument<String>("presenceToken"),
          ),
        )
        store.saveNotification(
          PresenceStore.NotificationConfig(
            title = notification["title"] as? String ?: "Address verification in progress",
            body = notification["body"] as? String ?: "Open the app to see your progress.",
            channelId = notification["channelId"] as? String ?: "myaza_kyc_presence",
            channelName = notification["channelName"] as? String ?: "Address verification",
            channelDescription = notification["channelDescription"] as? String,
            color = (notification["color"] as? Number)?.toInt(),
          ),
        )
        store.serviceEnabled = true
        val started = PresenceForegroundService.start(context)
        if (!started) store.serviceEnabled = false
        result.success(if (started) "started" else "failed")
      }
      "disablePresenceService" -> {
        PresenceStore(context).serviceEnabled = false
        PresenceForegroundService.stop(context)
        result.success(null)
      }
      "isPresenceServiceRunning" ->
        result.success(PresenceForegroundService.running && PresenceStore(context).serviceEnabled)
      else -> return false
    }
    return true
  }

  /**
   * The host declares the service and its permissions itself (a location
   * foreground service changes the app's review posture). Both are normal,
   * install-time permissions, so checkSelfPermission answers "declared or
   * not" — and an undeclared service resolves to nothing.
   */
  private fun serviceDeclared(): Boolean {
    val resolved = context.packageManager.resolveService(
      Intent(context, PresenceForegroundService::class.java), 0,
    ) != null
    if (!resolved) return false
    val granted = { permission: String ->
      ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }
    if (Build.VERSION.SDK_INT >= 28 && !granted(Manifest.permission.FOREGROUND_SERVICE)) return false
    if (Build.VERSION.SDK_INT >= 34 && !granted("android.permission.FOREGROUND_SERVICE_LOCATION")) return false
    return true
  }
}
