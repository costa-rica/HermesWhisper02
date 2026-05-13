import SwiftUI

struct SettingsView: View {
    let profileID: UUID
    @Binding var interactionMode: VoiceInteractionMode
    let settingsStore: RuntimeSettingsStore
    let onSettingsChanged: (RuntimeSettings) -> Void
    let onIntermediaryModeChanged: (IntermediaryMode) -> Void
    let onAudioParamsChanged: (RuntimeAudioParams) -> Void
    let onBargeInChanged: (BargeInDetector.Config) -> Void
    let onInteractionModeChanged: (VoiceInteractionMode) -> Void
    let onLogout: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings = RuntimeSettings()
    @State private var helpTopic: SettingsHelpTopic?

    var body: some View {
        Form {
            Section("Intermediary routing") {
                settingsParameterHeader(topic: .intermediaryMode)
                Picker("Mode", selection: intermediaryModeBinding) {
                    ForEach(IntermediaryMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text("Changes apply at the next turn.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Server VAD") {
                settingsSlider(
                    topic: .speechRmsThreshold,
                    value: speechRmsThresholdBinding,
                    range: 0.001...0.05,
                    format: .number.precision(.fractionLength(3)),
                    onCommit: sendAudioParams
                )
                settingsSlider(
                    topic: .endSilenceSeconds,
                    value: endSilenceSecondsBinding,
                    range: 0.3...3.0,
                    format: .number.precision(.fractionLength(1)),
                    onCommit: sendAudioParams
                )
                settingsSlider(
                    topic: .minTurnSeconds,
                    value: minTurnSecondsBinding,
                    range: 0.2...2.0,
                    format: .number.precision(.fractionLength(1)),
                    onCommit: sendAudioParams
                )
                settingsSlider(
                    topic: .maxTurnSeconds,
                    value: maxTurnSecondsBinding,
                    range: 5.0...180.0,
                    format: .number.precision(.fractionLength(0)),
                    onCommit: sendAudioParams
                )
            }

            Section("Barge-in") {
                settingsSlider(
                    topic: .bargeInRmsThreshold,
                    value: bargeInRmsThresholdBinding,
                    range: 0.01...0.10,
                    format: .number.precision(.fractionLength(3)),
                    onCommit: sendBargeInConfig
                )
                settingsSlider(
                    topic: .bargeInWindowDuration,
                    value: bargeInWindowDurationBinding,
                    range: 0.01...0.20,
                    format: .number.precision(.fractionLength(2)),
                    onCommit: sendBargeInConfig
                )
                Stepper(
                    value: bargeInConsecutiveWindowsBinding,
                    in: 1...5
                ) {
                    settingsParameterHeader(
                        topic: .bargeInConsecutiveWindows,
                        value: "\(settings.bargeInConsecutiveWindows)"
                    )
                }
            }

            Section("Voice") {
                settingsParameterHeader(topic: .voiceInteraction)
                Picker("Interaction", selection: $interactionMode) {
                    ForEach(VoiceInteractionMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .onChange(of: interactionMode) { _, mode in
                    onInteractionModeChanged(mode)
                }
            }

            Section {
                Button("Log out", role: .destructive) {
                    dismiss()
                    onLogout()
                }
            }
        }
        .alert(item: $helpTopic) { topic in
            Alert(
                title: Text(topic.title),
                message: Text(topic.description),
                dismissButton: .default(Text("OK"))
            )
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onAppear {
            settings = settingsStore.load(profileID: profileID)
            onSettingsChanged(settings)
        }
    }

    private var intermediaryModeBinding: Binding<IntermediaryMode> {
        Binding(
            get: { settings.intermediaryMode },
            set: { mode in
                settings.intermediaryMode = mode
                persistSettings()
                onIntermediaryModeChanged(mode)
            }
        )
    }

    private var speechRmsThresholdBinding: Binding<Double> {
        Binding(get: { settings.speechRmsThreshold }, set: { settings.speechRmsThreshold = $0; persistSettings() })
    }

    private var endSilenceSecondsBinding: Binding<Double> {
        Binding(get: { settings.endSilenceSeconds }, set: { settings.endSilenceSeconds = $0; persistSettings() })
    }

    private var minTurnSecondsBinding: Binding<Double> {
        Binding(get: { settings.minTurnSeconds }, set: { settings.minTurnSeconds = $0; persistSettings() })
    }

    private var maxTurnSecondsBinding: Binding<Double> {
        Binding(get: { settings.maxTurnSeconds }, set: { settings.maxTurnSeconds = $0; persistSettings() })
    }

    private var bargeInRmsThresholdBinding: Binding<Double> {
        Binding(get: { settings.bargeInRmsThreshold }, set: { settings.bargeInRmsThreshold = $0; persistSettings() })
    }

    private var bargeInWindowDurationBinding: Binding<Double> {
        Binding(get: { settings.bargeInWindowDuration }, set: { settings.bargeInWindowDuration = $0; persistSettings() })
    }

    private var bargeInConsecutiveWindowsBinding: Binding<Int> {
        Binding(
            get: { settings.bargeInConsecutiveWindows },
            set: { value in
                settings.bargeInConsecutiveWindows = value
                persistSettings()
                sendBargeInConfig()
            }
        )
    }

    private func settingsSlider<F: FormatStyle>(
        topic: SettingsHelpTopic,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: F,
        onCommit: @escaping () -> Void
    ) -> some View where F.FormatInput == Double, F.FormatOutput == String {
        VStack(alignment: .leading, spacing: 6) {
            settingsParameterHeader(topic: topic, value: value.wrappedValue.formatted(format))
            Slider(value: value, in: range) { editing in
                if !editing {
                    onCommit()
                }
            }
        }
    }

    private func settingsParameterHeader(topic: SettingsHelpTopic, value: String? = nil) -> some View {
        HStack(spacing: 8) {
            Button {
                helpTopic = topic
            } label: {
                HStack(spacing: 6) {
                    Text(topic.title)
                    Image(systemName: "info.circle")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About \(topic.title)")
            Spacer()
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func persistSettings() {
        settingsStore.save(settings, profileID: profileID)
        onSettingsChanged(settings)
    }

    private func sendAudioParams() {
        onAudioParamsChanged(settings.audioParams)
    }

    private func sendBargeInConfig() {
        onBargeInChanged(settings.bargeInConfig)
    }
}

private enum SettingsHelpTopic: String, Identifiable {
    case intermediaryMode
    case speechRmsThreshold
    case endSilenceSeconds
    case minTurnSeconds
    case maxTurnSeconds
    case bargeInRmsThreshold
    case bargeInWindowDuration
    case bargeInConsecutiveWindows
    case voiceInteraction

    var id: String { rawValue }

    var title: String {
        switch self {
        case .intermediaryMode:
            return "Mode"
        case .speechRmsThreshold:
            return "Speech RMS"
        case .endSilenceSeconds:
            return "End silence"
        case .minTurnSeconds:
            return "Minimum turn"
        case .maxTurnSeconds:
            return "Maximum turn"
        case .bargeInRmsThreshold:
            return "RMS threshold"
        case .bargeInWindowDuration:
            return "Window"
        case .bargeInConsecutiveWindows:
            return "Consecutive windows"
        case .voiceInteraction:
            return "Interaction"
        }
    }

    var description: String {
        switch self {
        case .intermediaryMode:
            return "Controls how the mobile voice request is routed before Hermes answers. Changes apply on the next turn."
        case .speechRmsThreshold:
            return "Server-side speech energy needed to start a turn. Lower values hear quieter speech; higher values ignore more background noise."
        case .endSilenceSeconds:
            return "How long the server waits after speech becomes quiet before it sends the turn to Hermes."
        case .minTurnSeconds:
            return "The shortest spoken segment accepted as a turn. Raise it to reduce accidental tiny turns; lower it for quicker short requests."
        case .maxTurnSeconds:
            return "The longest continuous segment collected before the server forces the turn to end and sends it. Longer turns can feel slower."
        case .bargeInRmsThreshold:
            return "Local microphone energy needed to interrupt assistant playback. Lower values interrupt more easily; higher values require louder speech."
        case .bargeInWindowDuration:
            return "How much microphone audio is measured at a time for barge-in. Shorter windows react faster; longer windows are steadier."
        case .bargeInConsecutiveWindows:
            return "How many loud windows must happen in a row before playback stops. Higher values reduce false interruptions."
        case .voiceInteraction:
            return "Continuous keeps listening until you stop voice. Push to talk listens only while the talk control is active."
        }
    }
}
