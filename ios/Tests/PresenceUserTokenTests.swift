import XCTest
@testable import toden_flutter

/// Replays the background cases of test/user_token_vectors.json (package root),
/// shared with the RN SDK's userTokenVectors.test.ts, Dart's
/// user_token_vectors_test.dart and Android's PresenceUserTokenTest.kt.
final class PresenceUserTokenTests: XCTestCase {
  private func vectors() throws -> [String: Any] {
    // ios/Tests/PresenceUserTokenTests.swift → ../../test/user_token_vectors.json
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("test/user_token_vectors.json")
    return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
  }

  func testNamesTheHeaderTheServerReads() throws {
    XCTAssertEqual(PresenceUserToken.header, try vectors()["header"] as? String)
    XCTAssertEqual(PresenceFlush.chunkDays, try vectors()["chunkDays"] as? Int)
  }

  func testBackgroundFlushMatchesTheSharedCases() throws {
    let doc = try vectors()
    let now = (doc["nowMillis"] as! NSNumber).int64Value
    let cases = doc["background"] as! [[String: Any]]
    XCTAssertGreaterThanOrEqual(cases.count, 10, "meaningful case set")
    for v in cases {
      let name = v["name"] as! String
      let raw = v["token"]
      let inUse = !(raw is NSNull)
      let read: PresenceUserToken.Read
      var stale = false
      if let word = raw as? String {
        read = word == "locked" ? .locked : .missing
      } else if let t = raw as? [String: Any] {
        stale = t["stale"] as? Bool ?? false
        read = .stored(PresenceUserToken.Record(
          externalUserId: t["externalUserId"] as! String, token: t["token"] as! String,
          expiresAtMillis: (t["expiresAtMillis"] as! NSNumber).int64Value, stale: stale))
      } else {
        read = .missing
      }
      let queue = (v["queue"] as! [String]).map { ["day": $0] as [String: Any] }
      let responses = (v["responses"] as! [NSNumber]).map { $0.intValue }
      var posts: [[String]] = []
      var remaining = queue.map { $0["day"] as! String }
      var header: String? = nil
      let decision = PresenceUserToken.decide(
        inUse: inUse, read: read, externalUserId: "cus_123", nowMillis: now)
      if decision != .skip {
        if case .use(let token) = decision { header = token }
        var answered = 0
        var finished = false
        PresenceFlush.run(
          queue: queue,
          post: { chunk, completion in
            posts.append(chunk.map { $0["day"] as! String })
            let status = responses[answered]
            answered += 1
            completion(status == 0 ? nil : status)
          },
          done: { result in
            remaining = result.remaining.map { $0["day"] as! String }
            if result.refused && header != nil { stale = true }
            finished = true
          }
        )
        XCTAssertTrue(finished, "\(name): runs synchronously with a synchronous poster")
      }
      XCTAssertEqual(posts, v["posts"] as! [[String]], "\(name): posts")
      if !posts.isEmpty { XCTAssertEqual(header, v["header"] as? String, "\(name): header") }
      XCTAssertEqual(remaining.sorted(), (v["remaining"] as! [String]).sorted(), "\(name): remaining")
      XCTAssertEqual(stale, v["stale"] as! Bool, "\(name): stale")
    }
  }

  func testAWellFormedTokenIsTheOnlyKindKept() {
    XCTAssertTrue(PresenceUserToken.wellFormed("ut_test_" + String(repeating: "A", count: 43)))
    XCTAssertFalse(PresenceUserToken.wellFormed("ut_test_short"))
    XCTAssertFalse(PresenceUserToken.wellFormed("pk_test_" + String(repeating: "A", count: 43)))
  }

  func testARefusalMarksOnlyTheTokenThatWasSentStale() {
    let a = PresenceUserToken.Record(
      externalUserId: "cus_123", token: "ut_test_" + String(repeating: "A", count: 43),
      expiresAtMillis: 1_795_000_000_000, stale: false)
    let b = PresenceUserToken.Record(
      externalUserId: a.externalUserId, token: "ut_test_" + String(repeating: "B", count: 43),
      expiresAtMillis: a.expiresAtMillis, stale: false)
    // The flush sent A; a silent push stored B while it was out: B stays good.
    XCTAssertNil(PresenceUserToken.staleAfterRefusal(read: .stored(b), sentToken: a.token))
    var staleA = a
    staleA.stale = true
    XCTAssertEqual(PresenceUserToken.staleAfterRefusal(read: .stored(a), sentToken: a.token), staleA)
    XCTAssertNil(PresenceUserToken.staleAfterRefusal(read: .missing, sentToken: a.token))
    XCTAssertNil(PresenceUserToken.staleAfterRefusal(read: .locked, sentToken: a.token))
  }

  func testTheStoredRecordRoundTrips() {
    let record = PresenceUserToken.Record(
      externalUserId: "cus_123", token: "ut_test_" + String(repeating: "A", count: 43),
      expiresAtMillis: 1_795_000_000_000, stale: true)
    XCTAssertEqual(PresenceUserToken.decode(PresenceUserToken.encode(record)!), record)
  }
}

/// The HMAC presenceToken's one-time move out of UserDefaults (R65).
final class PresenceHmacTokenTests: XCTestCase {
  func testAKeychainCopyForThisUserIsUsed() {
    XCTAssertEqual(
      PresenceHmacToken.step(defaultsToken: nil, keychain: .stored(externalUserId: "u", token: "k"), externalUserId: "u"),
      .use("k"))
    XCTAssertEqual(
      PresenceHmacToken.step(defaultsToken: "d", keychain: .stored(externalUserId: "u", token: "k"), externalUserId: "u"),
      .use("k"))
    XCTAssertTrue(PresenceHmacToken.keychainHas(.stored(externalUserId: "u", token: "k"), "u"))
  }

  func testAUserDefaultsCopyIsMovedOnce() {
    XCTAssertEqual(PresenceHmacToken.step(defaultsToken: "d", keychain: .missing, externalUserId: "u"), .moveFromDefaults("d"))
    XCTAssertEqual(
      PresenceHmacToken.step(defaultsToken: "d", keychain: .stored(externalUserId: "other", token: "k"), externalUserId: "u"),
      .moveFromDefaults("d"))
  }

  func testALockedKeychainHoldsTheFlushUnlessAnOldCopyRemains() {
    XCTAssertEqual(PresenceHmacToken.step(defaultsToken: nil, keychain: .locked, externalUserId: "u"), .held)
    XCTAssertEqual(PresenceHmacToken.step(defaultsToken: "d", keychain: .locked, externalUserId: "u"), .use("d"))
  }

  func testNoTokenAnywhereSendsNone() {
    XCTAssertEqual(PresenceHmacToken.step(defaultsToken: nil, keychain: .missing, externalUserId: "u"), .use(nil))
    XCTAssertEqual(
      PresenceHmacToken.step(defaultsToken: nil, keychain: .stored(externalUserId: "other", token: "k"), externalUserId: "u"),
      .use(nil))
  }

  func testTheKeychainRecordRoundTrips() throws {
    let data = try XCTUnwrap(PresenceHmacToken.encode(externalUserId: "u", token: "k"))
    let pair = try XCTUnwrap(PresenceHmacToken.decode(data))
    XCTAssertEqual(pair.externalUserId, "u")
    XCTAssertEqual(pair.token, "k")
  }
}
