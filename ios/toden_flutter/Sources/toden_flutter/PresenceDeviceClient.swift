import Foundation
import UIKit

/// The presence device's two requests (user token design rev 4, section 6b):
/// registration, from the foreground right after an address verification's
/// 202, and the background refresh that gets a 1-hour presence token by
/// signing a timestamped request. The rules are PresenceDeviceRules and
/// PresenceDeviceRecords, which XCTest pins. Mirrors Android's
/// PresenceDeviceClient.kt.
enum PresenceDeviceClient {
  struct Answer {
    let status: Int?
    let date: String?
    let body: Data?
  }

  private static func post(
    _ urlString: String, apiKey: String, body: [String: Any], userToken: String? = nil,
    completion: @escaping (Answer) -> Void
  ) {
    guard let url = URL(string: urlString), let data = try? JSONSerialization.data(withJSONObject: body) else {
      completion(Answer(status: nil, date: nil, body: nil))
      return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 8
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    if let userToken = userToken { request.setValue(userToken, forHTTPHeaderField: PresenceUserToken.header) }
    request.httpBody = data
    URLSession.shared.dataTask(with: request) { body, response, _ in
      let http = response as? HTTPURLResponse
      completion(Answer(status: http?.statusCode, date: http?.value(forHTTPHeaderField: "Date"), body: body))
    }.resume()
  }

  /// One refresh at a time in this process: region events, a check-in and the
  /// channel can each flush at once, and two refreshes would each sign and send.
  private static let refreshGate = NSLock()
  private static var refreshing = false

  private static func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

  private static func withClock(_ record: PresenceDeviceRecord, _ answer: Answer, deviceNow: Int64) -> PresenceDeviceRecord {
    var next = record
    if let offset = PresenceDeviceRules.clockOffset(date: answer.date, deviceNowMillis: deviceNow) {
      next.clockOffset = offset
    }
    return next
  }

  /// Registers this phone's presence device for `externalUserId`. Answers the
  /// outcome's name for Dart: `registered`, `refused`, `limit`, `delete_key`,
  /// `keep`, `no_key`, `needs_token` (asked with no user token and one is
  /// needed), or `user_token_invalid` (Dart fetches a fresh token and calls
  /// once more).
  static func register(
    baseUrl: String, apiKey: String, externalUserId: String, userToken: String?, presenceToken: String,
    stableId: String?, completion: @escaping (String) -> Void
  ) {
    var record: PresenceDeviceRecord
    let held = PresenceStore.readDevice()
    if let held = held, held.externalUserId == externalUserId, !held.registered,
       let until = held.limitUntil, nowMillis() < until
    {
      return completion("limit")
    }
    switch PresenceDeviceRecords.registrationStep(held, externalUserId: externalUserId, presenceToken: presenceToken) {
    case .registered: return completion("registered")
    case .refused: return completion("refused")
    case .reuse(let kept): record = kept
    case .newKey(let discard):
      if let tag = discard { PresenceDeviceKey.delete(tag: tag) }
      PresenceStore.deleteDevice()
      // The key first: a phone with none answers no_key before the host mints.
      guard let created = PresenceDeviceKey.create() else { return completion("no_key") }
      record = PresenceDeviceRecord(
        externalUserId: externalUserId, tag: created.tag, publicKey: created.publicKey, keyStorage: created.keyStorage)
      // Kept before sending, so an answer that never comes reuses this key.
      PresenceStore.saveDevice(record)
    }
    // Dart asks first with no token, so a phone already registered never
    // costs the host a mint.
    guard let userToken = userToken else { return completion("needs_token") }
    attemptRegistration(
      record, attempt: 0, baseUrl: baseUrl, apiKey: apiKey, userToken: userToken,
      presenceToken: presenceToken, stableId: stableId, completion: completion)
  }

  private static func attemptRegistration(
    _ start: PresenceDeviceRecord, attempt: Int, baseUrl: String, apiKey: String, userToken: String,
    presenceToken: String, stableId: String?, completion: @escaping (String) -> Void
  ) {
    guard let tag = start.tag, let publicKey = start.publicKey else { return completion("keep") }
    let user = start.externalUserId
    let deviceNow = nowMillis()
    let signedAt = PresenceDeviceRules.nextSignedAt(
      correctedNow: deviceNow + start.clockOffset, lastSent: start.lastSignedAt)
    guard let proof = PresenceDeviceKey.sign(
      tag: tag, text: PresenceDeviceRules.registrationText(externalUserId: user, publicKey: publicKey, signedAt: signedAt))
    else { return completion("keep") }
    var record = start
    record.lastSignedAt = signedAt
    PresenceStore.saveDevice(record)
    var body: [String: Any] = [
      "externalUserId": user, "publicKey": publicKey, "platform": "ios",
      "keyStorage": record.keyStorage ?? "secure_enclave", "signedAt": signedAt, "proof": proof,
      "presenceToken": presenceToken,
    ]
    if let stableId = stableId { body["device"] = ["stableId": stableId] }
    post("\(baseUrl)/api/v1/address/presence/devices", apiKey: apiKey, body: body, userToken: userToken) { answer in
      // A logout while the request was out: leave the device gone.
      guard PresenceDeviceRecords.stillHeld(record, PresenceStore.readDevice()) else { return completion("keep") }
      record = withClock(record, answer, deviceNow: deviceNow)
      let code = PresenceDeviceRules.errorCode(answer.body)
      switch PresenceDeviceRules.registrationOutcome(status: answer.status, code: code) {
      case .registered:
        let json = answer.body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        guard let id = json?["id"] as? String, !id.isEmpty else {
          PresenceStore.saveDevice(record)
          return completion("keep")
        }
        record.deviceId = id
        record.refusedFor = nil
        record.registeredFor = PresenceDeviceRecords.tokenDigest(presenceToken)
        PresenceStore.saveDevice(record)
        completion("registered")
      case .refused:
        // No refresh: this phone runs as before. A new verification's token may try again.
        PresenceDeviceKey.delete(tag: tag)
        PresenceStore.saveDevice(PresenceDeviceRecord(
          externalUserId: user, refusedFor: PresenceDeviceRecords.tokenDigest(presenceToken),
          clockOffset: record.clockOffset))
        completion("refused")
      case .limit:
        // The cap frees up when the customer revokes a device or a check
        // ends: a later foreground tries again, after a back-off.
        NSLog("[toden] presence_device_limit: this user already has the most presence devices")
        PresenceDeviceKey.delete(tag: tag)
        PresenceStore.saveDevice(PresenceDeviceRecord(
          externalUserId: user, clockOffset: record.clockOffset,
          limitUntil: nowMillis() + PresenceDeviceRules.backOffMillis))
        completion("limit")
      case .deleteKey:
        PresenceDeviceKey.delete(tag: tag)
        PresenceStore.deleteDevice()
        completion("delete_key")
      case .retryClock:
        PresenceStore.saveDevice(record)
        guard attempt == 0 else { return completion("keep") }
        attemptRegistration(
          record, attempt: 1, baseUrl: baseUrl, apiKey: apiKey, userToken: userToken,
          presenceToken: presenceToken, stableId: stableId, completion: completion)
      case .keep:
        PresenceStore.saveDevice(record)
        completion(code == "user_token_invalid" ? "user_token_invalid" : "keep")
      }
    }
  }

  /// A fresh presence token for the flush when this phone holds a registered
  /// device and a refresh is due. Completes true when one was stored.
  static func refreshIfDue(config: PresenceStore.Config, completion: @escaping (Bool) -> Void) {
    guard let record = PresenceStore.readDevice(), record.registered,
          record.externalUserId == config.externalUserId,
          PresenceDeviceRules.refreshDue(
            nowMillis: nowMillis(), lastRefreshAt: record.lastRefreshAt, backOffUntil: record.backOffUntil)
    else { return completion(false) }
    // Another flush is refreshing: it posts the queue when its token arrives.
    refreshGate.lock()
    let busy = refreshing
    refreshing = true
    refreshGate.unlock()
    if busy { return completion(false) }
    var task: UIBackgroundTaskIdentifier = .invalid
    let finish = { (ok: Bool) in
      refreshGate.lock()
      refreshing = false
      refreshGate.unlock()
      // The follow-up flush begins its own background task first.
      completion(ok)
      if task != .invalid {
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
      }
    }
    task = UIApplication.shared.beginBackgroundTask {
      if task != .invalid {
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
      }
    }
    attemptRefresh(record, attempt: 0, config: config, completion: finish)
  }

  private static func attemptRefresh(
    _ start: PresenceDeviceRecord, attempt: Int, config: PresenceStore.Config, completion: @escaping (Bool) -> Void
  ) {
    guard let tag = start.tag, let deviceId = start.deviceId else { return completion(false) }
    let deviceNow = nowMillis()
    let signedAt = PresenceDeviceRules.nextSignedAt(
      correctedNow: deviceNow + start.clockOffset, lastSent: start.lastSignedAt)
    guard let signature = PresenceDeviceKey.sign(
      tag: tag,
      text: PresenceDeviceRules.refreshText(deviceId: deviceId, externalUserId: config.externalUserId, signedAt: signedAt))
    else { return completion(false) }
    // Kept before sending: a signedAt once sent is never sent again.
    var record = start
    record.lastSignedAt = signedAt
    PresenceStore.saveDevice(record)
    let body: [String: Any] = [
      "deviceId": deviceId, "externalUserId": config.externalUserId, "signedAt": signedAt, "signature": signature,
    ]
    post("\(config.baseUrl)/api/v1/address/presence/devices/token", apiKey: config.apiKey, body: body) { answer in
      // A logout while the request was out: no record back, no token kept.
      guard PresenceDeviceRecords.stillHeld(record, PresenceStore.readDevice()) else { return completion(false) }
      record = withClock(record, answer, deviceNow: deviceNow)
      if answer.status != nil { record.lastRefreshAt = deviceNow }
      switch PresenceDeviceRules.refreshOutcome(status: answer.status, code: PresenceDeviceRules.errorCode(answer.body)) {
      case .store:
        record.backOffUntil = nil
        PresenceStore.saveDevice(record)
        let json = answer.body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        guard let json = json,
              let minted = PresenceUserToken.checkMinted(
                json, externalUserId: config.externalUserId, apiKey: config.apiKey, nowMillis: nowMillis()),
              PresenceStore.saveUserToken(minted)
        else { return completion(false) }
        PresenceStore.userTokensInUse = true
        completion(true)
      case .deleteKey:
        PresenceDeviceKey.delete(tag: tag)
        PresenceStore.deleteDevice()
        completion(false)
      case .retryClock, .retrySignedAt:
        PresenceStore.saveDevice(record)
        guard attempt == 0 else { return completion(false) }
        attemptRefresh(record, attempt: 1, config: config, completion: completion)
      case .backOff:
        record.backOffUntil = deviceNow + PresenceDeviceRules.backOffMillis
        PresenceStore.saveDevice(record)
        completion(false)
      case .keep:
        PresenceStore.saveDevice(record)
        completion(false)
      }
    }
  }
}
