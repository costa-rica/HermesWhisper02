import Foundation
import Network
import XCTest
@testable import HermesWhisper02

final class VoiceSocketIntegrationTests: XCTestCase {
    func testConnectSendsHelloAndUplinksBinaryAudio() async throws {
        let server = try TestWebSocketServer()
        try await server.start()
        defer {
            server.stop()
        }

        let profile = ServerProfile(
            id: UUID(),
            displayName: "local",
            baseURL: try XCTUnwrap(server.baseURL),
            notes: nil,
            authKind: .bearer2FA
        )
        let keychain = KeychainStore(keychain: VoiceSocketTestKeychainAccess())
        try keychain.save(
            profileID: profile.id,
            credentials: Credentials(
                token: "token",
                expiresAt: Date(timeIntervalSinceNow: 600),
                email: "nrodrig1@gmail.com"
            )
        )
        let socket = VoiceSocket(
            profile: profile,
            keychain: keychain,
            priorSessionID: "previous-session"
        )

        try await socket.connect()
        let hello = try await server.nextMessage()

        guard case .text(let helloPayload) = hello else {
            return XCTFail("Expected client hello text frame")
        }
        XCTAssertTrue(helloPayload.contains("\"type\":\"client_hello\""))
        XCTAssertTrue(helloPayload.contains("\"session_id\":\"previous-session\""))

        try await server.sendText(
            """
            {"type":"session_started","session_id":"new-session","conversation_id":"conversation","downlink_format":"pcm16","sample_rate":24000,"front_llm":"openai:gpt-4o-mini","resumed":true}
            """
        )

        let event = try await socket.events.nextEvent()
        XCTAssertEqual(
            event,
            .json(.sessionStarted(SessionStartedFrame(
                sessionID: "new-session",
                conversationID: "conversation",
                downlinkFormat: .pcm16,
                sampleRate: 24_000,
                frontLLM: "openai:gpt-4o-mini",
                resumed: true
            )))
        )

        try await socket.sendBinary(Data([0, 1, 2, 3]))
        let binary = try await server.nextMessage()
        XCTAssertEqual(binary, .binary(Data([0, 1, 2, 3])))

        socket.close()
    }
}

private enum TestWebSocketMessage: Equatable {
    case text(String)
    case binary(Data)
}

private final class TestWebSocketServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.dashanddata.hw02.tests.websocket")
    private let listener: NWListener
    private var connection: NWConnection?
    private var messageContinuations: [CheckedContinuation<TestWebSocketMessage, Error>] = []
    private var pendingMessages: [TestWebSocketMessage] = []
    private var startContinuation: CheckedContinuation<Void, Error>?

    var baseURL: URL? {
        guard let port = listener.port else {
            return nil
        }
        return URL(string: "http://127.0.0.1:\(port.rawValue)")
    }

    init() throws {
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        listener = try NWListener(using: parameters, on: .any)
    }

    func start() async throws {
        listener.newConnectionHandler = { [weak self] connection in
            self?.connection = connection
            connection.start(queue: self?.queue ?? .main)
            self?.receive(on: connection)
        }
        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.startContinuation?.resume()
                    self?.startContinuation = nil
                case .failed(let error):
                    self?.startContinuation?.resume(throwing: error)
                    self?.startContinuation = nil
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        connection?.cancel()
        listener.cancel()
    }

    func nextMessage() async throws -> TestWebSocketMessage {
        try await withThrowingTaskGroup(of: TestWebSocketMessage.self) { group in
            group.addTask {
                try await self.nextQueuedMessage()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                throw VoiceSocket.SocketError.disconnected
            }

            let message = try await group.next()!
            group.cancelAll()
            return message
        }
    }

    func sendText(_ text: String) async throws {
        try await send(Data(text.utf8), opcode: .text)
    }

    private func send(_ data: Data, opcode: NWProtocolWebSocket.Opcode) async throws {
        guard let connection else {
            throw VoiceSocket.SocketError.disconnected
        }

        let metadata = NWProtocolWebSocket.Metadata(opcode: opcode)
        let context = NWConnection.ContentContext(identifier: "websocket", metadata: [metadata])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func nextQueuedMessage() async throws -> TestWebSocketMessage {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if !self.pendingMessages.isEmpty {
                    continuation.resume(returning: self.pendingMessages.removeFirst())
                } else {
                    self.messageContinuations.append(continuation)
                }
            }
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else {
                return
            }
            if error == nil,
               let data,
               let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                let message: TestWebSocketMessage?
                switch metadata.opcode {
                case .text:
                    message = String(data: data, encoding: .utf8).map(TestWebSocketMessage.text)
                case .binary:
                    message = .binary(data)
                default:
                    message = nil
                }
                if let message {
                    self.queue.async {
                        if !self.messageContinuations.isEmpty {
                            self.messageContinuations.removeFirst().resume(returning: message)
                        } else {
                            self.pendingMessages.append(message)
                        }
                    }
                }
            }

            if error == nil {
                self.receive(on: connection)
            }
        }
    }
}

private extension AsyncStream where Element == VoiceSocket.VoiceEvent {
    func nextEvent() async throws -> VoiceSocket.VoiceEvent {
        try await withThrowingTaskGroup(of: VoiceSocket.VoiceEvent.self) { group in
            group.addTask {
                var iterator = makeAsyncIterator()
                guard let event = await iterator.next() else {
                    throw VoiceSocket.SocketError.disconnected
                }
                return event
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                throw VoiceSocket.SocketError.disconnected
            }

            let event = try await group.next()!
            group.cancelAll()
            return event
        }
    }
}

private final class VoiceSocketTestKeychainAccess: KeychainAccessing {
    private var values: [String: Data] = [:]

    func save(data: Data, service: String, account: String) throws {
        values[key(service: service, account: account)] = data
    }

    func load(service: String, account: String) throws -> Data? {
        values[key(service: service, account: account)]
    }

    func delete(service: String, account: String) throws {
        values[key(service: service, account: account)] = nil
    }

    private func key(service: String, account: String) -> String {
        "\(service):\(account)"
    }
}
