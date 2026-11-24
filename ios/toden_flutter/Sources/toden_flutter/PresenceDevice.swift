import CryptoKit
import Foundation

/// The presence device's rules, pure (user token design rev 4, sections 6b, 14).
///
/// After an address verification answers 202, Dart has this plugin make a P-256
/// key the Secure Enclave will never export (PresenceDeviceKey) and register its
/// public half with Toden. From then on background code gets its own 1-hour
/// presence token by signing a timestamped request, and every queued day is
/// sealed with that key, so a late report still counts for its own day.
///
/// Pure, so XCTest replays test/presence_seal_vectors.json, shared with the RN
/// SDK's device-rules.ts, Dart's presence_device.dart and Android's
/// PresenceDevice.kt.
enum PresenceDeviceRules {
  /// At most one refresh per device in this long.
  static let refreshIntervalMillis: Int64 = 30 * 60 * 1000
  /// After 409 `no_live_watch` (a pending device or a dormant chain).
  static let backOffMillis: Int64 = 6 * 60 * 60 * 1000

  /// The DER prefix that turns a 65-byte X9.63 P-256 point into an SPKI.
  static let p256SpkiPrefix: [UInt8] = [
    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
    0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
  ]

  /// iOS exports a public key as its X9.63 point; core reads DER SPKI.
  static func spki(fromX963 point: Data) -> Data? {
    guard point.count == 65, point.first == 0x04 else { return nil }
    return Data(p256SpkiPrefix) + point
  }

  static func registrationText(externalUserId: String, publicKey: String, signedAt: Int64) -> String {
    "toden-presence-device-v1\n\(externalUserId)\n\(publicKey)\n\(signedAt)"
  }

  static func refreshText(deviceId: String, externalUserId: String, signedAt: Int64) -> String {
    "toden-presence-refresh-v1\n\(deviceId)\n\(externalUserId)\n\(signedAt)"
  }

  /// The seal signs the observation's report-digest row, exactly as it is posted.
  static func sealText(
    deviceId: String, externalUserId: String, observation: [String: Any], observedAtMillis: Int64
  ) -> String {
    "toden-presence-seal-v1\n\(deviceId)\n\(externalUserId)\n\(PresenceWire.digestRow(observation))\n\(observedAtMillis)"
  }

  /// `observedAt` on the wire: UTC with milliseconds, as JavaScript writes it.
  static func isoMillis(_ millis: Int64) -> String {
    let format = DateFormatter()
    format.locale = Locale(identifier: "en_US_POSIX")
    format.timeZone = TimeZone(identifier: "UTC")
    format.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    return format.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
  }

  /// Always after the last one sent: the server takes only a strictly increasing value.
  static func nextSignedAt(correctedNow: Int64, lastSent: Int64?) -> Int64 {
    guard let last = lastSent else { return correctedNow }
    return max(correctedNow, last + 1)
  }

  /// Server minus device, from a response's Date header; nil keeps the offset.
  static func clockOffset(date: String?, deviceNowMillis: Int64) -> Int64? {
    guard let date = date, !date.isEmpty else { return nil }
    let format = DateFormatter()
    format.locale = Locale(identifier: "en_US_POSIX")
    format.timeZone = TimeZone(identifier: "GMT")
    format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    guard let server = format.date(from: date) else { return nil }
    return Int64((server.timeIntervalSince1970 * 1000).rounded()) - deviceNowMillis
  }

  enum Registration: String { case registered, refused, limit, deleteKey = "delete_key", retryClock = "retry_clock", keep }
  enum Refresh: String {
    case store, deleteKey = "delete_key", retryClock = "retry_clock", retrySignedAt = "retry_signed_at"
    case backOff = "back_off", keep
  }

  static func registrationOutcome(status: Int?, code: String?) -> Registration {
    switch (status, code) {
    case (201?, _), (200?, _): return .registered
    case (403?, "device_registration_refused"?), (422?, "device_not_genuine"?): return .refused
    case (409?, "presence_device_limit"?): return .limit
    case (403?, "presence_device_invalid"?), (422?, "invalid_device_key"?): return .deleteKey
    case (400?, "clock_skew"?): return .retryClock
    default: return .keep
    }
  }

  /// The code decides; only 403 `presence_device_invalid` ends the key.
  static func refreshOutcome(status: Int?, code: String?) -> Refresh {
    switch (status, code) {
    case (201?, _), (200?, _): return .store
    case (403?, "presence_device_invalid"?): return .deleteKey
    case (400?, "clock_skew"?): return .retryClock
    case (409?, "stale_signed_at"?): return .retrySignedAt
    case (409?, "no_live_watch"?): return .backOff
    default: return .keep
    }
  }

  static func refreshDue(nowMillis: Int64, lastRefreshAt: Int64?, backOffUntil: Int64?) -> Bool {
    if let until = backOffUntil, nowMillis < until { return false }
    guard let last = lastRefreshAt else { return true }
    return nowMillis - last >= refreshIntervalMillis
  }

  /// The days a 2xx may take off the queue: on a watch held past its deadline,
  /// only the days up to the deadline (a reviewer's extension may still let
  /// the later ones count).
  static func removableAfterSend(_ sent: [[String: Any]], heldDeadlineDay: String?) -> [[String: Any]] {
    guard let deadline = heldDeadlineDay else { return sent }
    return sent.filter { ($0["day"] as? String ?? "") <= deadline }
  }

