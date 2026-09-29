import XCTest
@testable import ContextBarCore

final class PromptBuilderTests: XCTestCase {
    private let context = ScreenContext(
        appName: "Google Chrome",
        bundleID: "com.google.Chrome",
        windowTitle: "Re: meeting - Gmail",
        focusedText: "draft",
        selectedText: nil,
        screenshotJPEG: Data([1, 2, 3])
    )

    func testFirstTurnIncludesAllContext() {
        let text = PromptBuilder.firstTurn(instruction: "reply formally", context: context, options: ContextOptions())
        XCTAssertTrue(text.contains("App: Google Chrome (com.google.Chrome)"))
        XCTAssertTrue(text.contains("Window: Re: meeting - Gmail"))
        XCTAssertTrue(text.contains("Focused field text:\n\"\"\"\ndraft\n\"\"\""))
        XCTAssertTrue(text.contains("A screenshot of the active window is attached."))
        XCTAssertTrue(text.hasSuffix("Instruction: reply formally"))
    }

    func testSystemPromptRestrictsTheAppToTextGeneration() {
        XCTAssertTrue(PromptBuilder.systemPrompt.contains("Only write, rewrite"))
        XCTAssertTrue(PromptBuilder.systemPrompt.contains("Do not act as a general-purpose assistant"))
    }

    func testDisabledContextIsOmitted() {
        let options = ContextOptions(includeApp: false, includeFocusedText: false, includeWindow: false)
        let text = PromptBuilder.firstTurn(instruction: "hi", context: context, options: options)
        XCTAssertFalse(text.contains("Chrome"))
        XCTAssertFalse(text.contains("draft"))
        XCTAssertFalse(text.contains("screenshot"))
        XCTAssertTrue(text.contains("No screen context was provided."))

        let request = PromptBuilder.request(instruction: "hi", context: context, options: options, model: "m")
        XCTAssertNil(request.imageJPEG)
    }

    func testContextCanBeOmittedEntirely() {
        let request = PromptBuilder.request(
            instruction: "Write a poem",
            context: ScreenContext(appName: "Mail", focusedText: "secret"),
            options: ContextOptions(),
            model: "model",
            includeContext: false
        )
        XCTAssertEqual(request.turns[0].text, "Instruction: Write a poem")
        XCTAssertNil(request.imageJPEG)
    }

    func testSelectedTextIsIncludedOnlyWhenEnabled() {
        let context = ScreenContext(selectedText: "Important paragraph")
        let included = PromptBuilder.firstTurn(instruction: "Reply", context: context, options: ContextOptions())
        XCTAssertTrue(included.contains("Important paragraph"))

        let excluded = PromptBuilder.firstTurn(
            instruction: "Reply",
            context: context,
            options: ContextOptions(includeSelection: false)
        )
        XCTAssertFalse(excluded.contains("Important paragraph"))
    }

    func testWindowTextRespectsItsOption() {
        let context = ScreenContext(windowText: "Conversation content")
        let excluded = PromptBuilder.firstTurn(
            instruction: "Reply",
            context: context,
            options: ContextOptions(includeWindowText: false)
        )
        XCTAssertFalse(excluded.contains("Conversation content"))
    }

    func testLongFieldKeepsTail() {
        let long = String(repeating: "a", count: PromptBuilder.maxFieldCharacters) + "TAIL"
        let truncated = PromptBuilder.truncated(long)
        XCTAssertTrue(truncated.hasPrefix("[…earlier text omitted]"))
        XCTAssertTrue(truncated.hasSuffix("TAIL"))
        XCTAssertFalse(truncated.contains(String(repeating: "a", count: PromptBuilder.maxFieldCharacters)))
    }

    func testRefinementAlternatesTurns() {
        let request = PromptBuilder.request(
            instruction: "shorter",
            context: context,
            options: ContextOptions(),
            history: [Exchange(instruction: "reply formally", result: "Dear John, ...")],
            model: "m"
        )
        XCTAssertEqual(request.turns.map(\.role), [.user, .assistant, .user])
        XCTAssertTrue(request.turns[0].text.hasSuffix("Instruction: reply formally"))
        XCTAssertEqual(request.turns[1].text, "Dear John, ...")
        XCTAssertEqual(request.turns[2].text, "shorter")
        XCTAssertEqual(request.imageJPEG, Data([1, 2, 3]))
    }
}
