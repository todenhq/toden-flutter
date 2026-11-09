import BackgroundTasks
import Foundation

/// "Still here" check-ins for the background presence tier. Region monitoring
/// only speaks when the person crosses the edge, so a stay was credited when
/// they LEFT: someone who hardly leaves home produced no background evidence,
/// and one exit the OS dropped capped a multi-day stay at its first 24 hours.
///
/// A check-in is iOS confirming the phone is inside (didDetermineState after
/// requestState). It happens on every launch or relaunch, when the Dart
/// reporter sees an inside fix on app open, and, when the HOST opts in, on a
/// periodic background refresh. Mirrors the RN SDK's presence/checkin.ts and
/// Android's PresenceCheckInWorker.
extension PresenceMonitor {
  /// The background refresh identifiers the host opted in to, preferred
  /// first. The host lists `co.toden.presence.checkin` (or the earlier
  /// `co.myazahq.kyc.presence.checkin`) under BGTaskSchedulerPermittedIdentifiers
  /// and adds the `fetch` background mode; without both nothing is registered
  /// (registering an undeclared identifier would crash the app at launch).
  static var permittedCheckInTaskIds: [String] {
    PresenceCheckInTaskIds.permitted(
      listed: Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String],
      backgroundModes: Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
    )
  }
  private static let checkInIntervalS: TimeInterval = 2 * 60 * 60

  /// Record a confirmed-inside reading: no open stay opens one; a stay open
  /// long enough is folded so far, queued, flushed and restarted.
  func recordCheckIn(atMs: Int64) {
    guard PresenceStore.armed else { return }
    let offsetMinutes = TimeZone.current.secondsFromGMT(
      for: Date(timeIntervalSince1970: Double(atMs) / 1000)
    ) / 60
    let out = PresenceFold.checkpointStay(
      enterAt: PresenceStore.enterAt, atMs: atMs, offsetMinutes: offsetMinutes,
      stayStart: PresenceStore.stayStart
    )
    PresenceStore.enterAt = out.enterAt
    PresenceStore.stayStart = out.stayStart
    if out.days.isEmpty { return }
    PresenceStore.queueDays(out.days)
    flushQueue()
  }

  /// Called once from plugin registration, which runs while the app finishes
  /// launching (the only time BGTaskScheduler accepts a registration).
  /// Each listed id gets the same handler, so a request submitted under the
  /// legacy id before an upgrade still runs.
  func registerCheckInTask() {
    for id in PresenceMonitor.permittedCheckInTaskIds {
      BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
        self.scheduleCheckIns()
        self.requestCheckIn()
        // requestState answers within moments; give the answer and its flush a
        // few seconds, well inside the refresh budget.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
          task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { task.setTaskCompleted(success: false) }
      }
    }
  }

  /// Ask iOS for the next refresh. iOS decides when it runs, usually around
  /// how often the person uses the app, so this narrows the gap rather than
  /// closing it on a schedule.
  func scheduleCheckIns() {
    let ids = PresenceMonitor.permittedCheckInTaskIds
    guard let id = ids.first, PresenceStore.armed else { return }
    // One pending refresh, under the preferred id: drop one left under the
    // other id (a legacy request from before the host listed the new one).
    for other in ids.dropFirst() {
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: other)
    }
    let request = BGAppRefreshTaskRequest(identifier: id)
    request.earliestBeginDate = Date(timeIntervalSinceNow: nextCheckInDelayS())
    try? BGTaskScheduler.shared.submit(request)
  }

  /// Ask for the refresh just after the open stay becomes recordable (five
  /// minutes past, so the run finds it due), never later than the usual two
  /// hours. With no stay open, the usual two hours.
  private func nextCheckInDelayS() -> TimeInterval {
    guard
      let due = PresenceFold.nextCheckpointAt(
        enterAt: PresenceStore.enterAt, stayStart: PresenceStore.stayStart)
    else { return PresenceMonitor.checkInIntervalS }
    let untilDue = Double(due) / 1000 - Date().timeIntervalSince1970 + 5 * 60
    return min(PresenceMonitor.checkInIntervalS, max(5 * 60, untilDue))
  }

  func cancelCheckIns() {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: PresenceCheckInTaskIds.current)
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: PresenceCheckInTaskIds.legacy)
  }
}
