import XCTest
@testable import HermesWhisper02

final class VoiceInteractionModeStoreTests: XCTestCase {
    func testDefaultsToContinuous() {
        let store = VoiceInteractionModeStore(defaults: makeDefaults())

        XCTAssertEqual(store.load(profileID: UUID()), .continuous)
    }

    func testPersistsModePerProfile() {
        let defaults = makeDefaults()
        let store = VoiceInteractionModeStore(defaults: defaults)
        let first = UUID()
        let second = UUID()

        store.save(.pushToTalk, profileID: first)

        XCTAssertEqual(store.load(profileID: first), .pushToTalk)
        XCTAssertEqual(store.load(profileID: second), .continuous)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "VoiceInteractionModeStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
