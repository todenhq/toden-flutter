import Foundation

/// The request body for a background flush, kept to one function. The token
/// proves the report comes from the device that captured the pin; without one
/// the server counts the report at the foreground tier. Mirrors Android's
/// PresenceWire.kt.
enum PresenceWire {
  static func body(
    externalUserId: String, presenceToken: String?, observations: [[String: Any]]
  ) -> [String: Any] {
    var body: [String: Any] = ["externalUserId": externalUserId, "observations": observations]
    if let token = presenceToken, !token.isEmpty { body["presenceToken"] = token }
    return body
  }

  /// One queued day as the server receives it. Seals sign this, so the
  /// background flush and the seal can never disagree on a row.
  static func observation(_ entry: [String: Any], emulator: Bool) -> [String: Any] {
    var out: [String: Any] = [
      "day": entry["day"] as? String ?? "",
      "source": "geofence",
      "dwellMinutes": entry["dwellMinutes"] as? Int ?? 1,
      "nightPresent": entry["nightPresent"] as? Bool ?? false,
      "samples": entry["samples"] as? Int ?? 1,
    ]
    var integrity: [String: Any] = [:]
    if entry["mockLocation"] as? Bool == true { integrity["mockLocation"] = true }
    if emulator { integrity["emulator"] = true }
    if !integrity.isEmpty { out["integrity"] = integrity }
    return out
  }

  /// One observation's line of the report digest (PresenceReportProof), which
  /// a seal also signs (PresenceDevice).
  static func digestRow(_ o: [String: Any]) -> String {
    let flag: (Bool) -> Int = { $0 ? 1 : 0 }
    let integrity = o["integrity"] as? [String: Any]
    return [
      o["day"] as? String ?? "",
      o["source"] as? String ?? "",
      String(o["dwellMinutes"] as? Int ?? 0),
      String(flag(o["nightPresent"] as? Bool ?? false)),
      String(o["samples"] as? Int ?? 1),
      String(flag(integrity?["mockLocation"] as? Bool ?? false)),
      String(flag(integrity?["emulator"] as? Bool ?? false)),
    ].joined(separator: "|")
  }
}
