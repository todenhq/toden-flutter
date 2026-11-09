import Foundation

/// Which background check-in identifiers this app lets the SDK use.
///
/// `BGTaskScheduler.register(forTaskWithIdentifier:)` crashes the app for an
/// identifier missing from `BGTaskSchedulerPermittedIdentifiers`, so only the
/// identifiers the host listed are ever registered. `co.toden.presence.checkin`
/// is the documented id; `co.myazahq.kyc.presence.checkin` is the earlier one,
/// still honoured so an app that lists only it keeps its check-ins.
///
/// Pure (no BackgroundTasks import) so the choice is unit tested on its own.
enum PresenceCheckInTaskIds {
  static let current = "co.toden.presence.checkin"
  static let legacy = "co.myazahq.kyc.presence.checkin"

  /// Every id the host listed, preferred first. Empty unless the `fetch`
  /// background mode is declared too, so an app missing either part
  /// registers nothing, as before.
  static func permitted(listed: [String]?, backgroundModes: [String]?) -> [String] {
    guard (backgroundModes ?? []).contains("fetch") else { return [] }
    let listed = listed ?? []
    return [current, legacy].filter { listed.contains($0) }
  }

  /// The id to submit refresh requests with: the new one when listed, else
  /// the legacy one, else none.
  static func submitId(listed: [String]?, backgroundModes: [String]?) -> String? {
    permitted(listed: listed, backgroundModes: backgroundModes).first
  }
}
