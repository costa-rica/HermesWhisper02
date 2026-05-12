import SwiftUI

struct VoiceView: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var voiceController = VoiceController()
    @State private var voiceTask: Task<Void, Never>?
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
                ProgressView(value: min(voiceController.microphoneRMS * 3, 1))
                    .frame(maxWidth: 220)
                Text(voiceController.microphoneRMS, format: .number.precision(.fractionLength(3)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                Text(voiceController.assistantState.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !voiceController.latestTranscript.isEmpty {
                    Text(voiceController.latestTranscript)
                        .font(.body)
                        .multilineTextAlignment(.center)
                }
            }
            Button {
                toggleAudioCapture()
            } label: {
                Label(
                    voiceController.isRunning ? "Stop voice" : "Start voice",
                    systemImage: voiceController.isRunning ? "mic.slash" : "mic"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(voiceController.isConnecting)
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
        if voiceController.isRunning || voiceController.isConnecting {
            stopAudioCapture()
        } else {
            startAudioCapture()
        }
    }

    private func startAudioCapture() {
        voiceTask = Task {
            do {
                try await voiceController.start(profile: appEnvironment.activeProfile)
            } catch {
                await MainActor.run {
                    audioError = error.localizedDescription
                }
            }
        }
    }

    private func stopAudioCapture() {
        voiceTask?.cancel()
        voiceTask = nil
        voiceController.disconnect()
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
