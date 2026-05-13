import Foundation

struct RuntimeSettings: Equatable {
    var intermediaryMode: IntermediaryMode = .llm
    var speechRmsThreshold: Double = 0.003
    var endSilenceSeconds: Double = 1.1
    var minTurnSeconds: Double = 0.8
    var maxTurnSeconds: Double = 8.0
    var bargeInRmsThreshold: Double = 0.025
    var bargeInWindowDuration: Double = 0.05
    var bargeInConsecutiveWindows: Int = 2

    var audioParams: RuntimeAudioParams {
        RuntimeAudioParams(
            speechRmsThreshold: speechRmsThreshold,
            endSilenceSeconds: endSilenceSeconds,
            minTurnSeconds: minTurnSeconds,
            maxTurnSeconds: maxTurnSeconds
        )
    }

    var bargeInConfig: BargeInDetector.Config {
        BargeInDetector.Config(
            windowDuration: bargeInWindowDuration,
            rmsThreshold: bargeInRmsThreshold,
            requiredConsecutiveWindows: bargeInConsecutiveWindows
        )
    }
}

struct RuntimeSettingsStore {
    private let defaults: UserDefaults
    private let keyPrefix = "runtime.settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(profileID: UUID) -> RuntimeSettings {
        var settings = RuntimeSettings()
        if let rawMode = defaults.string(forKey: key(profileID: profileID, name: "intermediaryMode")),
           let mode = IntermediaryMode(rawValue: rawMode) {
            settings.intermediaryMode = mode
        }
        settings.speechRmsThreshold = double(profileID, "speechRmsThreshold", settings.speechRmsThreshold)
        settings.endSilenceSeconds = double(profileID, "endSilenceSeconds", settings.endSilenceSeconds)
        settings.minTurnSeconds = double(profileID, "minTurnSeconds", settings.minTurnSeconds)
        settings.maxTurnSeconds = double(profileID, "maxTurnSeconds", settings.maxTurnSeconds)
        settings.bargeInRmsThreshold = double(profileID, "bargeInRmsThreshold", settings.bargeInRmsThreshold)
        settings.bargeInWindowDuration = double(profileID, "bargeInWindowDuration", settings.bargeInWindowDuration)
        settings.bargeInConsecutiveWindows = integer(
            profileID,
            "bargeInConsecutiveWindows",
            settings.bargeInConsecutiveWindows
        )
        return settings
    }

    func save(_ settings: RuntimeSettings, profileID: UUID) {
        defaults.set(settings.intermediaryMode.rawValue, forKey: key(profileID: profileID, name: "intermediaryMode"))
        defaults.set(settings.speechRmsThreshold, forKey: key(profileID: profileID, name: "speechRmsThreshold"))
        defaults.set(settings.endSilenceSeconds, forKey: key(profileID: profileID, name: "endSilenceSeconds"))
        defaults.set(settings.minTurnSeconds, forKey: key(profileID: profileID, name: "minTurnSeconds"))
        defaults.set(settings.maxTurnSeconds, forKey: key(profileID: profileID, name: "maxTurnSeconds"))
        defaults.set(settings.bargeInRmsThreshold, forKey: key(profileID: profileID, name: "bargeInRmsThreshold"))
        defaults.set(settings.bargeInWindowDuration, forKey: key(profileID: profileID, name: "bargeInWindowDuration"))
        defaults.set(settings.bargeInConsecutiveWindows, forKey: key(
            profileID: profileID,
            name: "bargeInConsecutiveWindows"
        ))
        defaults.synchronize()
    }

    private func double(_ profileID: UUID, _ name: String, _ defaultValue: Double) -> Double {
        let settingKey = key(profileID: profileID, name: name)
        guard defaults.object(forKey: settingKey) != nil else {
            return defaultValue
        }
        return defaults.double(forKey: settingKey)
    }

    private func integer(_ profileID: UUID, _ name: String, _ defaultValue: Int) -> Int {
        let settingKey = key(profileID: profileID, name: name)
        guard defaults.object(forKey: settingKey) != nil else {
            return defaultValue
        }
        return defaults.integer(forKey: settingKey)
    }

    private func key(profileID: UUID, name: String) -> String {
        "\(keyPrefix).\(profileID.uuidString).\(name)"
    }
}
