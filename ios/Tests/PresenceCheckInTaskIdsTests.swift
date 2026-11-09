import XCTest
@testable import toden_flutter

/// Which BGTask ids are registered and which one is submitted. Registering an
/// id the host did not list crashes the app, so these pin that only listed ids
/// come back, and that the Toden id wins when both are listed.
final class PresenceCheckInTaskIdsTests: XCTestCase {
  private let current = "co.toden.presence.checkin"
  private let legacy = "co.myazahq.kyc.presence.checkin"
  private let fetch = ["fetch"]

  func testOnlyTheNewIdListed() {
    XCTAssertEqual(PresenceCheckInTaskIds.permitted(listed: [current], backgroundModes: fetch), [current])
    XCTAssertEqual(PresenceCheckInTaskIds.submitId(listed: [current], backgroundModes: fetch), current)
  }

  func testOnlyTheLegacyIdListedKeepsWorking() {
    XCTAssertEqual(PresenceCheckInTaskIds.permitted(listed: [legacy], backgroundModes: fetch), [legacy])
    XCTAssertEqual(PresenceCheckInTaskIds.submitId(listed: [legacy], backgroundModes: fetch), legacy)
  }

  func testBothListedRegistersBothAndSubmitsTheNewOne() {
    XCTAssertEqual(PresenceCheckInTaskIds.permitted(listed: [legacy, current], backgroundModes: fetch), [current, legacy])
    XCTAssertEqual(PresenceCheckInTaskIds.submitId(listed: [legacy, current], backgroundModes: fetch), current)
  }

  func testNeitherListedRegistersNothing() {
    XCTAssertEqual(PresenceCheckInTaskIds.permitted(listed: ["com.example.other"], backgroundModes: fetch), [])
    XCTAssertEqual(PresenceCheckInTaskIds.permitted(listed: nil, backgroundModes: fetch), [])
    XCTAssertNil(PresenceCheckInTaskIds.submitId(listed: nil, backgroundModes: fetch))
  }

  func testWithoutTheFetchModeNothingIsRegistered() {
    XCTAssertEqual(PresenceCheckInTaskIds.permitted(listed: [current, legacy], backgroundModes: ["location"]), [])
    XCTAssertEqual(PresenceCheckInTaskIds.permitted(listed: [current, legacy], backgroundModes: nil), [])
    XCTAssertNil(PresenceCheckInTaskIds.submitId(listed: [current], backgroundModes: nil))
  }
}
