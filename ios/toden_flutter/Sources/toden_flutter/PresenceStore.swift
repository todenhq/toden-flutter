import Foundation
import Security

/// Persistence for the background presence tier: the armed config, the open
/// ENTER timestamp, and the pending per-day queue. UserDefaults because the
/// relaunched-for-a-region-event process must read it before any Dart runs.
/// Only per-day aggregates are ever stored; a location trace never exists
/// anywhere. Mirrors Android's PresenceStore.kt and RN's background-store.ts.
struct PresenceStore {
  private static let configKey = "myaza_kyc_presence.config"
  private static let armedKey = "myaza_kyc_presence.armed"
  private static let enterAtKey = "myaza_kyc_presence.enterAt"
  private static let stayStartKey = "myaza_kyc_presence.stayStart"
  private static let queueKey = "myaza_kyc_presence.queue"
  /// Not a secret: whether the flush needs a user token. The token itself is
  /// only ever in the Keychain, never here.
  private static let userTokensKey = "myaza_kyc_presence.userTokens"
  private static let keychainService = "co.toden.flutter.presence"
  private static let keychainAccount = "userToken"
  /// One lock for every read-modify-write of the queue and the token: the
  /// flush finishes on URLSession's queue while region events and the channel
  /// run on the main thread. Recursive, since the token helpers nest.
  private static let lock = NSRecursiveLock()

  private static func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  struct Config {
    let lat: Double
    let lng: Double
    let radius: Double
    let baseUrl: String
    let apiKey: String
    let externalUserId: String
    /// From the 202 of the verification that captured the pin. Kept in the
    /// Keychain (this device only), never in UserDefaults, which iCloud backs up.
    var presenceToken: String? = nil
    /// The Keychain holds it but cannot be read before the first unlock: the
    /// flush waits rather than post without it.
    var presenceTokenHeld = false
  }

  static func saveConfig(_ config: Config) {
    let defaults = UserDefaults.standard
    let raw: [String: Any] = [
      "lat": config.lat, "lng": config.lng, "radius": config.radius,
      "baseUrl": config.baseUrl, "apiKey": config.apiKey,
      "externalUserId": config.externalUserId,
    ]
    locked {
      // A new pin drops the old token, wherever it was kept.
      deleteKeychain(account: hmacAccount)
      var stored = raw
      if let token = config.presenceToken,
         !saveHmacTokenLocked(externalUserId: config.externalUserId, token: token)
      {
        // No Keychain right now: UserDefaults, as before 4.5.0, moved on a later read.
        stored["presenceToken"] = token
      }
      defaults.set(stored, forKey: configKey)
    }
    defaults.set(true, forKey: armedKey)
  }

  /// The token arrives after the region may already be armed, and Dart keeps
  /// it here for the foreground reporter too, so it is saved whether or not a
  /// config is armed. Leaves `armed` alone; a config for another user keeps
  /// its own. Answers whether the Keychain took it (Dart then keeps no copy).
  @discardableResult
  static func updatePresenceToken(externalUserId: String, token: String) -> Bool {
    locked {
      let saved = saveHmacTokenLocked(externalUserId: externalUserId, token: token)
      let defaults = UserDefaults.standard
      guard var raw = defaults.dictionary(forKey: configKey),
            raw["externalUserId"] as? String == externalUserId
      else { return saved }
      if saved {
        raw.removeValue(forKey: "presenceToken")
      } else {
        raw["presenceToken"] = token
      }
      defaults.set(raw, forKey: configKey)
      return saved
    }
  }

  /// This user's token for the Dart reporter: nil, or held before the first unlock.
  static func presenceToken(externalUserId: String) -> (token: String?, held: Bool) {
    locked {
      switch readHmacTokenLocked() {
      case .locked: return (nil, true)
      case .stored(let user, let token) where user == externalUserId: return (token, false)
      default: return (nil, false)
      }
    }
  }

  /// A new pin, a cleared pin or a stand-down for this user drops the token.
  static func forgetPresenceToken(externalUserId: String) {
    locked {
      if case .stored(let user, _) = readHmacTokenLocked(), user == externalUserId {
        deleteKeychain(account: hmacAccount)
      }
    }
  }

