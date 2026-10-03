import XCTest
@testable import FeatherCore

final class APIKeyTests: XCTestCase {
    func testMasksKeyAfterTenCharacters() {
        XCTAssertEqual(APIKey.masked("abcdef123456"), "abcdef1234...")
    }

    func testShowsAShortKeyWhole() {
        XCTAssertEqual(APIKey.masked("abcdef"), "abcdef...")
    }

    func testMasksShortKey() {
        XCTAssertEqual(APIKey.masked("abc"), "abc...")
    }

    func testEmptyKeyStaysEmpty() {
        XCTAssertEqual(APIKey.masked("   "), "")
    }
}
