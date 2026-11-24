import Foundation

/// User tokens for scoped publishable keys (Toden design 0020, section 14), as
/// the background flush needs them. Native code never calls the host's provider
/// and never renews a token: Dart hands one over after its identity check
/// (setPresenceUserToken), and PresenceStore keeps it in the Keychain.
///
/// Pure rules only, so XCTest can replay test/user_token_vectors.json:
///   - User tokens not in use: post exactly as before, with no header.
///   - In use: only a fresh token for the armed user is sent. A missing,
///     expired or stale token, another user's, or a locked Keychain means no
///     post, and the queue is kept.
/// Mirrors Android's PresenceUserToken.kt and the RN SDK's secure-token.ts.
enum PresenceUserToken {
  static let header = "X-Toden-User-Token"

  struct Record: Equatable {
    let externalUserId: String
    let token: String
    let expiresAtMillis: Int64
    var stale: Bool
  }

  enum Read: Equatable {
    case missing
    case locked
    case stored(Record)
  }

  enum Decision: Equatable {
    case noHeader
    case use(String)
    case skip
  }

  static func decide(inUse: Bool, read: Read, externalUserId: String, nowMillis: Int64) -> Decision {
    guard inUse else { return .noHeader }
    guard case .stored(let record) = read else { return .skip }
    if record.externalUserId != externalUserId || record.stale { return .skip }
    return nowMillis < record.expiresAtMillis ? .use(record.token) : .skip
  }

  /// The record to save after the server refused `sentToken`, or nil. Only the
  /// token that was sent goes stale: one a silent push stored while the refused
  /// flush was out stays good.
  static func staleAfterRefusal(read: Read, sentToken: String) -> Record? {
    guard case .stored(var record) = read, record.token == sentToken, !record.stale else { return nil }
    record.stale = true
    return record
  }

  private static let shape = try? NSRegularExpression(pattern: "^ut_(live|test|dev)_[A-Za-z0-9_-]{43}$")

  /// A value the server could accept at all; anything else is never stored.
  static func wellFormed(_ token: String) -> Bool {
    guard let shape = shape else { return false }
    let range = NSRange(token.startIndex..., in: token)
    return shape.firstMatch(in: token, range: range) != nil
  }

  private static let keyEnv = try? NSRegularExpression(pattern: "^(?:pk|sk)_(live|test|dev)_")

  private static func group(_ regex: NSRegularExpression?, _ value: String) -> String? {
    guard let regex = regex,
          let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
          let range = Range(match.range(at: 1), in: value)
    else { return nil }
    return String(value[range])
  }

  /// A mint-shaped answer's `expiresAt` (UTC, as core writes it), or nil.
  static func parseExpiresAt(_ value: String) -> Int64? {
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    guard value.hasSuffix("Z"), let date = format.date(from: value) ?? plain.date(from: value) else { return nil }
    return Int64((date.timeIntervalSince1970 * 1000).rounded())
  }

  /// A token core minted or refreshed, as a record the flush may send, or nil.
  /// The same identity check Dart runs on a provider's answer (user_token.dart),
  /// because a background refresh has no Dart to run it.
  static func checkMinted(_ body: [String: Any], externalUserId: String, apiKey: String, nowMillis: Int64) -> Record? {
    guard let token = body["token"] as? String, let user = body["externalUserId"] as? String,
          let purpose = body["purpose"] as? String, let expiresAt = body["expiresAt"] as? String,
          user == externalUserId, purpose == "presence", wellFormed(token),
          let env = group(keyEnv, apiKey), group(shape, token) == env,
          let expires = parseExpiresAt(expiresAt), expires > nowMillis
    else { return nil }
    return Record(externalUserId: user, token: token, expiresAtMillis: expires, stale: false)
  }

  static func encode(_ record: Record) -> Data? {
    try? JSONSerialization.data(withJSONObject: [
      "externalUserId": record.externalUserId, "token": record.token,
      "expiresAtMillis": NSNumber(value: record.expiresAtMillis), "stale": record.stale,
    ])
  }

  static func decode(_ data: Data) -> Record? {
    guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let user = raw["externalUserId"] as? String, let token = raw["token"] as? String,
          let expires = raw["expiresAtMillis"] as? NSNumber
    else { return nil }
    return Record(
      externalUserId: user, token: token, expiresAtMillis: expires.int64Value,
      stale: raw["stale"] as? Bool ?? false)
  }
}

