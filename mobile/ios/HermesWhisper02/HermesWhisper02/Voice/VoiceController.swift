import Foundation

@MainActor
@Observable
final class VoiceController: VoiceDisconnecting {
    enum ControllerError: Error {
        case alreadyRunning
    }

    private struct PendingTurn {
        var userText: String?
        var assistantText: String?
    }

    private let keychain: KeychainStore
    private let audioCapture: AudioCapture
    private let audioPlayer: AudioPlayer
    private var conversationStore: ConversationStore?
    private var bargeInDetector = BargeInDetector()
    private var socket: VoiceSocket?
    private var audioTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var activityTurnID: String?
    private var activeConversationSessionID: String?
    private var pendingTurns: [String: PendingTurn] = [:]

    var isRunning = false
    var isConnecting = false
    var microphoneRMS = 0.0
    var assistantState: AssistantState = .idle
    var latestTranscript = ""
    var sessionID: String?
    var errorMessage: String?
    var statusMessage = ""
    var hermesActivity: [HermesActivityEvent] = []

    init(
        keychain: KeychainStore = KeychainStore(),
        audioCapture: AudioCapture = AudioCapture(),
        audioPlayer: AudioPlayer = AudioPlayer(),
        conversationStore: ConversationStore? = nil
    ) {
        self.keychain = keychain
        self.audioCapture = audioCapture
        self.audioPlayer = audioPlayer
        self.conversationStore = conversationStore
    }

    func setConversationStore(_ conversationStore: ConversationStore?) {
        self.conversationStore = conversationStore
        activeConversationSessionID = nil
        pendingTurns.removeAll()
    }

    func start(profile: ServerProfile, pttMode: Bool = false) async throws {
        try await startSession(
            profile: profile,
            resumeSessionID: sessionID,
            pttMode: pttMode
        )
    }

