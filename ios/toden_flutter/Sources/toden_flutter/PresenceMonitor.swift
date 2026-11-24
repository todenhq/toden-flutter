import CoreLocation
import Foundation
import UIKit

/// Region monitoring for the background presence tier. iOS relaunches the app
/// for region crossings even after termination; plugin registration re-creates
/// this monitor whenever an armed config exists, so the delegate is standing
/// when Core Location redelivers the event. ENTER stamps a timestamp; EXIT
/// folds the dwell span (PresenceFold) into per-day aggregates and flushes
/// them — the only data that ever leaves the device. Mirrors Android's
/// PresenceGeofenceReceiver + PresenceGeofencer.
final class PresenceMonitor: NSObject, CLLocationManagerDelegate {
  static let shared = PresenceMonitor()
  static let regionId = "myaza-kyc-presence"

  var manager: CLLocationManager?

  /// Called from plugin registration: stand the delegate up again when a
  /// config is armed, so relaunch-delivered events have somewhere to land.
  func reattachIfArmed() {
    guard PresenceStore.armed, PresenceStore.loadConfig() != nil else { return }
    ensureManager()
    // Every launch or relaunch is a free "still here" check-in: ask iOS
    // whether the phone is inside, and didDetermineState records the stay.
    requestCheckIn()
  }

  /// Asks Core Location whether the phone is inside the region right now. The
  /// answer arrives in didDetermineState, which records the running stay. Uses
  /// the cell and wifi signals region monitoring already watches, not GPS.
  func requestCheckIn() {
    guard PresenceStore.armed else { return }
    ensureManager()
    guard let manager = manager else { return }
    for region in manager.monitoredRegions where region.identifier == PresenceMonitor.regionId {
      manager.requestState(for: region)
    }
  }

  private func ensureManager() {
    if manager == nil {
      // Core Location requires the manager be created on a run-loop thread.
      if Thread.isMainThread {
        manager = CLLocationManager()
        manager?.delegate = self
      } else {
        DispatchQueue.main.sync {
          self.manager = CLLocationManager()
          self.manager?.delegate = self
        }
      }
    }
  }

