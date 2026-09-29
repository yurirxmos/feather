import XCTest
@testable import FeatherCore

final class ContextRelevanceTests: XCTestCase {
    func testIndependentInstructionDoesNotNeedContext() {
        XCTAssertFalse(ContextRelevance.needsContext("Write a short poem about rain"))
    }

    func testScreenReferenceNeedsContextInEnglish() {
        XCTAssertTrue(ContextRelevance.needsContext("Rewrite this in a warmer tone"))
    }

    func testScreenReferenceNeedsContextInPortuguese() {
        XCTAssertTrue(ContextRelevance.needsContext("Resuma o texto acima"))
    }

    func testEmptyInstructionIsConservative() {
        XCTAssertTrue(ContextRelevance.needsContext(""))
    }
}
