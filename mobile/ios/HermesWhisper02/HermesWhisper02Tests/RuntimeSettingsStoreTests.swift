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

    func testPersistsSettingsPerProfile() {
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
        XCTAssertEqual(reloadedSettings.intermediaryMode, .deterministic)
        XCTAssertEqual(reloadedSettings.speechRmsThreshold, 0.01)
        XCTAssertEqual(reloadedSettings.endSilenceSeconds, 2.0)
        XCTAssertEqual(reloadedSettings.minTurnSeconds, 1.0)
        XCTAssertEqual(reloadedSettings.maxTurnSeconds, 180.0)
        XCTAssertEqual(reloadedSettings.bargeInRmsThreshold, 0.04)
        XCTAssertEqual(reloadedSettings.bargeInWindowDuration, 0.08)
        XCTAssertEqual(reloadedSettings.bargeInConsecutiveWindows, 4)
        XCTAssertEqual(reloadedStore.load(profileID: secondID).intermediaryMode, .llm)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "HermesWhisper02Tests.RuntimeSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