  func arm(config: PresenceStore.Config, completion: @escaping (Bool) -> Void) {
    guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
      completion(false)
      return
    }
    ensureManager()
    guard let manager = manager else {
      completion(false)
      return
    }
    let radius = min(config.radius, manager.maximumRegionMonitoringDistance)
    let region = CLCircularRegion(
      center: CLLocationCoordinate2D(latitude: config.lat, longitude: config.lng),
      radius: radius,
      identifier: PresenceMonitor.regionId
    )
    region.notifyOnEntry = true
    region.notifyOnExit = true
    manager.startMonitoring(for: region)
    // Being at home when the fence arms should stamp immediately; iOS answers
    // via didDetermineState rather than a synthetic entry event.
    manager.requestState(for: region)
    completion(true)
  }

  func disarm() {
    ensureManager()
    guard let manager = manager else { return }
    for region in manager.monitoredRegions where region.identifier == PresenceMonitor.regionId {
      manager.stopMonitoring(for: region)
    }
  }

  var isArmed: Bool {
    ensureManager()
    guard PresenceStore.armed else { return false }
    return manager?.monitoredRegions.contains { $0.identifier == PresenceMonitor.regionId } ?? false
  }

  // MARK: - CLLocationManagerDelegate

  func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    guard region.identifier == PresenceMonitor.regionId, PresenceStore.armed else { return }
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    PresenceStore.enterAt = now
    PresenceStore.stayStart = now
    // Ask for a refresh soon after the arrival, not at the next two-hourly one.
    scheduleCheckIns()
    checkFixIsReal()
  }

  func locationManager(
    _ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion
  ) {
    guard region.identifier == PresenceMonitor.regionId, PresenceStore.armed else { return }
    // Inside is a confirmed "still here": no open stamp opens one (the
    // arm-time answer, exactly like Android's INITIAL_TRIGGER_ENTER); a stay
    // open long enough is recorded so far and restarted (PresenceCheckIn).
    if state == .inside {
      recordCheckIn(atMs: Int64(Date().timeIntervalSince1970 * 1000))
      checkFixIsReal()
    }
  }

  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    guard region.identifier == PresenceMonitor.regionId, PresenceStore.armed else { return }
    guard let enteredAt = PresenceStore.enterAt else { return }
    PresenceStore.enterAt = nil
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    let offsetMinutes = TimeZone.current.secondsFromGMT(
      for: Date(timeIntervalSince1970: Double(enteredAt) / 1000)
    ) / 60
    let days = PresenceFold.foldSpanIntoDays(enterMs: enteredAt, exitMs: now, offsetMinutes: offsetMinutes)
    if days.isEmpty { return }
    PresenceStore.queueDays(days)
    flushQueue()
  }

  /// Posts the pending queue, oldest day first in chunks of 31 (PresenceFlush).
  /// The relaunched-for-an-event process gets only seconds, so the requests run
  /// under a background task. With user tokens in use, a missing, expired or
  /// stale token, or a locked Keychain, means no post and the queue is kept;
  /// a refusal keeps the queue and marks the token stale, so the app fetches
  /// a new one when it is next opened (or the host's silent push hands one).
  func flushQueue(refreshed: Bool = false) {
    // Before the first unlock the Keychain holds the presenceToken back: wait,
    // rather than post without it.
    guard let config = PresenceStore.loadConfig(), !config.presenceTokenHeld else { return }
    let pending = PresenceStore.pendingQueue()
    if pending.isEmpty { return }
    let decision = PresenceUserToken.decide(
      inUse: PresenceStore.userTokensInUse,
      read: PresenceStore.userTokensInUse ? PresenceStore.readUserToken() : .missing,
      externalUserId: config.externalUserId,
      nowMillis: Int64(Date().timeIntervalSince1970 * 1000)
    )
    let userToken: String?
    switch decision {
    case .skip:
      // No usable token: a registered presence device signs for a fresh one.
      guard !refreshed else { return }
      PresenceDeviceClient.refreshIfDue(config: config) { ok in
        if ok { self.flushQueue(refreshed: true) }
      }
      return
    case .noHeader: userToken = nil
    case .use(let token): userToken = token
    }

    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    let finish = {
      if backgroundTask != .invalid {
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
      }
    }
    backgroundTask = UIApplication.shared.beginBackgroundTask(expirationHandler: finish)

    PresenceFlush.run(
      queue: pending,
      post: { chunk, completion in
        self.post(chunk: chunk, config: config, userToken: userToken) { status in
          // A 400 can never succeed, so the chunk is dropped; say so (never the token).
          if status == 400 { NSLog("[toden] presence: the server refused %ld queued days (400); dropped", chunk.count) }
          completion(status)
        }
      },
      done: { result in
        if result.refused, let sent = userToken { PresenceStore.markUserTokenStale(sentToken: sent) }
        // On a watch held past its deadline, days after it stay queued: a
        // reviewer's extension may still let them count.
        PresenceStore.removeFromQueue(
          PresenceDeviceRules.removableAfterSend(result.sent, heldDeadlineDay: PresenceStore.heldDeadlineDay)
            + result.dropped)
        finish()
      }
    )
  }

  private func post(
    chunk: [[String: Any]], config: PresenceStore.Config, userToken: String?,
    completion: @escaping (Int?) -> Void
  ) {
    var observations = chunk.map { PresenceReportProof.wire($0) }
    // Seals are read only beside a user token, so a post without one is
    // exactly as before.
    var sealDeviceId: String?
    if userToken != nil, let device = PresenceStore.readDevice(), device.registered,
       device.externalUserId == config.externalUserId, let deviceId = device.deviceId, let tag = device.tag,
       PresenceSeal.apply(
         queued: chunk, observations: &observations, deviceId: deviceId, externalUserId: config.externalUserId,
         sign: { PresenceDeviceKey.sign(tag: tag, text: $0) })
    {
      sealDeviceId = deviceId
    }
    let posted = observations
    // Best-effort: what cannot be proved is left off and the report still goes.
    PresenceReportProof.prove(config: config, observations: posted) { proof in
      var fields = PresenceWire.body(
        externalUserId: config.externalUserId,
        presenceToken: config.presenceToken,
        observations: posted
      )
      if let id = sealDeviceId { fields["sealDeviceId"] = id }
      proof.forEach { fields[$0.key] = $0.value }
      guard let url = URL(string: "\(config.baseUrl)/api/v1/address/observations"),
            let body = try? JSONSerialization.data(withJSONObject: fields)
      else {
        completion(nil)
        return
      }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.timeoutInterval = 8
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
      if let userToken = userToken {
        request.setValue(userToken, forHTTPHeaderField: PresenceUserToken.header)
      }
      request.httpBody = body
      URLSession.shared.dataTask(with: request) { _, response, _ in
        completion((response as? HTTPURLResponse)?.statusCode)
      }.resume()
    }
  }
}
