import XCTest
@testable import FeatherCore

final class SettingsTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "FeatherTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testDefaultsAndConnectionSpecificModel() {
        let values = defaults()
        XCTAssertEqual(Settings.current(values), Settings(connection: .openCodeGo, model: OpenCodeGoProvider.defaultModel, hotkey: .optionSpace, includeScreenshot: true))

        values.set(ConnectionKind.openAI.rawValue, forKey: SettingsKey.connection)
        XCTAssertEqual(Settings.current(values).model, OpenAIProvider.defaultModel)
    }

    func testTheChatGPTSignInChoiceBecomesOpenAI() {
        let values = defaults()
        values.set("chatGPT", forKey: SettingsKey.connection)
        Settings.migrateLegacyConnection(values)
        XCTAssertEqual(values.string(forKey: SettingsKey.connection), "openAI")
        XCTAssertEqual(Settings.current(values).connection, .openAI)

        values.set("claude", forKey: SettingsKey.connection)
        Settings.migrateLegacyConnection(values)
        XCTAssertEqual(values.string(forKey: SettingsKey.connection), "claude")
    }

    func testSettingsTrimModelAndPreserveExplicitValues() {
        let values = defaults()
        values.set("  custom-model  ", forKey: SettingsKey.model)
        values.set(HotkeyPreset.shiftCommandSpace.rawValue, forKey: SettingsKey.hotkey)
        values.set(false, forKey: SettingsKey.includeScreenshot)
        values.set("  Do not use emojis.  ", forKey: SettingsKey.customInstructions)
        let settings = Settings.current(values)
        XCTAssertEqual(settings.model, "custom-model")
        XCTAssertEqual(settings.hotkey, .shiftCommandSpace)
        XCTAssertFalse(settings.includeScreenshot)
        XCTAssertEqual(settings.customInstructions, "Do not use emojis.")
    }

    func testConnectionChangeOnlyReplacesKnownDefaultModels() {
        XCTAssertEqual(Settings.model(afterChangingTo: .openAI, preserving: OpenCodeGoProvider.defaultModel), OpenAIProvider.defaultModel)
        XCTAssertEqual(Settings.model(afterChangingTo: .openCodeGo, preserving: OpenAIProvider.defaultModel), OpenCodeGoProvider.defaultModel)
        XCTAssertEqual(Settings.model(afterChangingTo: .openAI, preserving: "custom-model"), "custom-model")
    }

    func testCredentialStoreSelectsProviderCredentials() {
        let store = MemoryCredentialStore(apiKey: "go-key")
        let go = Settings(connection: .openCodeGo, model: "m", hotkey: .optionSpace, includeScreenshot: true)
        let openAI = Settings(connection: .openAI, model: "m", hotkey: .optionSpace, includeScreenshot: true)
        XCTAssertTrue(go.hasCredentials(using: store))
        XCTAssertFalse(openAI.hasCredentials(using: store))
        XCTAssertEqual((go.makeProvider(apiKey: store.apiKey()!) as? OpenCodeGoProvider)?.apiKey, "go-key")

        XCTAssertTrue(store.setOpenAIAPIKey("sk-openai"))
        XCTAssertTrue(openAI.hasCredentials(using: store))
        XCTAssertEqual((openAI.makeProvider(openAIAPIKey: "sk-openai") as? OpenAIProvider)?.apiKey, "sk-openai")
    }

    func testMemoryCredentialStoreMutations() {
        let store = MemoryCredentialStore()
        XCTAssertTrue(store.setAPIKey(" key "))
        XCTAssertEqual(store.apiKey(), "key")
        XCTAssertTrue(store.setAPIKey("  "))
        XCTAssertNil(store.apiKey())
        XCTAssertTrue(store.setAPIKey("key"))
        store.deleteAPIKey()
        XCTAssertNil(store.apiKey())
        XCTAssertTrue(store.setOpenAIAPIKey(" sk "))
        XCTAssertEqual(store.openAIAPIKey(), "sk")
        store.deleteOpenAIAPIKey()
        XCTAssertNil(store.openAIAPIKey())
    }

    func testTheProviderInUseStaysWhileItIsSetUp() {
        XCTAssertEqual(Settings.connection(current: .openAI, setUp: [.openAI, .openCodeGo], preferring: .openCodeGo), .openAI)
    }

    func testTheFirstProviderSetUpIsUsed() {
        XCTAssertEqual(Settings.connection(current: .openCodeGo, setUp: [.openAI], preferring: .openAI), .openAI)
    }

    func testRemovingTheProviderInUseFallsBackInOrder() {
        XCTAssertEqual(Settings.connection(current: .openAI, setUp: [.openCodeGo, .featherPlus]), .featherPlus)
        XCTAssertEqual(Settings.connection(current: .openAI, setUp: [.openCodeGo]), .openCodeGo)
        XCTAssertEqual(Settings.connection(current: .openAI, setUp: []), .openAI)
    }

    func testProvidersSetUpFollowTheStoredCredentials() {
        let store = MemoryCredentialStore(apiKey: "key", plusToken: "token")
        XCTAssertEqual(Settings.providersSetUp(in: store, plusAvailable: true), [.openCodeGo, .featherPlus])
        XCTAssertEqual(Settings.providersSetUp(in: MemoryCredentialStore(openAIAPIKey: "sk"), plusAvailable: true), [.openAI])
        XCTAssertEqual(Settings.providersSetUp(in: store, plusAvailable: false), [.openCodeGo])
    }

    func testOnboardingRunsOnceForEveryInstall() {
        XCTAssertFalse(Settings.onboardingCompleted(stored: nil))
        XCTAssertFalse(Settings.onboardingCompleted(stored: false))
        XCTAssertTrue(Settings.onboardingCompleted(stored: true))
    }
}

