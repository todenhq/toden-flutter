import XCTest
@testable import toden_flutter

/// The background flush's body. A port of the RN SDK's presenceToken.test.ts.
final class PresenceWireTests: XCTestCase {
  private let days: [[String: Any]] = [["day": "2026-11-01"]]

  func testCarriesTheTokenBesideTheObservations() {
    let body = PresenceWire.body(externalUserId: "user_1", presenceToken: "tok_1", observations: days)
    XCTAssertEqual(body["externalUserId"] as? String, "user_1")
    XCTAssertEqual(body["presenceToken"] as? String, "tok_1")
    XCTAssertEqual((body["observations"] as? [[String: Any]])?.count, 1)
  }

  func testLeavesItOutWhenThePinHasNone() {
    XCTAssertNil(PresenceWire.body(externalUserId: "user_1", presenceToken: nil, observations: days)["presenceToken"])
    XCTAssertNil(PresenceWire.body(externalUserId: "user_1", presenceToken: "", observations: days)["presenceToken"])
  }
}
