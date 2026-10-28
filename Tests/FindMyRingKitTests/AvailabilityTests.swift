import XCTest
@testable import FindMyRingKit

final class AvailabilityTests: XCTestCase {
    func testMissingAndUnexpectedStatusesNeverDisableAsOffline() {
        for value in [nil, "", "201", "404", "unknown"] as [String?] {
            XCTAssertEqual(DeviceAvailability(status: value), .unknown)
        }
        XCTAssertEqual(DeviceAvailability(status: "200"), .online)
        XCTAssertEqual(DeviceAvailability(status: "203"), .offline)
    }

    func testOfflineObservationExpiresAndMissingDeviceNeedsRefresh() {
        let now = Date(timeIntervalSince1970: 1000)
        let snapshot = AvailabilitySnapshot(devices: ["phone": .offline], checkedAt: now, valid: true)
        XCTAssertEqual(snapshot.state(for: "phone", at: now), .offline)
        XCTAssertEqual(snapshot.state(for: "phone", at: snapshot.expires), .unknown)
        XCTAssertEqual(snapshot.state(for: "removed", at: now), .unknown)
        XCTAssertEqual(snapshot.state(for: "phone", at: now.addingTimeInterval(-6)), .unknown)
    }

    func testFailedRefreshInvalidatesEvenRecentOnlineReading() {
        let now = Date()
        let failed = AvailabilitySnapshot(devices: ["phone": .online], checkedAt: now, valid: false)
        XCTAssertEqual(failed.state(for: "phone", at: now), .unknown)
        XCTAssertEqual(failed.state(for: "phone", at: now).title, "Needs refresh")
    }

    func testErrorBackoffAndRecovery() {
        var policy = AvailabilityPollPolicy()
        XCTAssertEqual(policy.completed(ok: true), 1)
        XCTAssertEqual(policy.completed(ok: false), 15)
        XCTAssertEqual(policy.completed(ok: false), 30)
        for _ in 0..<10 { XCTAssertLessThanOrEqual(policy.completed(ok: false), 300) }
        XCTAssertEqual(policy.completed(ok: false), 300)
        XCTAssertEqual(policy.completed(ok: true), 1)
        XCTAssertEqual(policy.completed(ok: false), 15)
    }

    func testExplicitSoundRejectionWithSuccessfulHTTPIsNotSuccess() {
        XCTAssertThrowsError(try SoundResponse.validate(["serviceErrors": [["code": "unavailable"]]]))
        XCTAssertThrowsError(try SoundResponse.validate(["statusCode": "500"]))
        XCTAssertNoThrow(try SoundResponse.validate(["statusCode": "200"]))
        XCTAssertNoThrow(try SoundResponse.validate(["serverContext": ["valid": true]]))
    }

    func testEmptySoundResponseIsUncertainRatherThanSuccessOrDefiniteFailure() {
        XCTAssertThrowsError(try SoundResponse.validate([:])) { error in
            XCTAssertEqual((error as? RingError)?.kind, .uncertain)
        }
    }

    func testFreshReadingsDoNotSuppressWidgetHeartbeat() {
        let start = Date(timeIntervalSince1970: 1000)
        var policy = AvailabilityWidgetReloadPolicy()
        var previous = AvailabilitySnapshot()
        for second in 0...10 {
            let now = start.addingTimeInterval(Double(second))
            let fresh = AvailabilitySnapshot(devices: ["phone": .online], checkedAt: now, valid: true)
            XCTAssertEqual(policy.shouldReload(previous: previous, current: fresh, now: now), second == 0 || second == 10)
            previous = fresh
        }
        let offline = AvailabilitySnapshot(devices: ["phone": .offline], checkedAt: start.addingTimeInterval(11), valid: true)
        XCTAssertTrue(policy.shouldReload(previous: previous, current: offline, now: offline.checkedAt))
    }

    func testSnapshotRoundTripRetainsOriginalTimestamp() throws {
        let original = AvailabilitySnapshot(devices: ["phone": .online, "old": .offline, "new": .unknown],
                                            checkedAt: Date(timeIntervalSince1970: 1000), valid: true)
        let roundTrip = try JSONDecoder().decode(AvailabilitySnapshot.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(roundTrip, original)
        XCTAssertEqual(roundTrip.state(for: "phone", at: Date(timeIntervalSince1970: 1100)), .unknown)
    }
}