  static func loadConfig() -> Config? {
    locked { loadConfigLocked() }
  }

  private static func loadConfigLocked() -> Config? {
    let defaults = UserDefaults.standard
    guard var raw = defaults.dictionary(forKey: configKey),
          let lat = raw["lat"] as? Double, let lng = raw["lng"] as? Double,
          let baseUrl = raw["baseUrl"] as? String, let apiKey = raw["apiKey"] as? String,
          let externalUserId = raw["externalUserId"] as? String
    else { return nil }
    let legacy = raw["presenceToken"] as? String
    let keychain = readHmacTokenLocked()
    var token: String?
    var held = false
    switch PresenceHmacToken.step(defaultsToken: legacy, keychain: keychain, externalUserId: externalUserId) {
    case .use(let value):
      token = value
      // The Keychain already holds it: the backed-up copy goes.
      if legacy != nil, PresenceHmacToken.keychainHas(keychain, externalUserId) {
        raw.removeValue(forKey: "presenceToken")
        defaults.set(raw, forKey: configKey)
      }
    case .moveFromDefaults(let value):
      token = value
      // Written, read back, and only then deleted from UserDefaults (iCloud backs it up).
      if saveHmacTokenLocked(externalUserId: externalUserId, token: value),
         readHmacTokenLocked() == .stored(externalUserId: externalUserId, token: value)
      {
        raw.removeValue(forKey: "presenceToken")
        defaults.set(raw, forKey: configKey)
      }
    case .held:
      held = true
    }
    var config = Config(
      lat: lat, lng: lng, radius: raw["radius"] as? Double ?? 250,
      baseUrl: baseUrl, apiKey: apiKey, externalUserId: externalUserId,
      presenceToken: token
    )
    config.presenceTokenHeld = held
    return config
  }

  // MARK: - The HMAC presenceToken (Keychain, this device only; design rev 4, R65)

  private static let hmacAccount = "presenceToken"

