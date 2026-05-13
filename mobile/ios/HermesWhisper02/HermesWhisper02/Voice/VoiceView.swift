import SwiftUI

struct VoiceView: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var voiceController = VoiceController()
    private let interactionModeStore = VoiceInteractionModeStore()
    private let runtimeSettingsStore = RuntimeSettingsStore()
    @State private var voiceTask: Task<Void, Never>?
    @State private var audioError: String?
    @State private var logoutError: String?
    @State private var showingServers = false
    @State private var showingHistory = false
    @State private var showingSettings = false
    @State private var interactionMode: VoiceInteractionMode = .continuous
    @State private var runtimeSettings = RuntimeSettings()
    @State private var isPressingPTT = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 12)

            statusBlock
                .padding(.horizontal, 18)
                .padding(.bottom, 10)

            Divider()

            ConversationTranscriptView(
                messages: voiceController.transcriptMessages,
                liveUserText: voiceController.liveTranscript
            )
        }
        .onAppear {
            voiceController.setConversationStore(appEnvironment.conversationStore)
            interactionMode = interactionModeStore.load(profileID: appEnvironment.activeProfile.id)
            runtimeSettings = runtimeSettingsStore.load(profileID: appEnvironment.activeProfile.id)
            voiceController.applyRuntimeSettings(runtimeSettings)
        }
        .onChange(of: appEnvironment.activeProfile.id) { _, profileID in
            voiceController.setConversationStore(appEnvironment.conversationStore)
            interactionMode = interactionModeStore.load(profileID: profileID)
            runtimeSettings = runtimeSettingsStore.load(profileID: profileID)
            voiceController.applyRuntimeSettings(runtimeSettings)
        }
        .sheet(isPresented: $showingServers) {
            NavigationStack {
                ServerRegistryView()
            }
        }
        .sheet(isPresented: $showingHistory) {
            NavigationStack {
                if let store = appEnvironment.conversationStore {
                    ConversationHistoryView(
                        store: store,
                        activeServerName: appEnvironment.activeServerName,
                        onResume: resumeConversation
                    )
                } else {
                    Text("History unavailable.")
                        .foregroundStyle(.secondary)
                        .navigationTitle("History")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView(
                    profileID: appEnvironment.activeProfile.id,
                    interactionMode: $interactionMode,
                    settingsStore: runtimeSettingsStore,
                    onSettingsChanged: { settings in
                        runtimeSettings = settings
                        voiceController.applyRuntimeSettings(settings)
                    },
                    onIntermediaryModeChanged: { mode in
                        Task {
                            await voiceController.sendIntermediaryMode(mode)
                        }
                    },
                    onAudioParamsChanged: { params in
                        Task {
                            await voiceController.sendAudioParams(params)
                        }
                    },
                    onBargeInChanged: { config in
                        voiceController.updateBargeInConfig(config)
                    },
                    onInteractionModeChanged: { mode in
                        interactionModeStore.save(mode, profileID: appEnvironment.activeProfile.id)
                        stopAudioCapture()
                    },
                    onLogout: logout
                )
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

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                showingHistory = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title3)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Conversation history")

            Button {
                showingServers = true
            } label: {
                Text(appEnvironment.activeServerName)
                    .font(.title2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Active server")

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    private var statusBlock: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mic RMS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: min(voiceController.microphoneRMS * 3, 1))
                    Text(voiceController.microphoneRMS, format: .number.precision(.fractionLength(3)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Assistant")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(voiceController.assistantState.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !voiceController.statusMessage.isEmpty {
                        Text(voiceController.statusMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            HermesActivityView(events: voiceController.hermesActivity)

            voiceControl
        }
    }

    @ViewBuilder
    private var voiceControl: some View {
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

    private func resumeConversation(sessionID: String) {
        showingHistory = false
        stopAudioCapture()
        voiceTask = Task {
            do {
                try await voiceController.startSession(
                    profile: appEnvironment.activeProfile,
                    resumeSessionID: sessionID,
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
