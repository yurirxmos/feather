import XCTest
@testable import ContextBarCore

final class APIKeyTests: XCTestCase {
    func testMasksKeyAfterSixCharacters() {
        XCTAssertEqual(APIKey.masked("abcdef123456"), "abcdef...")
    }

    func testMasksKeyWithExactlySixCharacters() {
        XCTAssertEqual(APIKey.masked("abcdef"), "abcdef...")
    }

    func testMasksShortKey() {
        XCTAssertEqual(APIKey.masked("abc"), "abc...")
    }

    func testEmptyKeyStaysEmpty() {
        XCTAssertEqual(APIKey.masked("   "), "")
    }
}
