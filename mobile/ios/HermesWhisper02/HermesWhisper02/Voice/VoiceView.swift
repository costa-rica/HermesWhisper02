import SwiftUI

struct VoiceView: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var audioCapture = AudioCapture()
    @State private var audioTask: Task<Void, Never>?
    @State private var isCapturingAudio = false
    @State private var microphoneRMS = 0.0
    @State private var audioError: String?
    @State private var logoutError: String?
    @State private var showingServers = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Hello, HermesWhisper02")
                .font(.title2)
            Text(appEnvironment.activeServerName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text("Mic RMS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: min(microphoneRMS * 8, 1))
                    .frame(maxWidth: 220)
                Text(microphoneRMS, format: .number.precision(.fractionLength(3)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button {
                toggleAudioCapture()
            } label: {
                Label(
                    isCapturingAudio ? "Stop mic" : "Start mic",
                    systemImage: isCapturingAudio ? "mic.slash" : "mic"
                )
            }
            .buttonStyle(.borderedProminent)
            Button("Log out", role: .destructive) {
                logout()
            }
            .buttonStyle(.bordered)
            Button {
                showingServers = true
            } label: {
                Label("Servers", systemImage: "server.rack")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .sheet(isPresented: $showingServers) {
            NavigationStack {
                ServerRegistryView()
            }
        }
        .alert("Logout failed", isPresented: logoutFailed) {
            Button("OK", role: .cancel) {
                logoutError = nil
            }
        } message: {
            Text(logoutError ?? "Unable to clear stored credentials.")
        }
        .alert("Microphone unavailable", isPresented: audioFailed) {
            Button("OK", role: .cancel) {
                audioError = nil
            }
        } message: {
            Text(audioError ?? "Unable to start audio capture.")
        }
        .onDisappear {
            stopAudioCapture()
        }
    }

    private var logoutFailed: Binding<Bool> {
        Binding(
            get: { logoutError != nil },
            set: { isPresented in
                if !isPresented {
                    logoutError = nil
                }
            }
        )
    }

    private var audioFailed: Binding<Bool> {
        Binding(
            get: { audioError != nil },
            set: { isPresented in
                if !isPresented {
                    audioError = nil
                }
            }
        )
    }

    private func toggleAudioCapture() {
        if isCapturingAudio {
            stopAudioCapture()
        } else {
            startAudioCapture()
        }
    }

    private func startAudioCapture() {
        let frames = audioCapture.frames()

        do {
            try audioCapture.start()
            isCapturingAudio = true
            audioTask = Task {
                for await frame in frames {
                    let rms = AudioCapture.rms(forPCM16Frame: frame)
                    await MainActor.run {
                        microphoneRMS = rms
                    }
                }
            }
        } catch {
            audioCapture.stop()
            audioError = error.localizedDescription
            isCapturingAudio = false
            microphoneRMS = 0
        }
    }

    private func stopAudioCapture() {
        audioTask?.cancel()
        audioTask = nil
        audioCapture.stop()
        isCapturingAudio = false
        microphoneRMS = 0
    }

    private func logout() {
        stopAudioCapture()
        do {
            try appEnvironment.logout()
        } catch {
            logoutError = error.localizedDescription
        }
    }
}

#Preview {
    VoiceView()
        .environment(AppEnvironment())
}
