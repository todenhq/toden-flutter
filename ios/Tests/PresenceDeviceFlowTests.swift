import CryptoKit
import XCTest

@testable import toden_flutter

/// The device record, the registration step, the seals at post time and the
/// flush's sent and dropped days. The Secure Enclave is replaced with a
/// software P-256 key: what is checked is what gets signed and posted.
/// Mirrors Android's PresenceDeviceFlowTest.kt.
final class PresenceDeviceFlowTests: XCTestCase {
  private let token = "hmac-token-1"

  func testTheRecordRoundTripsWithEveryField() throws {
    let record = PresenceDeviceRecord(
      externalUserId: "cus_123", tag: "tag", publicKey: "spki", keyStorage: "secure_enclave", deviceId: "upd_1",
      lastSignedAt: 5, lastRefreshAt: 6, backOffUntil: 7, clockOffset: -300_000, limitUntil: 8, registeredFor: "digest")
    let data = try JSONEncoder().encode(record)
    XCTAssertEqual(try JSONDecoder().decode(PresenceDeviceRecord.self, from: data), record)
  }

  func testTheRefusalMarkIsADigestNeverTheToken() throws {
    let digest = PresenceDeviceRecords.tokenDigest(token)
    XCTAssertEqual(digest.count, 64)
    let data = try JSONEncoder().encode(PresenceDeviceRecord(externalUserId: "cus_123", refusedFor: digest))
    XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(token))
  }

  func testRegistrationSteps() {
    let keyed = PresenceDeviceRecord(externalUserId: "cus_123", tag: "tag", publicKey: "spki", keyStorage: "secure_enclave")
    XCTAssertEqual(PresenceDeviceRecords.registrationStep(nil, externalUserId: "cus_123", presenceToken: token), .newKey(discard: nil))
    var registered = keyed
    registered.deviceId = "upd_1"
    // Registered for an unknown token (or another verification's): a new key.
    XCTAssertEqual(
      PresenceDeviceRecords.registrationStep(registered, externalUserId: "cus_123", presenceToken: token), .newKey(discard: "tag"))
    registered.registeredFor = PresenceDeviceRecords.tokenDigest(token)
    XCTAssertEqual(PresenceDeviceRecords.registrationStep(registered, externalUserId: "cus_123", presenceToken: token), .registered)
    XCTAssertEqual(
      PresenceDeviceRecords.registrationStep(registered, externalUserId: "cus_123", presenceToken: "hmac-token-2"),
      .newKey(discard: "tag"))
    XCTAssertEqual(PresenceDeviceRecords.registrationStep(keyed, externalUserId: "cus_123", presenceToken: token), .reuse(keyed))
    XCTAssertEqual(PresenceDeviceRecords.registrationStep(keyed, externalUserId: "cus_other", presenceToken: token), .newKey(discard: "tag"))
    let refused = PresenceDeviceRecord(externalUserId: "cus_123", refusedFor: PresenceDeviceRecords.tokenDigest(token))
    XCTAssertEqual(PresenceDeviceRecords.registrationStep(refused, externalUserId: "cus_123", presenceToken: token), .refused)
    XCTAssertEqual(
      PresenceDeviceRecords.registrationStep(refused, externalUserId: "cus_123", presenceToken: "hmac-token-2"),
      .newKey(discard: nil))
  }

  func testAnAnswerWritesBackOnlyOverTheDeviceItWasSentFor() {
    let sent = PresenceDeviceRecord(
      externalUserId: "cus_123", tag: "tag", publicKey: "spki", keyStorage: "secure_enclave", deviceId: "upd_1",
      lastSignedAt: 5)
    var later = sent
    later.lastSignedAt = 6
    XCTAssertTrue(PresenceDeviceRecords.stillHeld(sent, later))
    // A logout, a deletion or a new key while the request was out.
    XCTAssertFalse(PresenceDeviceRecords.stillHeld(sent, nil))
    var rekeyed = sent
    rekeyed.tag = "tag-2"
    XCTAssertFalse(PresenceDeviceRecords.stillHeld(sent, rekeyed))
    var reregistered = sent
    reregistered.deviceId = "upd_2"
    XCTAssertFalse(PresenceDeviceRecords.stillHeld(sent, reregistered))
    var other = sent
    other.externalUserId = "cus_other"
    XCTAssertFalse(PresenceDeviceRecords.stillHeld(sent, other))
  }

  func testSealsSignThePostedRowAndSkipWhatCannotBeSigned() throws {
    let key = P256.Signing.PrivateKey()
    let sign: (String) -> String? = { text in
      (try? key.signature(for: Data(text.utf8)))?.derRepresentation.base64EncodedString()
    }
    let queued: [[String: Any]] = [
      ["day": "2026-11-20", "mockLocation": true, "dwellMinutes": 610, "nightPresent": true, "samples": 14,
       "observedAtMillis": Int64(1_795_000_000_000)],
      // Queued before 4.5.0: no observedAt, so no seal, and still posted.
      ["day": "2026-11-21", "dwellMinutes": 610, "nightPresent": true, "samples": 14],
    ]
    var observations = queued.map { PresenceWire.observation($0, emulator: true) }
    XCTAssertTrue(PresenceSeal.apply(
      queued: queued, observations: &observations, deviceId: "upd_1", externalUserId: "cus_123", sign: sign))

    let seal = try XCTUnwrap(observations[0]["seal"] as? [String: Any])
    XCTAssertEqual(seal["observedAt"] as? String, "2026-11-18T11:06:40.000Z")
    let text = "toden-presence-seal-v1\nupd_1\ncus_123\n2026-11-20|geofence|610|1|14|1|1\n1795000000000"
    let signature = try P256.Signing.ECDSASignature(
      derRepresentation: try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(seal["signature"] as? String))))
    XCTAssertTrue(key.publicKey.isValidSignature(signature, for: Data(text.utf8)), "the seal covers the row as posted")
    XCTAssertNil(observations[1]["seal"])
  }

  func testAKeyThatCannotSignLeavesEveryEntryUnsealed() {
    let queued: [[String: Any]] = [["day": "2026-11-20", "observedAtMillis": Int64(1)]]
    var observations = queued.map { PresenceWire.observation($0, emulator: false) }
    XCTAssertFalse(PresenceSeal.apply(
      queued: queued, observations: &observations, deviceId: "upd_1", externalUserId: "cus_123", sign: { _ in nil }))
    XCTAssertNil(observations[0]["seal"])
  }

  private func run(_ days: [String], answers: [Int?]) -> PresenceFlush.Result {
    var remainingAnswers = answers
    var out: PresenceFlush.Result?
    PresenceFlush.run(
      queue: days.map { ["day": $0] },
      post: { _, completion in completion(remainingAnswers.removeFirst()) },
      done: { out = $0 })
    return out!
  }

  private func days(_ count: Int) -> [String] {
    (1...count).map { String(format: "2026-%02d-%02d", $0 <= 31 ? 10 : 11, (($0 - 1) % 31) + 1) }
  }

  func testTheFlushReportsWhatWasSentAndWhatWasDropped() {
    let result = run(days(40), answers: [200, 400])
    XCTAssertEqual(result.sent.count, 31)
    XCTAssertEqual(result.dropped.count, 9)
    XCTAssertTrue(result.remaining.isEmpty)
    XCTAssertFalse(result.refused)
  }

  func testARefusalKeepsTheRestQueued() {
    let result = run(days(40), answers: [201, 403])
    XCTAssertEqual(result.sent.count, 31)
    XCTAssertEqual(result.remaining.count, 9)
    XCTAssertTrue(result.refused)
    XCTAssertTrue(result.dropped.isEmpty)
  }

  func testAHeldWatchKeepsDaysAfterItsDeadline() {
    let result = run(["2026-11-19", "2026-11-20", "2026-11-21"], answers: [201])
    let removed = PresenceDeviceRules.removableAfterSend(result.sent, heldDeadlineDay: "2026-11-20")
    XCTAssertEqual(removed.compactMap { $0["day"] as? String }, ["2026-11-19", "2026-11-20"])
  }
}
