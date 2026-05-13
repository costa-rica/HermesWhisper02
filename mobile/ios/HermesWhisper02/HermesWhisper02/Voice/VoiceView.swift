import SwiftUI

struct VoiceView: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var voiceController = VoiceController()
    private let interactionModeStore = VoiceInteractionModeStore()
    @State private var voiceTask: Task<Void, Never>?
    @State private var audioError: String?
    @State private var logoutError: String?
    @State private var showingServers = false
    @State private var interactionMode: VoiceInteractionMode = .continuous
    @State private var isPressingPTT = false

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
                if !voiceController.statusMessage.isEmpty {
                    Text(voiceController.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if !voiceController.latestTranscript.isEmpty {
                    Text(voiceController.latestTranscript)
                        .font(.body)
                        .multilineTextAlignment(.center)
                }
            }
            HermesActivityView(events: voiceController.hermesActivity)
                .frame(maxWidth: 340)
            Picker("Mode", selection: $interactionMode) {
                ForEach(VoiceInteractionMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            .onChange(of: interactionMode) { _, newMode in
                interactionModeStore.save(newMode, profileID: appEnvironment.activeProfile.id)
                stopAudioCapture()
            }
            if interactionMode == .continuous {
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
            } else {
                Label(
                    isPressingPTT ? "Release to stop" : "Hold to talk",
                    systemImage: isPressingPTT ? "mic.fill" : "mic"
                )
                .frame(minWidth: 160)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .foregroundStyle(.white)
                .background(isPressingPTT ? Color.red : Color.accentColor)
                .clipShape(Capsule())
                .opacity(voiceController.isConnecting ? 0.6 : 1)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            startPushToTalkIfNeeded()
                        }
                        .onEnded { _ in
                            stopPushToTalk()
                        }
                )
            }
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
        .onAppear {
            interactionMode = interactionModeStore.load(profileID: appEnvironment.activeProfile.id)
        }
        .onChange(of: appEnvironment.activeProfile.id) { _, profileID in
            interactionMode = interactionModeStore.load(profileID: profileID)
        }
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
                try await voiceController.start(
                    profile: appEnvironment.activeProfile,
                    pttMode: interactionMode.pttMode
                )
            } catch {
                await MainActor.run {
                    audioError = error.localizedDescription
                    isPressingPTT = false
                }
            }
        }
    }

    private func stopAudioCapture() {
        voiceTask?.cancel()
        voiceTask = nil
        voiceController.disconnect()
    }

    private func startPushToTalkIfNeeded() {
        guard !isPressingPTT, !voiceController.isRunning, !voiceController.isConnecting else {
            return
        }
        isPressingPTT = true
        startAudioCapture()
    }

    private func stopPushToTalk() {
        guard isPressingPTT else {
            return
        }
        isPressingPTT = false
        stopAudioCapture()
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

private struct HermesActivityView: View {
    let events: [HermesActivityEvent]
    @State private var showingActivityLog = false

    private var compactEvents: [HermesActivityEvent] {
        Array(events.suffix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: events.isEmpty ? "hourglass" : "checklist")
                Text(events.isEmpty ? "Hermes activity" : "Hermes working")
                Spacer()
                if !events.isEmpty {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if events.isEmpty {
                Text("No Hermes activity yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(compactEvents) { event in
                                HermesActivityRow(event: event, lineLimit: 2)
                                    .id(event.id)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                    .onChange(of: events.count) { _, _ in
                        if let lastID = events.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if !events.isEmpty {
                showingActivityLog = true
            }
        }
        .sheet(isPresented: $showingActivityLog) {
            HermesActivityLogView(events: events)
        }
    }
}

private struct HermesActivityRow: View {
    let event: HermesActivityEvent
    var lineLimit: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName)
                .frame(width: 18)
            Text(event.text)
                .font(.caption)
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.primary)
    }

    private var iconName: String {
        switch event.kind {
        case .sentToHermes:
            "paperplane"
        case .responseStarted:
            "hourglass"
        case .toolCall:
            "wrench.and.screwdriver"
        case .toolResult:
            "checkmark.circle"
        case .preparingAudio:
            "waveform"
        case .audioReady:
            "speaker.wave.2"
        case .finished:
            "flag.checkered"
        case .failed:
            "exclamationmark.triangle"
        }
    }
}

private struct HermesActivityLogView: View {
    let events: [HermesActivityEvent]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(events) { event in
                            HermesActivityRow(event: event, lineLimit: nil)
                                .id(event.id)
                                .padding(.vertical, 2)
                        }
                    }
                    .padding()
                }
                .onAppear {
                    if let lastID = events.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .navigationTitle("Hermes activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    VoiceView()
        .environment(AppEnvironment())
}
