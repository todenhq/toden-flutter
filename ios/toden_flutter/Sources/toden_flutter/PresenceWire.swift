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
}