  /// The error code of a JSON error answer (v1 envelope or flat).
  static func errorCode(_ data: Data?) -> String? {
    guard let data = data, let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return nil }
    if let error = raw["error"] as? [String: Any] { return error["code"] as? String }
    if let error = raw["error"] as? String { return error }
    return raw["code"] as? String
  }
}

/// What this phone holds for its presence device, in the Keychain (this
/// device only): the key's tag and public half, and once Toden registered it,
/// its id. Never the private key, which stays in the Secure Enclave.
struct PresenceDeviceRecord: Codable, Equatable {
  var externalUserId: String
  var tag: String?
  var publicKey: String?
  var keyStorage: String?
  var deviceId: String?
  /// SHA-256 of the HMAC presenceToken a registration was refused (or capped)
  /// for: no new attempt until a new verification's 202 brings another token.
  var refusedFor: String?
  var lastSignedAt: Int64?
  var lastRefreshAt: Int64?
  var backOffUntil: Int64?
  /// Server minus device, from the last core Date header.
  var clockOffset: Int64 = 0
  /// After 409 `presence_device_limit`: no new attempt before this. The cap
  /// frees up when the customer revokes a device or a check ends.
  var limitUntil: Int64?
  /// SHA-256 of the HMAC presenceToken this device registered with. Core binds
  /// a device to that token's verification, so a new verification's token
  /// needs a new key and a new registration.
  var registeredFor: String?

  init(
    externalUserId: String, tag: String? = nil, publicKey: String? = nil, keyStorage: String? = nil,
    deviceId: String? = nil, refusedFor: String? = nil, lastSignedAt: Int64? = nil,
    lastRefreshAt: Int64? = nil, backOffUntil: Int64? = nil, clockOffset: Int64 = 0, limitUntil: Int64? = nil,
    registeredFor: String? = nil
  ) {
    self.limitUntil = limitUntil
    self.registeredFor = registeredFor
    self.externalUserId = externalUserId
    self.tag = tag
    self.publicKey = publicKey
    self.keyStorage = keyStorage
    self.deviceId = deviceId
    self.refusedFor = refusedFor
    self.lastSignedAt = lastSignedAt
    self.lastRefreshAt = lastRefreshAt
    self.backOffUntil = backOffUntil
    self.clockOffset = clockOffset
  }

  var hasKey: Bool { tag != nil && publicKey != nil }
  var registered: Bool { hasKey && deviceId != nil }
}

/// The device record's decisions, pure. Mirrors Android's PresenceDeviceRecords.
enum PresenceDeviceRecords {
  /// Lowercase hex SHA-256 of a presenceToken: the refusal mark, never the token.
  static func tokenDigest(_ token: String) -> String {
    SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  enum Step: Equatable {
    /// Registered already: nothing to send.
    case registered
    /// Refused (or capped) for this very token: wait for a new verification.
    case refused
    /// A key kept from an attempt with no answer: send it again.
    case reuse(PresenceDeviceRecord)
    /// Make a new key; `discard` is a key held for another user, deleted first.
    case newKey(discard: String?)
  }

  static func registrationStep(_ record: PresenceDeviceRecord?, externalUserId: String, presenceToken: String) -> Step {
    guard let record = record else { return .newKey(discard: nil) }
    if record.externalUserId != externalUserId { return .newKey(discard: record.tag) }
    if record.registered {
      return record.registeredFor == tokenDigest(presenceToken) ? .registered : .newKey(discard: record.tag)
    }
    if record.refusedFor == tokenDigest(presenceToken) { return .refused }
    if record.hasKey { return .reuse(record) }
    return .newKey(discard: nil)
  }

  /// Whether `current` is still the device a request was sent for: the same
  /// user, key and registration. A logout, or another run's delete or new key,
  /// while the request was out means its answer must not write the old record
  /// back (or keep a token for a user who signed out).
  static func stillHeld(_ sent: PresenceDeviceRecord, _ current: PresenceDeviceRecord?) -> Bool {
    guard let current = current else { return false }
    return current.externalUserId == sent.externalUserId && current.tag == sent.tag
      && current.deviceId == sent.deviceId
  }
}

/// Seals a chunk at post time: each queued entry with its `observedAtMillis`
/// (stamped, on the corrected clock, whenever its aggregate changed) gets a
/// `seal` over its wire row exactly as posted. An entry the key cannot sign
/// goes unsealed, never dropped. Mirrors Android's PresenceSeal.
enum PresenceSeal {
  /// True when at least one entry was sealed, so the body needs `sealDeviceId`.
  static func apply(
    queued: [[String: Any]], observations: inout [[String: Any]], deviceId: String,
    externalUserId: String, sign: (String) -> String?
  ) -> Bool {
    var any = false
    for i in 0..<min(queued.count, observations.count) {
      guard let observedAt = (queued[i]["observedAtMillis"] as? NSNumber)?.int64Value, observedAt > 0 else { continue }
      let text = PresenceDeviceRules.sealText(
        deviceId: deviceId, externalUserId: externalUserId, observation: observations[i], observedAtMillis: observedAt)
      guard let signature = sign(text) else { continue }
      observations[i]["seal"] = ["observedAt": PresenceDeviceRules.isoMillis(observedAt), "signature": signature]
      any = true
    }
    return any
  }
}
