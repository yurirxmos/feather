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

        values.set(ConnectionKind.chatGPT.rawValue, forKey: SettingsKey.connection)
        XCTAssertEqual(Settings.current(values).model, ChatGPTModelCatalog.defaultModel)
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
        XCTAssertEqual(Settings.model(afterChangingTo: .chatGPT, preserving: OpenCodeGoProvider.defaultModel), ChatGPTModelCatalog.defaultModel)
        XCTAssertEqual(Settings.model(afterChangingTo: .openCodeGo, preserving: ChatGPTModelCatalog.defaultModel), OpenCodeGoProvider.defaultModel)
        XCTAssertEqual(Settings.model(afterChangingTo: .chatGPT, preserving: "custom-model"), "custom-model")
    }

    func testCredentialStoreSelectsProviderCredentials() {
        let store = MemoryCredentialStore(apiKey: "go-key")
        let go = Settings(connection: .openCodeGo, model: "m", hotkey: .optionSpace, includeScreenshot: true)
        let chatGPT = Settings(connection: .chatGPT, model: "m", hotkey: .optionSpace, includeScreenshot: true)
        XCTAssertTrue(go.hasCredentials(using: store))
        XCTAssertFalse(chatGPT.hasCredentials(using: store))
        XCTAssertEqual((go.makeProvider(apiKey: store.apiKey()!) as? OpenCodeGoProvider)?.apiKey, "go-key")

        let credentials = ChatGPTCredentials(accessToken: "access", refreshToken: "refresh", expiresAt: .distantFuture)
        XCTAssertTrue(store.setChatGPTCredentials(credentials))
        XCTAssertTrue(chatGPT.hasCredentials(using: store))
        XCTAssertEqual((chatGPT.makeProvider(accessToken: "access") as? ChatGPTProvider)?.accessToken, "access")
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
        let credentials = ChatGPTCredentials(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture)
        XCTAssertTrue(store.setChatGPTCredentials(credentials))
        store.deleteChatGPTCredentials()
        XCTAssertNil(store.chatGPTCredentials())
    }

    func testTheProviderInUseStaysWhileItIsSetUp() {
        XCTAssertEqual(Settings.connection(current: .chatGPT, setUp: [.chatGPT, .openCodeGo], preferring: .openCodeGo), .chatGPT)
    }

    func testTheFirstProviderSetUpIsUsed() {
        XCTAssertEqual(Settings.connection(current: .openCodeGo, setUp: [.chatGPT], preferring: .chatGPT), .chatGPT)
    }

    func testRemovingTheProviderInUseFallsBackInOrder() {
        XCTAssertEqual(Settings.connection(current: .chatGPT, setUp: [.openCodeGo, .featherPlus]), .featherPlus)
        XCTAssertEqual(Settings.connection(current: .chatGPT, setUp: [.openCodeGo]), .openCodeGo)
        XCTAssertEqual(Settings.connection(current: .chatGPT, setUp: []), .chatGPT)
    }

    func testProvidersSetUpFollowTheStoredCredentials() {
        let store = MemoryCredentialStore(apiKey: "key", plusToken: "token")
        XCTAssertEqual(Settings.providersSetUp(in: store, plusAvailable: true), [.openCodeGo, .featherPlus])
        XCTAssertEqual(Settings.providersSetUp(in: store, plusAvailable: false), [.openCodeGo])
    }

    func testOnboardingRunsOnceForEveryInstall() {
        XCTAssertFalse(Settings.onboardingCompleted(stored: nil))
        XCTAssertFalse(Settings.onboardingCompleted(stored: false))
        XCTAssertTrue(Settings.onboardingCompleted(stored: true))
    }
}

