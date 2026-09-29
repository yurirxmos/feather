import XCTest
@testable import FeatherCore

final class ElapsedTimeTests: XCTestCase {
    func testShowsWholeSecondsUnderAMinute() {
        XCTAssertEqual(ElapsedTime.string(0), "0s")
        XCTAssertEqual(ElapsedTime.string(11.9), "11s")
        XCTAssertEqual(ElapsedTime.string(59.99), "59s")
    }

    func testSwitchesToMinutesAndHours() {
        XCTAssertEqual(ElapsedTime.string(60), "1m 0s")
        XCTAssertEqual(ElapsedTime.string(125.7), "2m 5s")
        XCTAssertEqual(ElapsedTime.string(3_725), "1h 2m")
    }

    func testClampsNegativeValues() {
        XCTAssertEqual(ElapsedTime.string(-3), "0s")
    }
}
