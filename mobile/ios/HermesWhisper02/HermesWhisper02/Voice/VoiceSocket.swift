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
    private static let reconnectDelaysNanoseconds: [UInt64] = [
        200_000_000,
        500_000_000,
        1_000_000_000
    ]

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
    private var currentSessionID: String?
    private var isReconnecting = false
    private var didCloseIntentionally = false

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
        didCloseIntentionally = false
        try await openWebSocket(sessionID: priorSessionID)
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func openWebSocket(sessionID: String?) async throws {
        let credentials = try keychain.loadValid(profileID: profile.id)
        guard let token = credentials?.token else {
            throw SocketError.missingValidCredentials
        }

        var request = URLRequest(url: try voiceURL())
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        webSocketTask = task
        task.resume()

        processor.reset()
        pendingPingTimestamp = nil
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            await self?.heartbeatLoop()
        }

        try await sendJSON(.clientHello(ClientHelloFrame(sessionID: sessionID, pttMode: pttMode)))
    }

    func sendJSON(_ frame: ClientFrame) async throws {
        guard let webSocketTask else {
            throw SocketError.disconnected
        }
        let payload = try ProtocolEnvelope.encode(frame)
        try await webSocketTask.send(.string(payload))
    }

    func sendBinary(_ data: Data) async throws {
        try await waitUntilConnected()
        do {
            try await sendBinaryOnce(data)
        } catch {
            if didCloseIntentionally {
                throw error
            }
            if isReconnecting {
                try await waitUntilConnected()
                try await retryBinaryAfterReconnect(data)
                return
            }
            if await reconnectAfterFailure(error) {
                try await retryBinaryAfterReconnect(data)
                return
            }
            throw error
        }
    }

    private func sendBinaryOnce(_ data: Data) async throws {
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

    private func retryBinaryAfterReconnect(_ data: Data) async throws {
        do {
            try await sendBinaryOnce(data)
        } catch {
            if didCloseIntentionally || webSocketTask == nil {
                throw error
            }
            AppLog.voice.warning(
                "voice_socket_binary_retry_dropped bytes=\(data.count, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func close() {
        didCloseIntentionally = true
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
            if didCloseIntentionally || Task.isCancelled {
                return
            }
            if await reconnectAfterFailure(error) {
                await receiveLoop()
                return
            }
            AppLog.voice.error("voice_socket_receive_failed error=\(error.localizedDescription, privacy: .public)")
            eventContinuation.yield(.closed(error))
            eventContinuation.finish()
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) throws {
        switch message {
        case .string(let text):
            let frame = try ProtocolEnvelope.decodeServerFrame(from: text)
            if case .sessionStarted(let started) = frame {
                currentSessionID = started.sessionID
            }
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
                if didCloseIntentionally {
                    return
                }
                AppLog.voice.error("voice_socket_heartbeat_failed error=\(error.localizedDescription, privacy: .public)")
                webSocketTask?.cancel(with: .goingAway, reason: nil)
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

    private func reconnectAfterFailure(_ error: Error) async -> Bool {
        guard !didCloseIntentionally else {
            return false
        }
        if isReconnecting {
            return await waitForReconnectCompletion()
        }

        isReconnecting = true
        defer {
            isReconnecting = false
        }

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil

        for (attemptIndex, delay) in Self.reconnectDelaysNanoseconds.enumerated() {
            if didCloseIntentionally || Task.isCancelled {
                return false
            }

            try? await Task.sleep(nanoseconds: delay)
            do {
                try await openWebSocket(sessionID: currentSessionID)
                AppLog.voice.info(
                    """
                    voice_socket_reconnected attempt=\(attemptIndex + 1, privacy: .public) \
                    session_id=\(self.currentSessionID ?? "none", privacy: .public)
                    """
                )
                return true
            } catch {
                AppLog.voice.error(
                    """
                    voice_socket_reconnect_failed attempt=\(attemptIndex + 1, privacy: .public) \
                    error=\(error.localizedDescription, privacy: .public)
                    """
                )
            }
        }

        AppLog.voice.error("voice_socket_reconnect_exhausted error=\(error.localizedDescription, privacy: .public)")
        return false
    }

    private func waitForReconnectCompletion() async -> Bool {
        var attempts = 0
        while isReconnecting && attempts < 100 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }
        return !isReconnecting && webSocketTask != nil
    }

    private func waitUntilConnected() async throws {
        var attempts = 0
        while isReconnecting && attempts < 20 {
            try await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }
        if isReconnecting || webSocketTask == nil {
            throw SocketError.disconnected
        }
    }
}

struct VoiceSocketMessageProcessor {
    private var pendingPrelude: AudioChunkPrelude?
    private var nextSequenceBySource: [AudioSource: Int] = [:]

    mutating func reset() {
        pendingPrelude = nil
        nextSequenceBySource = [:]
    }

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
