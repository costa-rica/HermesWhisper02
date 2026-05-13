import XCTest
@testable import HermesWhisper02

final class RuntimeSettingsStoreTests: XCTestCase {
    func testDefaultsToLLMAndDocumentedAudioValues() {
        let store = RuntimeSettingsStore(defaults: makeDefaults())
        let settings = store.load(profileID: UUID())

        XCTAssertEqual(settings.intermediaryMode, .llm)
        XCTAssertEqual(settings.speechRmsThreshold, 0.003)
        XCTAssertEqual(settings.endSilenceSeconds, 1.1)
        XCTAssertEqual(settings.minTurnSeconds, 0.8)
        XCTAssertEqual(settings.maxTurnSeconds, 8.0)
        XCTAssertEqual(settings.bargeInRmsThreshold, 0.025)
        XCTAssertEqual(settings.bargeInWindowDuration, 0.05)
        XCTAssertEqual(settings.bargeInConsecutiveWindows, 2)
    }

    func testPersistsSettingsGloballyAcrossProfiles() {
        let defaults = makeDefaults()
        let store = RuntimeSettingsStore(defaults: defaults)
        let firstID = UUID()
        let secondID = UUID()

        store.save(RuntimeSettings(
            intermediaryMode: .deterministic,
            speechRmsThreshold: 0.01,
            endSilenceSeconds: 2.0,
            minTurnSeconds: 1.0,
            maxTurnSeconds: 180.0,
            bargeInRmsThreshold: 0.04,
            bargeInWindowDuration: 0.08,
            bargeInConsecutiveWindows: 4
        ), profileID: firstID)

        let reloadedStore = RuntimeSettingsStore(defaults: defaults)
        let reloadedSettings = reloadedStore.load(profileID: firstID)
        let secondProfileSettings = reloadedStore.load(profileID: secondID)
        XCTAssertEqual(reloadedSettings.intermediaryMode, .deterministic)
        XCTAssertEqual(reloadedSettings.speechRmsThreshold, 0.01)
        XCTAssertEqual(reloadedSettings.endSilenceSeconds, 2.0)
        XCTAssertEqual(reloadedSettings.minTurnSeconds, 1.0)
        XCTAssertEqual(reloadedSettings.maxTurnSeconds, 180.0)
        XCTAssertEqual(reloadedSettings.bargeInRmsThreshold, 0.04)
        XCTAssertEqual(reloadedSettings.bargeInWindowDuration, 0.08)
        XCTAssertEqual(reloadedSettings.bargeInConsecutiveWindows, 4)
        XCTAssertEqual(secondProfileSettings, reloadedSettings)
    }

    func testMigratesExistingProfileScopedSettingsToGlobalSettings() {
        let defaults = makeDefaults()
        let profileID = UUID()
        let secondID = UUID()
        defaults.set("deterministic", forKey: "runtime.settings.\(profileID.uuidString).intermediaryMode")
        defaults.set(0.05, forKey: "runtime.settings.\(profileID.uuidString).speechRmsThreshold")
        defaults.set(2.5, forKey: "runtime.settings.\(profileID.uuidString).endSilenceSeconds")
        defaults.set(1.2, forKey: "runtime.settings.\(profileID.uuidString).minTurnSeconds")
        defaults.set(120.0, forKey: "runtime.settings.\(profileID.uuidString).maxTurnSeconds")
        defaults.set(0.06, forKey: "runtime.settings.\(profileID.uuidString).bargeInRmsThreshold")
        defaults.set(0.09, forKey: "runtime.settings.\(profileID.uuidString).bargeInWindowDuration")
        defaults.set(5, forKey: "runtime.settings.\(profileID.uuidString).bargeInConsecutiveWindows")

        let store = RuntimeSettingsStore(defaults: defaults)
        let migratedSettings = store.load(profileID: profileID)
        let globalSettings = store.load(profileID: secondID)

        XCTAssertEqual(migratedSettings.intermediaryMode, .deterministic)
        XCTAssertEqual(migratedSettings.speechRmsThreshold, 0.05)
        XCTAssertEqual(migratedSettings.endSilenceSeconds, 2.5)
        XCTAssertEqual(migratedSettings.minTurnSeconds, 1.2)
        XCTAssertEqual(migratedSettings.maxTurnSeconds, 120.0)
        XCTAssertEqual(migratedSettings.bargeInRmsThreshold, 0.06)
        XCTAssertEqual(migratedSettings.bargeInWindowDuration, 0.09)
        XCTAssertEqual(migratedSettings.bargeInConsecutiveWindows, 5)
        XCTAssertEqual(globalSettings, migratedSettings)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "HermesWhisper02Tests.RuntimeSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