/// The background queue's flush rules: oldest day first, at most 31 days a
/// request (the server's limit). A 2xx removes its chunk; a 400 can never
/// succeed, so its chunk is dropped; anything else keeps the queue and stops.
/// Days are never dropped by age alone. Mirrors PresenceFlush.kt and the RN
/// SDK's flush.ts.
enum PresenceFlush {
  static let chunkDays = 31

  enum Outcome { case sent, drop, keep }

  static func chunks(_ queue: [[String: Any]]) -> [[[String: Any]]] {
    let sorted = queue.sorted { ($0["day"] as? String ?? "") < ($1["day"] as? String ?? "") }
    return stride(from: 0, to: sorted.count, by: chunkDays).map {
      Array(sorted[$0..<min($0 + chunkDays, sorted.count)])
    }
  }

  /// `nil`: nothing came back.
  static func outcome(status: Int?) -> Outcome {
    guard let status = status else { return .keep }
    if (200...299).contains(status) { return .sent }
    return status == 400 ? .drop : .keep
  }

  struct Result {
    /// Still queued, oldest first.
    let remaining: [[String: Any]]
    /// The server answered with a refusal (not 2xx, not 400).
    let refused: Bool
    /// Taken by a 2xx. On a held watch only some may leave the queue.
    var sent: [[String: Any]] = []
    /// Refused with a 400, which can never succeed.
    var dropped: [[String: Any]] = []
  }

  /// Posts chunk by chunk until one is kept. `post` answers each chunk's status
  /// (or nil) through its completion, from any thread.
  static func run(
    queue: [[String: Any]],
    post: @escaping ([[String: Any]], @escaping (Int?) -> Void) -> Void,
    done: @escaping (Result) -> Void
  ) {
    let all = chunks(queue)
    var sent: [[String: Any]] = []
    var dropped: [[String: Any]] = []
    func step(_ index: Int) {
      guard index < all.count else {
        done(Result(remaining: [], refused: false, sent: sent, dropped: dropped))
        return
      }
      post(all[index]) { status in
        switch outcome(status: status) {
        case .sent:
          sent += all[index]
          step(index + 1)
        case .drop:
          dropped += all[index]
          step(index + 1)
        case .keep:
          done(Result(
            remaining: Array(all[index...].joined()), refused: status != nil, sent: sent, dropped: dropped))
        }
      }
    }
    step(0)
  }
}

/// The HMAC presenceToken's move from UserDefaults (which iCloud backs up) to
/// the Keychain, this device only (user token design rev 4, R65). Pure, so
/// XCTest pins every branch. Mirrors Android's PresenceHmacToken and the RN
/// SDK's store.ts.
enum PresenceHmacToken {
  enum Keychain: Equatable {
    case missing
    case locked
    case stored(externalUserId: String, token: String)
  }

  enum Step: Equatable {
    /// Send this (nil: no token).
    case use(String?)
    /// Write it to the Keychain, read it back, then delete the UserDefaults copy.
    case moveFromDefaults(String)
    /// The Keychain cannot be read yet and nothing else holds a token: wait.
    case held
  }

  static func step(defaultsToken: String?, keychain: Keychain, externalUserId: String) -> Step {
    switch keychain {
    case .stored(let user, let token) where user == externalUserId:
      return .use(token)
    case .locked:
      return defaultsToken.map { .use($0) } ?? .held
    default:
      return defaultsToken.map { .moveFromDefaults($0) } ?? .use(nil)
    }
  }

  static func keychainHas(_ keychain: Keychain, _ externalUserId: String) -> Bool {
    if case .stored(let user, _) = keychain { return user == externalUserId }
    return false
  }

  static func encode(externalUserId: String, token: String) -> Data? {
    try? JSONSerialization.data(withJSONObject: ["externalUserId": externalUserId, "token": token])
  }

  static func decode(_ data: Data) -> (externalUserId: String, token: String)? {
    guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let user = raw["externalUserId"] as? String, let token = raw["token"] as? String
    else { return nil }
    return (user, token)
  }
}
