import XCTest
@testable import HermesWhisper02

final class ConversationStoreTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        tempDirectoryURL = nil
    }

    func testUpsertAndListSessions() throws {
        let store = try makeStore()

        let first = try store.upsertSession(
            id: "session-1",
            hermesConversationID: "hermes-1",
            title: "First"
        )
        let second = try store.upsertSession(
            id: "session-2",
            hermesConversationID: "hermes-2",
            title: "Second"
        )
        try store.updateSessionPreview(
            sessionID: first.id,
            preview: "older",
            lastUpdated: Date(timeIntervalSince1970: 100)
        )
        try store.updateSessionPreview(
            sessionID: second.id,
            preview: "newer",
            lastUpdated: Date(timeIntervalSince1970: 200)
        )

        let sessions = try store.listSessions()

        XCTAssertEqual(sessions.map(\.id), ["session-2", "session-1"])
        XCTAssertEqual(sessions.first?.lastMessagePreview, "newer")
    }

    func testMessageOrdering() throws {
        let store = try makeStore()
        try store.upsertSession(id: "session-1", hermesConversationID: "hermes-1", title: nil)

        try store.appendMessage(
            sessionID: "session-1",
            turnID: "turn-1",
            role: .user,
            text: "hello",
            final: true,
            metadata: "{}"
        )
        try store.appendMessage(
            sessionID: "session-1",
            turnID: "turn-1",
            role: .assistant,
            text: "hi",
            final: true,
            metadata: "{}"
        )

        let messages = try store.loadMessages(sessionID: "session-1")
        let sessions = try store.listSessions()

        XCTAssertEqual(messages.map(\.text), ["hello", "hi"])
        XCTAssertEqual(sessions.first?.messageCount, 2)
        XCTAssertEqual(sessions.first?.lastMessagePreview, "hi")
    }

    func testPerServerFileIsolation() throws {
        let firstID = UUID()
        let secondID = UUID()
        let firstStore = try makeStore(profileID: firstID)
        let secondStore = try makeStore(profileID: secondID)

        try firstStore.upsertSession(id: "session-1", hermesConversationID: "hermes-1", title: nil)

        XCTAssertEqual(try firstStore.listSessions().map(\.id), ["session-1"])
        XCTAssertEqual(try secondStore.listSessions(), [])
        XCTAssertNotEqual(firstStore.databaseURL, secondStore.databaseURL)
    }

    func testUpsertIsIdempotent() throws {
        let store = try makeStore()

        try store.upsertSession(id: "session-1", hermesConversationID: "hermes-1", title: "Old")
        let updated = try store.upsertSession(
            id: "session-1",
            hermesConversationID: "hermes-2",
            title: "New"
        )
        let sessions = try store.listSessions()

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(updated.hermesConversationID, "hermes-2")
        XCTAssertEqual(updated.title, "New")
    }

    func testDeleteRemovesSessionAndMessages() throws {
        let store = try makeStore()
        try store.upsertSession(id: "session-1", hermesConversationID: "hermes-1", title: nil)
        try store.appendMessage(
            sessionID: "session-1",
            turnID: "turn-1",
            role: .user,
            text: "hello",
            final: true,
            metadata: "{}"
        )

        try store.deleteSession(sessionID: "session-1")

        XCTAssertEqual(try store.listSessions(), [])
        XCTAssertEqual(try store.loadMessages(sessionID: "session-1"), [])
    }

    func testChangeTokenUpdatesAfterTurnCommitWrites() throws {
        let store = try makeStore()
        try store.upsertSession(id: "session-1", hermesConversationID: "hermes-1", title: nil)
        let previousToken = store.changeToken

        try store.appendMessage(
            sessionID: "session-1",
            turnID: "turn-1",
            role: .assistant,
            text: "hi",
            final: true,
            metadata: "{}"
        )

        XCTAssertNotEqual(store.changeToken, previousToken)
    }

    private func makeStore(profileID: UUID = UUID()) throws -> ConversationStore {
        try ConversationStore(
            serverProfileID: profileID,
            applicationSupportURL: tempDirectoryURL
        )
    }
}
