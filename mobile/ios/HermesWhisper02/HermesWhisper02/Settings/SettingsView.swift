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
    @State private var settings: RuntimeSettings

    init(
        profileID: UUID,
        interactionMode: Binding<VoiceInteractionMode>,
        settingsStore: RuntimeSettingsStore,
        initialSettings: RuntimeSettings,
        onSettingsChanged: @escaping (RuntimeSettings) -> Void,
        onIntermediaryModeChanged: @escaping (IntermediaryMode) -> Void,
        onAudioParamsChanged: @escaping (RuntimeAudioParams) -> Void,
        onBargeInChanged: @escaping (BargeInDetector.Config) -> Void,
        onInteractionModeChanged: @escaping (VoiceInteractionMode) -> Void,
        onLogout: @escaping () -> Void
    ) {
        self.profileID = profileID
        self._interactionMode = interactionMode
        self.settingsStore = settingsStore
        self.onSettingsChanged = onSettingsChanged
        self.onIntermediaryModeChanged = onIntermediaryModeChanged
        self.onAudioParamsChanged = onAudioParamsChanged
        self.onBargeInChanged = onBargeInChanged
        self.onInteractionModeChanged = onInteractionModeChanged
        self.onLogout = onLogout
        self._settings = State(initialValue: initialSettings)
    }

    var body: some View {
        Form {
            Section("Intermediary routing") {
                Picker("Mode", selection: intermediaryModeBinding) {
                    ForEach(IntermediaryMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("Changes apply at the next turn.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Server VAD") {
                settingsSlider(
                    title: "Speech RMS",
                    value: speechRmsThresholdBinding,
                    range: 0.001...0.05,
                    format: .number.precision(.fractionLength(3)),
                    onCommit: sendAudioParams
                )
                settingsSlider(
                    title: "End silence",
                    value: endSilenceSecondsBinding,
                    range: 0.3...3.0,
                    format: .number.precision(.fractionLength(1)),
                    onCommit: sendAudioParams
                )
                settingsSlider(
                    title: "Minimum turn",
                    value: minTurnSecondsBinding,
                    range: 0.2...2.0,
                    format: .number.precision(.fractionLength(1)),
                    onCommit: sendAudioParams
                )
                settingsSlider(
                    title: "Maximum turn",
                    value: maxTurnSecondsBinding,
                    range: 5.0...30.0,
                    format: .number.precision(.fractionLength(0)),
                    onCommit: sendAudioParams
                )
            }

            Section("Barge-in") {
                settingsSlider(
                    title: "RMS threshold",
                    value: bargeInRmsThresholdBinding,
                    range: 0.01...0.10,
                    format: .number.precision(.fractionLength(3)),
                    onCommit: sendBargeInConfig
                )
                settingsSlider(
                    title: "Window",
                    value: bargeInWindowDurationBinding,
                    range: 0.01...0.20,
                    format: .number.precision(.fractionLength(2)),
                    onCommit: sendBargeInConfig
                )
                Stepper(
                    "Consecutive windows: \(settings.bargeInConsecutiveWindows)",
                    value: bargeInConsecutiveWindowsBinding,
                    in: 1...5
                )
            }

            Section("Voice") {
                Picker("Interaction", selection: $interactionMode) {
                    ForEach(VoiceInteractionMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
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
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
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
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: F,
        onCommit: @escaping () -> Void
    ) -> some View where F.FormatInput == Double, F.FormatOutput == String {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: format)
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range) { editing in
                if !editing {
                    onCommit()
                }
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
