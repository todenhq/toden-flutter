import CoreLocation
import Foundation

/// A region event carries no location, so nothing in it says whether the
/// position was simulated. One fix is taken when the fence speaks, and iOS 15+
/// says whether software produced it. A simulated fix is reported flagged and
/// ends the stay, matching Android's sampler.
extension PresenceMonitor {
  func checkFixIsReal() {
    guard #available(iOS 15.0, *), PresenceStore.armed else { return }
    manager?.requestLocation()
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard #available(iOS 15.0, *), PresenceStore.armed, let fix = locations.last else { return }
    guard fix.sourceInformation?.isSimulatedBySoftware == true else { return }
    PresenceStore.enterAt = nil
    PresenceStore.stayStart = nil
    let (day, night) = PresenceSimulatedFix.localDay(
      atMs: Int64(fix.timestamp.timeIntervalSince1970 * 1000),
      offsetMinutes: TimeZone.current.secondsFromGMT(for: fix.timestamp) / 60
    )
    PresenceStore.queueFlagged(day: day, nightPresent: night)
    flushQueue()
  }

  /// CoreLocation requires this beside requestLocation. A failed read says
  /// nothing about the position.
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

enum PresenceSimulatedFix {
  private static let dayMs: Int64 = 86_400_000
  private static let hourMs: Int64 = 3_600_000

  /// The same offset arithmetic as the fold, so a flagged day and a folded day
  /// can never disagree.
  static func localDay(atMs: Int64, offsetMinutes: Int) -> (day: String, nightPresent: Bool) {
    let shifted = atMs + Int64(offsetMinutes) * 60_000
    var dayIndex = shifted / dayMs
    var remainder = shifted % dayMs
    if remainder < 0 {
      remainder += dayMs
      dayIndex -= 1
    }
    let hour = remainder / hourMs
    return (PresenceFold.civilFromDays(dayIndex), hour >= 20 || hour < 6)
  }
}
