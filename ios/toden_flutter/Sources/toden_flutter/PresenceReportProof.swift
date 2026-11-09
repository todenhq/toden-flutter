import CryptoKit
import Foundation

/// Proving a background presence report: which phone is reporting, and App
/// Attest's proof over these exact contents. The Dart reporter's twin
/// (presence_report_proof.dart). Best-effort: what cannot be proved is left
/// off and the report still goes.
///
/// `digestText` is the wire contract shared with kyc-core and every SDK; all
/// copies pin one test vector, so change them in the same commit.
enum PresenceReportProof {
  /// The whole step's bound: a relaunched process gets only seconds.
  private static let budget: TimeInterval = 5

  /// One queued day as the server receives it.
  static func wire(_ entry: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [
      "day": entry["day"] as? String ?? "",
      "source": "geofence",
      "dwellMinutes": entry["dwellMinutes"] as? Int ?? 1,
      "nightPresent": entry["nightPresent"] as? Bool ?? false,
      "samples": entry["samples"] as? Int ?? 1,
    ]
    var integrity: [String: Any] = [:]
    if entry["mockLocation"] as? Bool == true { integrity["mockLocation"] = true }
    #if targetEnvironment(simulator)
      integrity["emulator"] = true
    #endif
    if !integrity.isEmpty { out["integrity"] = integrity }
    return out
  }

  static func digestText(
    externalUserId: String, stableId: String?, deviceId: String?, observations: [[String: Any]]
  ) -> String {
    let flag: (Bool) -> Int = { $0 ? 1 : 0 }
    let rows = observations.map { o -> String in
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
    return (["toden-presence-report-v1", externalUserId, stableId ?? "", deviceId ?? ""] + rows)
      .joined(separator: "\n")
  }

  /// SHA-256(SHA-256(challenge || SHA-256(text))): what App Attest signs over.
  static func clientDataHash(challenge: Data, digestText: String) -> Data {
    var inner = Data(challenge)
    inner.append(Data(SHA256.hash(data: Data(digestText.utf8))))
    return Data(SHA256.hash(data: Data(SHA256.hash(data: inner))))
  }

  /// `device` and `attestation` for the body. Completes exactly once.
  static func prove(
    config: PresenceStore.Config, observations: [[String: Any]],
    done: @escaping ([String: Any]) -> Void
  ) {
    // Read, never create: a phone still locked since boot must not mint a new id.
    guard let stableId = KeychainItem.read(DeviceIntelChannel.stableIdAccount) else {
      done([:])
      return
    }
    let device: [String: Any] = ["device": ["stableId": stableId]]
    let once = Once(done)
    DispatchQueue.global().asyncAfter(deadline: .now() + budget) { once.finish(device) }
    let state = AppAttest.state()
    guard state["supported"] as? Bool == true else {
      once.finish(device)
      return
    }
    let stored = state["keyId"] as? String
    let text = digestText(
      externalUserId: config.externalUserId, stableId: stableId, deviceId: nil,
      observations: observations
    )
    fetchChallenge(config: config, keyId: stored) { challenge in
      guard let challenge,
            let id = challenge["challengeId"] as? String,
            let encoded = challenge["challenge"] as? String,
            let bytes = Data(base64Encoded: encoded)
      else {
        once.finish(device)
        return
      }
      let attest = (challenge["attest"] as? Bool == true) || stored == nil
      AppAttest.run(
        keyId: stored, clientDataHash: clientDataHash(challenge: bytes, digestText: text),
        attest: attest
      ) { out in
        guard let out, let keyId = out["keyId"] as? String else {
          once.finish(device)
          return
        }
        var block: [String: Any] = [
          "platform": "ios", "kind": "app_attest", "challengeId": id, "keyId": keyId,
        ]
        if let value = out["attestation"] { block["attestation"] = value }
        if let value = out["assertion"] { block["assertion"] = value }
        once.finish(device.merging(["attestation": block]) { a, _ in a })
      }
    }
  }

  private static func fetchChallenge(
    config: PresenceStore.Config, keyId: String?, done: @escaping ([String: Any]?) -> Void
  ) {
    var fields: [String: Any] = ["platform": "ios"]
    if let keyId { fields["keyId"] = keyId }
    guard let url = URL(string: "\(config.baseUrl)/api/v1/device/challenge"),
          let body = try? JSONSerialization.data(withJSONObject: fields)
    else {
      done(nil)
      return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 2
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = body
    URLSession.shared.dataTask(with: request) { data, response, _ in
      guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
            let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else {
        done(nil)
        return
      }
      done(json)
    }.resume()
  }

  /// The deadline and the proof race; whichever lands first answers.
  private final class Once {
    private let lock = NSLock()
    private var callback: (([String: Any]) -> Void)?
    init(_ callback: @escaping ([String: Any]) -> Void) { self.callback = callback }
    func finish(_ value: [String: Any]) {
      lock.lock()
      let run = callback
      callback = nil
      lock.unlock()
      run?(value)
    }
  }
}
