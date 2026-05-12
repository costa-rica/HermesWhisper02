import Foundation

final class VoiceSocket {
    enum SocketError: Error, Equatable {
        case missingValidCredentials
        case invalidBaseURL
        case disconnected
        case unexpectedMessage
        case heartbeatTimedOut
    }

    enum VoiceEvent: Equatable {
        case json(ServerFrame)
        case binaryAudio(AudioChunkPrelude, Data)
        case closed(Error?)

        static func == (lhs: VoiceEvent, rhs: VoiceEvent) -> Bool {
            switch (lhs, rhs) {
            case (.json(let lhsFrame), .json(let rhsFrame)):
                return lhsFrame == rhsFrame
            case (.binaryAudio(let lhsPrelude, let lhsData), .binaryAudio(let rhsPrelude, let rhsData)):
                return lhsPrelude == rhsPrelude && lhsData == rhsData
            case (.closed(nil), .closed(nil)):
                return true
            case (.closed, .closed):
                return false
            default:
                return false
            }
        }
    }

    private static let heartbeatIntervalNanoseconds: UInt64 = 15_000_000_000
    private static let heartbeatTimeoutNanoseconds: UInt64 = 5_000_000_000

    private let profile: ServerProfile
    private let keychain: KeychainStore
    private let session: URLSession
    private let pttMode: Bool
    private let priorSessionID: String?

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var processor = VoiceSocketMessageProcessor()
    private var pendingPingTimestamp: Double?
    private var sendQueueDepth = 0

    private let eventStream: AsyncStream<VoiceEvent>
    private let eventContinuation: AsyncStream<VoiceEvent>.Continuation

    var events: AsyncStream<VoiceEvent> {
        eventStream
    }

    init(
        profile: ServerProfile,
        keychain: KeychainStore = KeychainStore(),
        session: URLSession = .shared,
        priorSessionID: String? = nil,
        pttMode: Bool = false
    ) {
        self.profile = profile
        self.keychain = keychain
        self.session = session
        self.priorSessionID = priorSessionID
        self.pttMode = pttMode

        var continuation: AsyncStream<VoiceEvent>.Continuation!
        self.eventStream = AsyncStream<VoiceEvent> { streamContinuation in
            continuation = streamContinuation
        }
        self.eventContinuation = continuation
    }

    deinit {
        close()
    }

    func connect() async throws {
        let credentials = try keychain.loadValid(profileID: profile.id)
        guard let token = credentials?.token else {
            throw SocketError.missingValidCredentials
        }

        var request = URLRequest(url: try voiceURL())
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        webSocketTask = task
        task.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
        heartbeatTask = Task { [weak self] in
            await self?.heartbeatLoop()
        }

        try await sendJSON(.clientHello(ClientHelloFrame(sessionID: priorSessionID, pttMode: pttMode)))
    }

    func sendJSON(_ frame: ClientFrame) async throws {
        guard let webSocketTask else {
            throw SocketError.disconnected
        }
        let payload = try ProtocolEnvelope.encode(frame)
        try await webSocketTask.send(.string(payload))
    }

    func sendBinary(_ data: Data) async throws {
        guard let webSocketTask else {
            throw SocketError.disconnected
        }

        sendQueueDepth += 1
        if sendQueueDepth > 8 {
            AppLog.voice.warning("voice_socket_send_backpressure depth=\(self.sendQueueDepth, privacy: .public)")
        }
        defer {
            sendQueueDepth -= 1
        }

        try await webSocketTask.send(.data(data))
    }

    func close() {
        receiveTask?.cancel()
        receiveTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        eventContinuation.yield(.closed(nil))
        eventContinuation.finish()
    }

    private func voiceURL() throws -> URL {
        var components = URLComponents(url: profile.baseURL, resolvingAgainstBaseURL: false)
        switch components?.scheme {
        case "https":
            components?.scheme = "wss"
        case "http":
            components?.scheme = "ws"
        default:
            throw SocketError.invalidBaseURL
        }
        components?.path = "/ws/voice"
        guard let url = components?.url else {
            throw SocketError.invalidBaseURL
        }
        return url
    }

    private func receiveLoop() async {
        do {
            while !Task.isCancelled {
                guard let webSocketTask else {
                    throw SocketError.disconnected
                }

                let message = try await webSocketTask.receive()
                try handle(message)
            }
        } catch {
            AppLog.voice.error("voice_socket_receive_failed error=\(error.localizedDescription, privacy: .public)")
            eventContinuation.yield(.closed(error))
            eventContinuation.finish()
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) throws {
        switch message {
        case .string(let text):
            let frame = try ProtocolEnvelope.decodeServerFrame(from: text)
            if case .pong(let pong) = frame {
                handlePong(pong)
            }
            if let event = try processor.handle(frame) {
                eventContinuation.yield(event)
            }
        case .data(let data):
            let event = try processor.handleBinary(data)
            AppLog.voice.info(
                """
                voice_socket_binary_audio turn_id=\(event.0.turnID, privacy: .public) \
                source=\(event.0.source.rawValue, privacy: .public) seq=\(event.0.seq, privacy: .public) bytes=\(data.count, privacy: .public)
                """
            )
            eventContinuation.yield(.binaryAudio(event.0, event.1))
        @unknown default:
            throw SocketError.unexpectedMessage
        }
    }

    private func heartbeatLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: Self.heartbeatIntervalNanoseconds)
            if Task.isCancelled {
                return
            }

            let timestamp = Date().timeIntervalSince1970
            pendingPingTimestamp = timestamp
            do {
                try await sendJSON(.ping(PingFrame(ts: timestamp)))
                try await Task.sleep(nanoseconds: Self.heartbeatTimeoutNanoseconds)
                if pendingPingTimestamp == timestamp {
                    throw SocketError.heartbeatTimedOut
                }
            } catch {
                AppLog.voice.error("voice_socket_heartbeat_failed error=\(error.localizedDescription, privacy: .public)")
                eventContinuation.yield(.closed(error))
                close()
                return
            }
        }
    }

    private func handlePong(_ pong: PongFrame) {
        guard pendingPingTimestamp == pong.ts else {
            return
        }
        pendingPingTimestamp = nil
    }
}

struct VoiceSocketMessageProcessor {
    private var pendingPrelude: AudioChunkPrelude?
    private var nextSequenceBySource: [AudioSource: Int] = [:]

    mutating func handle(_ frame: ServerFrame) throws -> VoiceSocket.VoiceEvent? {
        if case .audioChunk(let prelude) = frame {
            guard pendingPrelude == nil else {
                throw ProtocolError.pendingPreludeReplaced
            }

            let expected = nextSequenceBySource[prelude.source] ?? 0
            guard prelude.seq >= expected else {
                throw ProtocolError.duplicateOrOutOfOrderSequence(
                    turnID: prelude.turnID,
                    source: prelude.source,
                    expectedAtLeast: expected,
                    actual: prelude.seq
                )
            }
            nextSequenceBySource[prelude.source] = prelude.seq + 1
            pendingPrelude = prelude
            return nil
        }

        return .json(frame)
    }

    mutating func handleBinary(_ data: Data) throws -> (AudioChunkPrelude, Data) {
        guard let prelude = pendingPrelude else {
            throw ProtocolError.binaryWithoutPrelude
        }
        pendingPrelude = nil

        guard data.count == prelude.bytes else {
            throw ProtocolError.byteCountMismatch(expected: prelude.bytes, actual: data.count)
        }
        return (prelude, data)
    }
}
