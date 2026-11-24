import CryptoKit
import Security
import XCTest
@testable import toden_flutter

/// Replays test/presence_seal_vectors.json (package root), shared with the RN
/// SDK's presenceDeviceVectors.test.ts, Dart's presence_device_vectors_test.dart
/// and Android's PresenceDeviceTest.kt.
final class PresenceDeviceTests: XCTestCase {
  private func load(_ name: String) throws -> [String: Any] {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("test/\(name)")
    return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
  }

  private func cases(_ doc: [String: Any], _ key: String) -> [[String: Any]] { doc[key] as! [[String: Any]] }
  private func int64(_ v: Any?) -> Int64? { (v as? NSNumber)?.int64Value }

  func testUsesTheSharedIntervalsAndWrapsTheEnclavePointAsCoreReadsIt() throws {
    let doc = try load("presence_seal_vectors.json")
    XCTAssertEqual(PresenceDeviceRules.refreshIntervalMillis, int64(doc["refreshIntervalMillis"]))
    XCTAssertEqual(PresenceDeviceRules.backOffMillis, int64(doc["backOffMillis"]))
    let hex = PresenceDeviceRules.p256SpkiPrefix.map { String(format: "%02x", $0) }.joined()
    XCTAssertEqual(hex, doc["spkiPrefixHex"] as? String)
    let key = doc["key"] as! [String: Any]
    let point = Data(base64Encoded: key["x963"] as! String)!
    XCTAssertEqual(PresenceDeviceRules.spki(fromX963: point)?.base64EncodedString(), key["spki"] as? String)
    XCTAssertNil(PresenceDeviceRules.spki(fromX963: point.dropFirst()))
  }

  /// SecKeyCreateSignature(.ecdsaSignatureMessageX962SHA256) gives DER, which
  /// is what core verifies: the shared signature verifies the same way here.
  func testASharedSignatureVerifiesAndATamperedTextDoesNot() throws {
    let doc = try load("presence_seal_vectors.json")
    let sig = doc["signature"] as! [String: Any]
    let pub = try P256.Signing.PublicKey(derRepresentation: Data(base64Encoded: sig["publicKey"] as! String)!)
    let signature = try P256.Signing.ECDSASignature(derRepresentation: Data(base64Encoded: sig["signature"] as! String)!)
    XCTAssertTrue(pub.isValidSignature(signature, for: Data((sig["text"] as! String).utf8)))
    XCTAssertFalse(pub.isValidSignature(signature, for: Data((sig["tamperedText"] as! String).utf8)))
  }

  /// Core's file, copied into the fixture: core's signatures verify over the
  /// texts built here, so a builder that drifts from core fails.
  func testCoreSignaturesVerifyOverTheTextsBuiltHere() throws {
    let doc = try load("presence_seal_vectors.json")
    let c = doc["core"] as! [String: Any]
    let publicKey = c["publicKey"] as! String
    let pub = try P256.Signing.PublicKey(derRepresentation: Data(base64Encoded: publicKey)!)
    func holds(_ text: String, _ signature: Any?) throws -> Bool {
      let sig = try P256.Signing.ECDSASignature(derRepresentation: Data(base64Encoded: signature as! String)!)
      return pub.isValidSignature(sig, for: Data(text.utf8))
    }
    let reg = c["registration"] as! [String: Any]
    let registration = PresenceDeviceRules.registrationText(
      externalUserId: reg["externalUserId"] as! String, publicKey: publicKey, signedAt: int64(reg["signedAt"])!)
    XCTAssertEqual(registration, reg["text"] as? String)
    XCTAssertTrue(try holds(registration, reg["signature"]))
    let ref = c["refresh"] as! [String: Any]
    let refresh = PresenceDeviceRules.refreshText(
      deviceId: ref["deviceId"] as! String, externalUserId: ref["externalUserId"] as! String,
      signedAt: int64(ref["signedAt"])!)
    XCTAssertEqual(refresh, ref["text"] as? String)
    XCTAssertTrue(try holds(refresh, ref["signature"]))
    let s = c["seal"] as! [String: Any]
    let seal = PresenceDeviceRules.sealText(
      deviceId: s["deviceId"] as! String, externalUserId: s["externalUserId"] as! String,
      observation: s["observation"] as! [String: Any], observedAtMillis: int64(s["observedAtMillis"])!)
    XCTAssertEqual(seal, s["text"] as? String)
    XCTAssertTrue(try holds(seal, s["signature"]))
  }

  func testTextsMatch() throws {
    let doc = try load("presence_seal_vectors.json")
    for c in cases(doc, "registration") {
      XCTAssertEqual(
        PresenceDeviceRules.registrationText(
          externalUserId: c["externalUserId"] as! String, publicKey: c["publicKey"] as! String,
          signedAt: int64(c["signedAt"])!),
        c["text"] as? String)
    }
    for c in cases(doc, "refresh") {
      XCTAssertEqual(
        PresenceDeviceRules.refreshText(
          deviceId: c["deviceId"] as! String, externalUserId: c["externalUserId"] as! String,
          signedAt: int64(c["signedAt"])!),
        c["text"] as? String)
    }
    for c in cases(doc, "seal") {
      let name = c["name"] as! String
      XCTAssertEqual(
        PresenceDeviceRules.sealText(
          deviceId: c["deviceId"] as! String, externalUserId: c["externalUserId"] as! String,
          observation: c["observation"] as! [String: Any], observedAtMillis: int64(c["observedAtMillis"])!),
        c["text"] as? String, name)
      XCTAssertEqual(PresenceDeviceRules.isoMillis(int64(c["observedAtMillis"])!), c["observedAt"] as? String, name)
    }
  }