    func startSession(
        profile: ServerProfile,
        resumeSessionID: String? = nil,
        pttMode: Bool = false
    ) async throws {
        guard !isRunning, !isConnecting else {
            throw ControllerError.alreadyRunning
        }

        isConnecting = true
        errorMessage = nil
        statusMessage = ""
        hermesActivity = []
        activityTurnID = nil
        let socket = VoiceSocket(
            profile: profile,
            keychain: keychain,
            priorSessionID: resumeSessionID,
            pttMode: pttMode
        )

        do {
            let frames = audioCapture.frames()
            try await socket.connect()
            try audioCapture.start()
            self.socket = socket
            isRunning = true
            isConnecting = false

            audioTask = Task { [weak self] in
                for await frame in frames {
                    let rms = AudioCapture.rms(forPCM16Frame: frame)
                    let playbackActive = await self?.audioPlayer.isPlaying() ?? false
                    let shouldFlushPlayback = await MainActor.run {
                        guard let self else {
                            return false
                        }
                        var shouldFlush = false
                        self.microphoneRMS = rms
                        self.bargeInDetector.process(frame: frame, playbackActive: playbackActive) {
                            shouldFlush = true
                        }
                        return shouldFlush
                    }
                    if shouldFlushPlayback {
                        AppLog.voice.info("voice_barge_in_detected action=flush_playback")
                        await self?.audioPlayer.flushAndStop()
                    }

                    do {
                        try await socket.sendBinary(frame)
                    } catch {
                        await MainActor.run {
                            self?.handleFailure(error)
                        }
                        return
                    }
                }
            }

            eventTask = Task { [weak self] in
                for await event in socket.events {
                    await self?.handle(event)
                }
            }
        } catch {
            audioCapture.stop()
            socket.close()
            isConnecting = false
            isRunning = false
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func disconnect() {
        audioTask?.cancel()
        audioTask = nil
        eventTask?.cancel()
        eventTask = nil
        audioCapture.stop()
        Task {
            await audioPlayer.flushAndStop()
        }
        bargeInDetector.reset()
        socket?.close()
        socket = nil
        isRunning = false
        isConnecting = false
        microphoneRMS = 0
        assistantState = .idle
        hermesActivity = []
        activityTurnID = nil
        pendingTurns.removeAll()
    }

    private func handle(_ event: VoiceSocket.VoiceEvent) async {
        switch event {
        case .json(let frame):
            await handle(frame)
        case .binaryAudio(let prelude, let data):
            do {
                try await audioPlayer.enqueue(
                    format: prelude.format,
                    sampleRate: prelude.sampleRate,
                    pcm16: data
                )
                AppLog.voice.info(
                    """
                    voice_controller_playback_enqueued turn_id=\(prelude.turnID, privacy: .public) \
                    source=\(prelude.source.rawValue, privacy: .public) bytes=\(data.count, privacy: .public)
                    """
                )
            } catch {
                handleFailure(error)
            }
        case .closed(let error):
            if let error {
                handleFailure(error)
            } else {
                disconnect()
            }
        }
    }

    func handle(_ frame: ServerFrame) async {
        switch frame {
        case .sessionStarted(let started):
            let previousSessionID = sessionID
            sessionID = started.sessionID
            activeConversationSessionID = started.sessionID
            upsertSession(started)
            if previousSessionID != nil && !started.resumed {
                statusMessage = "Reconnected; previous turn lost."
            } else if started.resumed {
                statusMessage = ""
            }
            AppLog.voice.info(
                """
                voice_session_started session_id=\(started.sessionID, privacy: .public) \
                resumed=\(started.resumed, privacy: .public) sample_rate=\(started.sampleRate, privacy: .public)
                """
            )
        case .transcript(let transcript):
            latestTranscript = transcript.text
            if transcript.isFinal && activityTurnID != transcript.turnID {
                activityTurnID = transcript.turnID
                hermesActivity = []
            }
            if transcript.isFinal {
                updatePendingTurn(transcript.turnID) { pending in
                    pending.userText = transcript.text
                }
            }
        case .assistantText(let assistantText):
            guard assistantText.final else {
                break
            }
            updatePendingTurn(assistantText.turnID) { pending in
                pending.assistantText = assistantText.text
            }
        case .assistantState(let state):
            assistantState = state.state
        case .hermesProgress(let progress):
            if activityTurnID != progress.turnID {
                activityTurnID = progress.turnID
                hermesActivity = []
            }
            hermesActivity.append(HermesActivityEvent(frame: progress))
            statusMessage = "Hermes is working."
        case .userStartedSpeaking:
            AppLog.voice.info("voice_server_user_started_speaking action=flush_playback")
            await audioPlayer.flushAndStop()
        case .turnEnd(let turnEnd):
            if turnEnd.canceled == true {
                assistantState = .idle
                await audioPlayer.flushAndStop()
                // Canceled turns are dropped as a pair so local history mirrors completed exchanges only.
                pendingTurns[turnEnd.turnID] = nil
            } else {
                commitPendingTurn(turnEnd.turnID)
            }
        case .error(let envelope):
            errorMessage = envelope.error.message
            AppLog.voice.error("voice_server_error code=\(envelope.error.code, privacy: .public) message=\(envelope.error.message, privacy: .public)")
        default:
            break
        }
    }

    private func upsertSession(_ started: SessionStartedFrame) {
        do {
            try conversationStore?.upsertSession(
                id: started.sessionID,
                hermesConversationID: started.conversationID,
                title: nil
            )
        } catch {
            errorMessage = "Unable to save conversation session."
            AppLog.voice.error("voice_conversation_session_save_failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func updatePendingTurn(_ turnID: String, body: (inout PendingTurn) -> Void) {
        var pending = pendingTurns[turnID, default: PendingTurn()]
        body(&pending)
        pendingTurns[turnID] = pending
    }

    private func commitPendingTurn(_ turnID: String) {
        guard let sessionID = activeConversationSessionID,
              let pending = pendingTurns.removeValue(forKey: turnID) else {
            return
        }

        do {
            if let userText = pending.userText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !userText.isEmpty {
                try conversationStore?.appendMessage(
                    sessionID: sessionID,
                    turnID: turnID,
                    role: .user,
                    text: userText,
                    final: true,
                    metadata: "{}"
                )
            }

            if let assistantText = pending.assistantText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !assistantText.isEmpty {
                try conversationStore?.appendMessage(
                    sessionID: sessionID,
                    turnID: turnID,
                    role: .assistant,
                    text: assistantText,
                    final: true,
                    metadata: "{}"
                )
            }
        } catch {
            errorMessage = "Unable to save conversation turn."
            AppLog.voice.error("voice_conversation_turn_save_failed turn_id=\(turnID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleFailure(_ error: Error) {
        errorMessage = error.localizedDescription
        AppLog.voice.error("voice_controller_failed error=\(error.localizedDescription, privacy: .public)")
        disconnect()
    }
}

struct HermesActivityEvent: Identifiable, Equatable {
    let id = UUID()
    let turnID: String
    let kind: HermesProgressKind
    let text: String
    let ts: Double

    init(frame: HermesProgressFrame) {
        turnID = frame.turnID
        kind = frame.kind
        text = frame.text
        ts = frame.ts
    }
}

@MainActor
protocol VoiceDisconnecting: AnyObject {
    func disconnect()
}
