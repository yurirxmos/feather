import FeatherCore
import XCTest

final class ReplyStyleTests: XCTestCase {
    func testStandardStyleAddsNothing() {
        XCTAssertEqual(ReplyStyle.standard.writingPreferences(customInstructions: ""), "")
        XCTAssertEqual(ReplyStyle.standard.writingPreferences(customInstructions: "  No emojis.  "), "No emojis.")
    }

    func testChoicesComeBeforeCustomInstructions() {
        let style = ReplyStyle(tone: .professional, length: .short, language: .portuguese)
        XCTAssertEqual(
            style.writingPreferences(customInstructions: "No emojis."),
            """
            Write in a professional, polished tone.
            Keep replies short and to the point.
            Write in Brazilian Portuguese, whatever language the conversation is in.
            No emojis.
            """
        )
    }

    func testSettingsReadStoredChoicesAndIgnoreUnknownOnes() {
        let values = UserDefaults(suiteName: "ReplyStyleTests")!
        values.removePersistentDomain(forName: "ReplyStyleTests")
        XCTAssertEqual(Settings.current(values).replyStyle, .standard)
        values.set("casual", forKey: SettingsKey.replyTone)
        values.set("detailed", forKey: SettingsKey.replyLength)
        values.set("klingon", forKey: SettingsKey.replyLanguage)
        XCTAssertEqual(Settings.current(values).replyStyle, ReplyStyle(tone: .casual, length: .detailed, language: .conversation))
    }
}