  /// A queued entry is sealed over the row the flush will post for it.
  func testTheSealedRowIsThePostedRow() {
    let entry: [String: Any] = ["day": "2026-11-20", "dwellMinutes": 610, "nightPresent": true, "samples": 14]
    let wire = PresenceWire.observation(entry, emulator: false)
    XCTAssertEqual(PresenceWire.digestRow(wire), "2026-11-20|geofence|610|1|14|0|0")
    let flagged = PresenceWire.observation(["day": "2026-11-20", "mockLocation": true], emulator: true)
    XCTAssertEqual(PresenceWire.digestRow(flagged), "2026-11-20|geofence|1|0|1|1|1")
  }

  func testRulesMatch() throws {
    let doc = try load("presence_seal_vectors.json")
    for c in cases(doc, "signedAt") {
      XCTAssertEqual(
        PresenceDeviceRules.nextSignedAt(correctedNow: int64(c["correctedNow"])!, lastSent: int64(c["lastSent"])),
        int64(c["expected"]), c["name"] as? String ?? "")
    }
    for c in cases(doc, "clockOffset") {
      XCTAssertEqual(
        PresenceDeviceRules.clockOffset(date: c["date"] as? String, deviceNowMillis: int64(c["deviceNowMillis"])!),
        int64(c["expected"]), c["name"] as? String ?? "")
    }
    for c in cases(doc, "refreshAnswers") {
      XCTAssertEqual(
        PresenceDeviceRules.refreshOutcome(status: c["status"] as? Int, code: c["code"] as? String).rawValue,
        c["outcome"] as? String, c["name"] as? String ?? "")
    }
    for c in cases(doc, "registrationAnswers") {
      XCTAssertEqual(
        PresenceDeviceRules.registrationOutcome(status: c["status"] as? Int, code: c["code"] as? String).rawValue,
        c["outcome"] as? String, c["name"] as? String ?? "")
    }
    for c in cases(doc, "refreshDue") {
      XCTAssertEqual(
        PresenceDeviceRules.refreshDue(
          nowMillis: int64(c["nowMillis"])!, lastRefreshAt: int64(c["lastRefreshAtMillis"]),
          backOffUntil: int64(c["backOffUntilMillis"])),
        c["due"] as? Bool, c["name"] as? String ?? "")
    }
    for c in cases(doc, "heldWatch") {
      let sent = (c["sent"] as! [String]).map { ["day": $0] as [String: Any] }
      let removed = PresenceDeviceRules.removableAfterSend(sent, heldDeadlineDay: c["deadlineDay"] as? String)
      XCTAssertEqual(removed.map { $0["day"] as! String }, c["removed"] as? [String], c["name"] as? String ?? "")
    }
  }

  /// Background refresh has no Dart, so the identity check runs natively on the same cases.
  func testARefreshedTokenIsCheckedAsDartChecksAProvidersAnswer() throws {
    let doc = try load("user_token_vectors.json")
    let now = int64(doc["nowMillis"])!
    for v in cases(doc, "identity") {
      let checked = PresenceUserToken.checkMinted(
        v["body"] as! [String: Any], externalUserId: v["actingFor"] as! String,
        apiKey: v["apiKey"] as! String, nowMillis: now)
      XCTAssertEqual(checked == nil ? "user_token_mismatch" : "ok", v["expected"] as? String, v["name"] as? String ?? "")
    }
    XCTAssertEqual(PresenceUserToken.parseExpiresAt("2026-11-18T11:06:40.000Z"), 1_795_000_000_000)
    XCTAssertNil(PresenceUserToken.parseExpiresAt("2026-11-18T12:06:40+01:00"))
  }

  /// The key can never be exported and signs with no prompt after the first unlock.
  func testTheKeyRequestIsNeverExportableAndSignsInTheBackground() throws {
    let r = PresenceDeviceKey.request
    XCTAssertTrue(r.secureEnclave)
    XCTAssertTrue(r.permanent)
    XCTAssertTrue(r.privateKeyUsageOnly)
    XCTAssertFalse(r.biometryOrPasscode)
    XCTAssertEqual(r.accessible, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    let attributes = try XCTUnwrap(PresenceDeviceKey.attributes(tag: "t"))
    XCTAssertEqual(attributes[kSecAttrTokenID as String] as? String, kSecAttrTokenIDSecureEnclave as String)
    XCTAssertEqual(attributes[kSecAttrKeySizeInBits as String] as? Int, 256)
    let priv = try XCTUnwrap(attributes[kSecPrivateKeyAttrs as String] as? [String: Any])
    XCTAssertEqual(priv[kSecAttrIsPermanent as String] as? Bool, true)
    XCTAssertNotNil(priv[kSecAttrAccessControl as String])
    // A Secure Enclave key has no extractable private half; nothing here asks for one.
    XCTAssertNil(priv[kSecAttrIsExtractable as String])
  }
}
