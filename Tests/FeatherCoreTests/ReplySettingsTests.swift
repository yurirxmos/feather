import XCTest
@testable import FeatherCore

final class ReplySettingsTests: XCTestCase {
    private let sample = ReplySettings(
        customInstructions: "Do not use emojis.",
        includeScreenshot: false,
        tone: "friendly",
        length: "short",
        language: "portuguese"
    )

    private func freshDefaults(_ name: String = #function) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testStoredSettingsUseTheSameDefaultsAsSettings() {
        XCTAssertEqual(
            ReplySettings.stored(in: freshDefaults()),
            ReplySettings(customInstructions: "", includeScreenshot: true, tone: "natural", length: "matchRequest", language: "conversation")
        )
    }

    func testStoringRoundTripsAndReachesTheReplyStyle() {
        let defaults = freshDefaults()
        sample.store(in: defaults)
        XCTAssertEqual(ReplySettings.stored(in: defaults), sample)
        let settings = Settings.current(defaults)
        XCTAssertEqual(settings.customInstructions, "Do not use emojis.")
        XCTAssertFalse(settings.includeScreenshot)
        XCTAssertEqual(settings.replyStyle, ReplyStyle(tone: .friendly, length: .short, language: .portuguese))
    }

    func testAChoiceFromANewerAppSurvivesButFallsBackForReplies() {
        let defaults = freshDefaults()
        var newer = sample
        newer.tone = "poetic"
        newer.store(in: defaults)
        XCTAssertEqual(ReplySettings.stored(in: defaults).tone, "poetic")
        XCTAssertEqual(Settings.current(defaults).replyStyle.tone, .natural)
    }

    func testEncodesTheServerFieldNames() throws {
        let request = try FeatherPlus.saveReplySettingsRequest(base: "http://127.0.0.1:8787", token: "fth_x", settings: sample)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8787/v1/reply-settings")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fth_x")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["custom_instructions"] as? String, "Do not use emojis.")
        XCTAssertEqual(body["include_screenshot"] as? Bool, false)
        XCTAssertEqual(body["reply_tone"] as? String, "friendly")
        XCTAssertEqual(body["reply_length"] as? String, "short")
        XCTAssertEqual(body["reply_language"] as? String, "portuguese")

        let read = try FeatherPlus.replySettingsRequest(base: "http://127.0.0.1:8787", token: "fth_x")
        XCTAssertEqual(read.httpMethod, "GET")
        XCTAssertEqual(read.url?.path, "/v1/reply-settings")
    }

    func testDecodesTheAccountsSettingsOrNone() throws {
        let saved = Data(#"{"settings":{"custom_instructions":"Do not use emojis.","include_screenshot":false,"reply_tone":"friendly","reply_length":"short","reply_language":"portuguese"},"updated_at":"2026-10-10T12:00:00.000Z"}"#.utf8)
        XCTAssertEqual(try FeatherPlus.decodeReplySettings(saved), sample)
        XCTAssertNil(try FeatherPlus.decodeReplySettings(Data(#"{"settings":null,"updated_at":null}"#.utf8)))
        XCTAssertThrowsError(try FeatherPlus.decodeReplySettings(Data(#"{"settings":{"reply_tone":"casual"}}"#.utf8)))
    }

    func testTheAccountWinsUnlessAChangeIsPendingOrItHasNone() {
        let local = ReplySettings.stored(in: freshDefaults())
        XCTAssertEqual(ReplySettings.syncAction(local: local, remote: sample, localChangePending: false), .apply(sample))
        XCTAssertEqual(ReplySettings.syncAction(local: local, remote: sample, localChangePending: true), .upload(local))
        XCTAssertEqual(ReplySettings.syncAction(local: local, remote: nil, localChangePending: false), .upload(local))
        XCTAssertEqual(ReplySettings.syncAction(local: sample, remote: sample, localChangePending: false), .none)
    }
}
