import Foundation

@MainActor
@Observable
final class VoiceController: VoiceDisconnecting {
    enum ControllerError: Error {
        case alreadyRunning
    }

    private let keychain: KeychainStore
    private let audioCapture: AudioCapture
    private var socket: VoiceSocket?
    private var audioTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?

    var isRunning = false
    var isConnecting = false
    var microphoneRMS = 0.0
    var assistantState: AssistantState = .idle
    var latestTranscript = ""
    var sessionID: String?
    var errorMessage: String?

    init(
        keychain: KeychainStore = KeychainStore(),
        audioCapture: AudioCapture = AudioCapture()
    ) {
        self.keychain = keychain
        self.audioCapture = audioCapture
    }

    func start(profile: ServerProfile, pttMode: Bool = false) async throws {
        guard !isRunning, !isConnecting else {
            throw ControllerError.alreadyRunning
        }

        isConnecting = true
        errorMessage = nil
        let socket = VoiceSocket(
            profile: profile,
            keychain: keychain,
            priorSessionID: sessionID,
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
                    await MainActor.run {
                        self?.microphoneRMS = rms
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
                    await MainActor.run {
                        self?.handle(event)
                    }
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
        socket?.close()
        socket = nil
        isRunning = false
        isConnecting = false
        microphoneRMS = 0
        assistantState = .idle
    }

    private func handle(_ event: VoiceSocket.VoiceEvent) {
        switch event {
        case .json(let frame):
            handle(frame)
        case .binaryAudio(let prelude, let data):
            AppLog.voice.info(
                """
                voice_controller_playback_deferred turn_id=\(prelude.turnID, privacy: .public) \
                source=\(prelude.source.rawValue, privacy: .public) bytes=\(data.count, privacy: .public)
                """
            )
        case .closed(let error):
            if let error {
                handleFailure(error)
            } else {
                disconnect()
            }
        }
    }

    private func handle(_ frame: ServerFrame) {
        switch frame {
        case .sessionStarted(let started):
            sessionID = started.sessionID
            AppLog.voice.info(
                """
                voice_session_started session_id=\(started.sessionID, privacy: .public) \
                resumed=\(started.resumed, privacy: .public) sample_rate=\(started.sampleRate, privacy: .public)
                """
            )
        case .transcript(let transcript):
            latestTranscript = transcript.text
        case .assistantState(let state):
            assistantState = state.state
        case .turnEnd(let turnEnd):
            if turnEnd.canceled == true {
                assistantState = .idle
            }
        case .error(let envelope):
            errorMessage = envelope.error.message
            AppLog.voice.error("voice_server_error code=\(envelope.error.code, privacy: .public) message=\(envelope.error.message, privacy: .public)")
        default:
            break
        }
    }

    private func handleFailure(_ error: Error) {
        errorMessage = error.localizedDescription
        AppLog.voice.error("voice_controller_failed error=\(error.localizedDescription, privacy: .public)")
        disconnect()
    }
}

@MainActor
protocol VoiceDisconnecting: AnyObject {
    func disconnect()
}
