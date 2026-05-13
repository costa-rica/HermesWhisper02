import Foundation
import XCTest
@testable import HermesWhisper02

@MainActor
final class VoiceControllerPersistenceTests: XCTestCase {
    func testCompletedTurnPersistsUserAndAssistantMessages() async throws {
        let store = try makeStore()
        let controller = VoiceController(conversationStore: store)

        await controller.handle(.sessionStarted(SessionStartedFrame(
            sessionID: "session-1",
            conversationID: "hermes-1",
            downlinkFormat: .pcm16,
            sampleRate: 24_000,
            frontLLM: "deterministic",
            resumed: false,
            created: true
        )))
        await controller.handle(.transcript(TranscriptFrame(
            turnID: "turn-1",
            text: "Tell me a story.",
            isFinal: true
        )))
        await controller.handle(.assistantText(AssistantTextFrame(
            turnID: "turn-1",
            text: "Once upon a time, Hermes answered clearly.",
            final: true,
            ts: 1
        )))
        await controller.handle(.turnEnd(TurnEndFrame(turnID: "turn-1", canceled: false)))

        let sessions = try store.listSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, "session-1")
        XCTAssertEqual(sessions.first?.hermesConversationID, "hermes-1")
        XCTAssertEqual(sessions.first?.messageCount, 2)
        XCTAssertEqual(sessions.first?.lastMessagePreview, "Once upon a time, Hermes answered clearly.")

        let messages = try store.loadMessages(sessionID: "session-1")
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(messages.map(\.text), [
            "Tell me a story.",
            "Once upon a time, Hermes answered clearly."
        ])
        XCTAssertEqual(messages.map(\.turnID), ["turn-1", "turn-1"])
        XCTAssertEqual(controller.transcriptMessages, messages)
        XCTAssertNil(controller.liveTranscript)
    }

    func testCanceledTurnDoesNotPersistAssistantMessage() async throws {
        let store = try makeStore()
        let controller = VoiceController(conversationStore: store)

        await controller.handle(.sessionStarted(SessionStartedFrame(
            sessionID: "session-1",
            conversationID: "hermes-1",
            downlinkFormat: .pcm16,
            sampleRate: 24_000,
            frontLLM: "deterministic",
            resumed: false
        )))
        await controller.handle(.transcript(TranscriptFrame(
            turnID: "turn-1",
            text: "Tell me a story.",
            isFinal: true
        )))
        await controller.handle(.assistantText(AssistantTextFrame(
            turnID: "turn-1",
            text: "This should not persist.",
            final: true,
            ts: 1
        )))
        await controller.handle(.turnEnd(TurnEndFrame(turnID: "turn-1", canceled: true)))

        XCTAssertEqual(try store.loadMessages(sessionID: "session-1"), [])
        XCTAssertEqual(try store.listSessions().first?.messageCount, 0)
    }

    private func makeStore() throws -> ConversationStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HermesWhisper02Tests-\(UUID().uuidString)", isDirectory: true)
        return try ConversationStore(
            serverProfileID: UUID(),
            applicationSupportURL: root
        )
    }
}
