import Flutter
import Foundation

/// Channel side of the background presence tier (`kyc_sdk_flutter/presence`).
/// Dart owns the permission escalation, but the step up to "Always" is asked
/// here (PresenceAlwaysPermission): geolocator never asks for it on iOS. The
/// rest of this side persists the reporter config and arms/disarms the region.
final class PresenceChannel: NSObject {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kyc_sdk_flutter/presence",
      binaryMessenger: registrar.messenger()
    )
    let instance = PresenceChannel()
    channel.setMethodCallHandler { call, result in
      instance.handle(call, result: result)
    }
    // A relaunch for a region event lands here before any Dart runs: stand
    // the delegate up again so Core Location has somewhere to deliver.
    PresenceMonitor.shared.reattachIfArmed()
    // Registration is only accepted while the app finishes launching, which
    // is when plugins register. A no-op unless the host opted in.
    PresenceMonitor.shared.registerCheckInTask()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "enablePresence":
      guard let args = call.arguments as? [String: Any],
            let lat = args["lat"] as? Double,
            let lng = args["lng"] as? Double,
            let baseUrl = args["baseUrl"] as? String,
            let apiKey = args["apiKey"] as? String,
            let externalUserId = args["externalUserId"] as? String
      else {
        result(false)
        return
      }
      let config = PresenceStore.Config(
        lat: lat, lng: lng,
        radius: (args["radius"] as? NSNumber)?.doubleValue ?? 250,
        baseUrl: baseUrl, apiKey: apiKey, externalUserId: externalUserId,
        presenceToken: args["presenceToken"] as? String
      )
      PresenceMonitor.shared.arm(config: config) { ok in
        if ok {
          PresenceStore.saveConfig(config)
          PresenceMonitor.shared.scheduleCheckIns()
        } else {
          PresenceStore.armed = false
        }
        result(ok)
      }
    case "setPresenceToken":
      // True: the Keychain (this device only) has it, and Dart keeps no copy
      // in its documents file, which iCloud backs up.
      if let args = call.arguments as? [String: Any],
         let externalUserId = args["externalUserId"] as? String,
         let token = args["presenceToken"] as? String {
        result(PresenceStore.updatePresenceToken(externalUserId: externalUserId, token: token))
      } else {
        result(false)
      }
    case "readPresenceToken":
      guard let args = call.arguments as? [String: Any],
            let externalUserId = args["externalUserId"] as? String
      else {
        result(nil)
        return
      }
      let read = PresenceStore.presenceToken(externalUserId: externalUserId)
      result(["token": read.token as Any, "held": read.held])
    case "forgetPresenceToken":
      if let args = call.arguments as? [String: Any],
         let externalUserId = args["externalUserId"] as? String {
        PresenceStore.forgetPresenceToken(externalUserId: externalUserId)
      }
      result(nil)
    case "setPresenceUserToken":
      // Called only after Dart's identity check; checked again here against
      // the armed user, so a token for anyone else is never kept.
      guard let args = call.arguments as? [String: Any],
            let externalUserId = args["externalUserId"] as? String,
            let token = args["token"] as? String,
            let expiresAt = (args["expiresAtMillis"] as? NSNumber)?.int64Value,
            let config = PresenceStore.loadConfig(),
            config.externalUserId == externalUserId,
            PresenceUserToken.wellFormed(token)
      else {
        result(false)
        return
      }
      let saved = PresenceStore.saveUserToken(
        PresenceUserToken.Record(
          externalUserId: externalUserId, token: token, expiresAtMillis: expiresAt, stale: false))
      if saved {
        PresenceStore.userTokensInUse = true
        // The days held while there was no token go now.
        PresenceMonitor.shared.flushQueue()
      }
      result(saved)
    case "presenceArmedReporter":
      // setUserToken after a cold start (a silent push): the user and key the
      // background tier reports for. The key is publishable by design.
      guard PresenceStore.armed, let config = PresenceStore.loadConfig() else {
        result(nil)
        return
      }
      result(["externalUserId": config.externalUserId, "apiKey": config.apiKey])
    case "registerPresenceDevice":
      // Right after an address verification's 202, from Dart, which fetched
      // the presence user token.
      guard let args = call.arguments as? [String: Any],
            let baseUrl = args["baseUrl"] as? String, let apiKey = args["apiKey"] as? String,
            let externalUserId = args["externalUserId"] as? String,
            let presenceToken = args["presenceToken"] as? String
      else {
        result("keep")
        return
      }
      DispatchQueue.global(qos: .utility).async {
        PresenceDeviceClient.register(
          baseUrl: baseUrl, apiKey: apiKey, externalUserId: externalUserId, userToken: args["userToken"] as? String,
          presenceToken: presenceToken, stableId: DeviceIntelChannel.stableId()
        ) { outcome in
          DispatchQueue.main.async { result(outcome) }
        }
      }
    case "setPresenceHeldDeadline":
      PresenceStore.heldDeadlineDay = (call.arguments as? [String: Any])?["day"] as? String
      result(nil)
    case "forgetPresenceDevice":
      if let args = call.arguments as? [String: Any], let externalUserId = args["externalUserId"] as? String {
        PresenceStore.forgetDevice(externalUserId: externalUserId)
      }
      result(nil)
    case "clearPresenceUserToken":
      if let args = call.arguments as? [String: Any],
         let externalUserId = args["externalUserId"] as? String {
        PresenceStore.clearUserToken(externalUserId: externalUserId)
      }
      result(nil)
    case "presenceCheckIn":
      // The Dart reporter saw an inside fix on app open. iOS confirms it with
      // its own region state rather than trusting the coordinates twice.
      PresenceMonitor.shared.requestCheckIn()
      result(PresenceStore.armed)
    case "disablePresence":
      PresenceMonitor.shared.cancelCheckIns()
      PresenceMonitor.shared.disarm()
      PresenceStore.clear()
      result(nil)
    case "requestAlwaysLocation":
      PresenceAlwaysPermission.shared.request { word in result(word) }
    case "isPresenceArmed":
      result(PresenceMonitor.shared.isArmed)
    case "presenceStay":
      // The open stay, for the host to show. Nil with no stay open.
      guard PresenceStore.armed, let enterAt = PresenceStore.enterAt else {
        result(nil)
        return
      }
      result([
        "since": PresenceStore.stayStart ?? enterAt,
        "nextReportAt": PresenceFold.nextCheckpointAt(
          enterAt: enterAt, stayStart: PresenceStore.stayStart) as Any,
      ])
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