  private static func keychainQuery(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: account,
    ]
  }

  private static func deleteKeychain(account: String) {
    _ = SecItemDelete(keychainQuery(account: account) as CFDictionary)
  }

  private static func writeKeychain(account: String, data: Data) -> Bool {
    let update: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    var status = SecItemUpdate(keychainQuery(account: account) as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      var add = keychainQuery(account: account)
      update.forEach { add[$0.key] = $0.value }
      status = SecItemAdd(add as CFDictionary, nil)
    }
    return status == errSecSuccess
  }

  /// `.locked` before the first unlock (errSecInteractionNotAllowed).
  private static func readKeychain(account: String) -> (data: Data?, locked: Bool) {
    var query = keychainQuery(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    switch SecItemCopyMatching(query as CFDictionary, &item) {
    case errSecSuccess: return (item as? Data, false)
    case errSecItemNotFound: return (nil, false)
    default: return (nil, true)
    }
  }

  private static func saveHmacTokenLocked(externalUserId: String, token: String) -> Bool {
    guard let data = PresenceHmacToken.encode(externalUserId: externalUserId, token: token) else { return false }
    return writeKeychain(account: hmacAccount, data: data)
  }

  private static func readHmacTokenLocked() -> PresenceHmacToken.Keychain {
    let read = readKeychain(account: hmacAccount)
    if read.locked { return .locked }
    guard let data = read.data, let pair = PresenceHmacToken.decode(data) else { return .missing }
    return .stored(externalUserId: pair.externalUserId, token: pair.token)
  }

  static func clear() {
    locked {
      let defaults = UserDefaults.standard
      [configKey, armedKey, enterAtKey, stayStartKey, queueKey, userTokensKey, heldDeadlineKey].forEach {
        defaults.removeObject(forKey: $0)
      }
      deleteUserToken()
      deleteKeychain(account: hmacAccount)
    }
  }

  // MARK: - User token (Keychain, this device only, after first unlock)

  static var userTokensInUse: Bool {
    get { UserDefaults.standard.bool(forKey: userTokensKey) }
    set { UserDefaults.standard.set(newValue, forKey: userTokensKey) }
  }

  private static func keychainQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
    ]
  }

  /// Keeps the token Dart checked. Never in UserDefaults, never in a backup.
  @discardableResult
  static func saveUserToken(_ record: PresenceUserToken.Record) -> Bool {
    locked { saveUserTokenLocked(record) }
  }

  private static func saveUserTokenLocked(_ record: PresenceUserToken.Record) -> Bool {
    guard let data = PresenceUserToken.encode(record) else { return false }
    let update: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    var status = SecItemUpdate(keychainQuery() as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      var add = keychainQuery()
      update.forEach { add[$0.key] = $0.value }
      status = SecItemAdd(add as CFDictionary, nil)
    }
    return status == errSecSuccess
  }

  /// Before the first unlock the Keychain answers errSecInteractionNotAllowed:
  /// that is `locked`, and the flush keeps its queue.
  static func readUserToken() -> PresenceUserToken.Read {
    locked { readUserTokenLocked() }
  }

  private static func readUserTokenLocked() -> PresenceUserToken.Read {
    var query = keychainQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      guard let data = item as? Data, let record = PresenceUserToken.decode(data) else { return .missing }
      return .stored(record)
    case errSecItemNotFound:
      return .missing
    default:
      return .locked
    }
  }

  /// The server refused `sentToken`: only that token goes stale.
  static func markUserTokenStale(sentToken: String) {
    locked {
      if let record = PresenceUserToken.staleAfterRefusal(read: readUserTokenLocked(), sentToken: sentToken) {
        _ = saveUserTokenLocked(record)
      }
    }
  }

  static func deleteUserToken() {
    locked { _ = SecItemDelete(keychainQuery() as CFDictionary) }
  }

  /// Logout or stand-down for this user: no token, no flag.
  static func clearUserToken(externalUserId: String) {
    locked {
      if case .stored(let record) = readUserTokenLocked(), record.externalUserId != externalUserId { return }
      userTokensInUse = false
      deleteUserToken()
    }
  }

  /// Removes posted entries; days queued while the requests were out stay.
  static func removeFromQueue(_ posted: [[String: Any]]) {
    guard !posted.isEmpty else { return }
    locked {
      let gone = posted.map { NSDictionary(dictionary: $0) }
      let kept = pendingQueue().filter { entry in
        !gone.contains { $0.isEqual(to: entry) }
      }
      UserDefaults.standard.set(kept, forKey: queueKey)
    }
  }

  static var armed: Bool {
    get { UserDefaults.standard.bool(forKey: armedKey) }
    set { UserDefaults.standard.set(newValue, forKey: armedKey) }
  }

  static var enterAt: Int64? {
    get {
      let value = UserDefaults.standard.object(forKey: enterAtKey) as? NSNumber
      return value.map { $0.int64Value }
    }
    set {
      if let value = newValue {
        UserDefaults.standard.set(NSNumber(value: value), forKey: enterAtKey)
      } else {
        UserDefaults.standard.removeObject(forKey: enterAtKey)
        UserDefaults.standard.removeObject(forKey: stayStartKey)
      }
    }
  }

  /// When the open stay began. `enterAt` moves on at each check-in; this
  /// does not, which is how the check-in rule knows a stay was recorded.
  static var stayStart: Int64? {
    get {
      guard enterAt != nil else { return nil }
      return (UserDefaults.standard.object(forKey: stayStartKey) as? NSNumber)?.int64Value
    }
    set {
      if let value = newValue {
        UserDefaults.standard.set(NSNumber(value: value), forKey: stayStartKey)
      } else {
        UserDefaults.standard.removeObject(forKey: stayStartKey)
      }
    }
  }

  // MARK: - Presence device (Keychain, this device only)
  // The key's tag, its public half and the registration id. A restored backup
  // must never carry them to another phone, whose Secure Enclave has no key.

  private static let deviceAccount = "presenceDevice"
  private static let heldDeadlineKey = "myaza_kyc_presence.heldDeadlineDay"

  static func readDevice() -> PresenceDeviceRecord? {
    locked {
      guard let data = readKeychain(account: deviceAccount).data else { return nil }
      return try? JSONDecoder().decode(PresenceDeviceRecord.self, from: data)
    }
  }

  @discardableResult
  static func saveDevice(_ record: PresenceDeviceRecord) -> Bool {
    locked {
      guard let data = try? JSONEncoder().encode(record) else { return false }
      return writeKeychain(account: deviceAccount, data: data)
    }
  }

  static func deleteDevice() {
    locked { deleteKeychain(account: deviceAccount) }
  }

  /// Logout: the key, its registration and its marks, for this user only.
  static func forgetDevice(externalUserId: String) {
    locked {
      guard let record = readDevice(), record.externalUserId == externalUserId else { return }
      if let tag = record.tag { PresenceDeviceKey.delete(tag: tag) }
      deleteDevice()
    }
  }

  /// The watch's deadline day (yyyy-MM-dd, UTC) while it is in progress past
  /// it, held for late sealed reports; nil otherwise. Set by Dart from the
  /// watch status. Not a secret.
  static var heldDeadlineDay: String? {
    get { UserDefaults.standard.string(forKey: heldDeadlineKey) }
    set {
      if let day = newValue {
        UserDefaults.standard.set(day, forKey: heldDeadlineKey)
      } else {
        UserDefaults.standard.removeObject(forKey: heldDeadlineKey)
      }
    }
  }

  /// When an entry's aggregate last changed, on the clock the seals use.
  private static func observedNow() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000) + (readDevice()?.clockOffset ?? 0)
  }

  /// Merge fresh day aggregates into the queue: same day → sum dwell, OR
  /// night, sum samples. The RN tier's mergeIntoQueue, verbatim.
  static func queueDays(_ days: [PresenceFold.DayAggregate]) {
    locked { queueDaysLocked(days) }
  }

  private static func queueDaysLocked(_ days: [PresenceFold.DayAggregate]) {
    let observed = observedNow()
    var byDay: [String: [String: Any]] = [:]
    var order: [String] = []
    for entry in pendingQueue() {
      guard let day = entry["day"] as? String else { continue }
      byDay[day] = entry
      order.append(day)
    }
    for aggregate in days {
      if var prior = byDay[aggregate.day] {
        prior["dwellMinutes"] = (prior["dwellMinutes"] as? Int ?? 0) + aggregate.dwellMinutes
        prior["nightPresent"] = (prior["nightPresent"] as? Bool ?? false) || aggregate.nightPresent
        prior["samples"] = (prior["samples"] as? Int ?? 0) + 1
        // A changed day is sealed again, as of now.
        prior["observedAtMillis"] = observed
        byDay[aggregate.day] = prior
      } else {
        byDay[aggregate.day] = [
          "day": aggregate.day, "dwellMinutes": aggregate.dwellMinutes,
          "nightPresent": aggregate.nightPresent, "samples": 1, "observedAtMillis": observed,
        ]
        order.append(aggregate.day)
      }
    }
    UserDefaults.standard.set(order.compactMap { byDay[$0] }, forKey: queueKey)
  }

  /// A simulated fix's day: reported flagged, with no dwell.
  static func queueFlagged(day: String, nightPresent: Bool) {
    locked { queueFlaggedLocked(day: day, nightPresent: nightPresent) }
  }

  private static func queueFlaggedLocked(day: String, nightPresent: Bool) {
    let observed = observedNow()
    var entries = pendingQueue()
    if let index = entries.firstIndex(where: { $0["day"] as? String == day }) {
      var prior = entries[index]
      prior["nightPresent"] = (prior["nightPresent"] as? Bool ?? false) || nightPresent
      prior["samples"] = (prior["samples"] as? Int ?? 0) + 1
      prior["mockLocation"] = true
      prior["observedAtMillis"] = observed
      entries[index] = prior
    } else {
      entries.append([
        "day": day, "dwellMinutes": 0, "nightPresent": nightPresent, "samples": 1,
        "mockLocation": true, "observedAtMillis": observed,
      ])
    }
    UserDefaults.standard.set(entries, forKey: queueKey)
  }

  static func pendingQueue() -> [[String: Any]] {
    (UserDefaults.standard.array(forKey: queueKey) as? [[String: Any]]) ?? []
  }

  static func clearQueue() {
    locked { UserDefaults.standard.removeObject(forKey: queueKey) }
  }
}
