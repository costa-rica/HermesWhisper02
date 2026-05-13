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
    private let globalScope = "global"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(profileID: UUID) -> RuntimeSettings {
        if !hasGlobalSettings(), hasProfileSettings(profileID: profileID) {
            let migratedSettings = loadFromProfile(profileID: profileID)
            save(migratedSettings, profileID: profileID)
            return migratedSettings
        }

        return loadGlobal()
    }

    func save(_ settings: RuntimeSettings, profileID _: UUID) {
        defaults.set(settings.intermediaryMode.rawValue, forKey: key(name: "intermediaryMode"))
        defaults.set(settings.speechRmsThreshold, forKey: key(name: "speechRmsThreshold"))
        defaults.set(settings.endSilenceSeconds, forKey: key(name: "endSilenceSeconds"))
        defaults.set(settings.minTurnSeconds, forKey: key(name: "minTurnSeconds"))
        defaults.set(settings.maxTurnSeconds, forKey: key(name: "maxTurnSeconds"))
        defaults.set(settings.bargeInRmsThreshold, forKey: key(name: "bargeInRmsThreshold"))
        defaults.set(settings.bargeInWindowDuration, forKey: key(name: "bargeInWindowDuration"))
        defaults.set(settings.bargeInConsecutiveWindows, forKey: key(name: "bargeInConsecutiveWindows"))
        defaults.synchronize()
    }

    private func loadGlobal() -> RuntimeSettings {
        var settings = RuntimeSettings()
        if let rawMode = defaults.string(forKey: key(name: "intermediaryMode")),
           let mode = IntermediaryMode(rawValue: rawMode) {
            settings.intermediaryMode = mode
        }
        settings.speechRmsThreshold = double("speechRmsThreshold", settings.speechRmsThreshold)
        settings.endSilenceSeconds = double("endSilenceSeconds", settings.endSilenceSeconds)
        settings.minTurnSeconds = double("minTurnSeconds", settings.minTurnSeconds)
        settings.maxTurnSeconds = double("maxTurnSeconds", settings.maxTurnSeconds)
        settings.bargeInRmsThreshold = double("bargeInRmsThreshold", settings.bargeInRmsThreshold)
        settings.bargeInWindowDuration = double("bargeInWindowDuration", settings.bargeInWindowDuration)
        settings.bargeInConsecutiveWindows = integer("bargeInConsecutiveWindows", settings.bargeInConsecutiveWindows)
        return settings
    }

    private func loadFromProfile(profileID: UUID) -> RuntimeSettings {
        var settings = RuntimeSettings()
        if let rawMode = defaults.string(forKey: profileKey(profileID: profileID, name: "intermediaryMode")),
           let mode = IntermediaryMode(rawValue: rawMode) {
            settings.intermediaryMode = mode
        }
        settings.speechRmsThreshold = profileDouble(profileID, "speechRmsThreshold", settings.speechRmsThreshold)
        settings.endSilenceSeconds = profileDouble(profileID, "endSilenceSeconds", settings.endSilenceSeconds)
        settings.minTurnSeconds = profileDouble(profileID, "minTurnSeconds", settings.minTurnSeconds)
        settings.maxTurnSeconds = profileDouble(profileID, "maxTurnSeconds", settings.maxTurnSeconds)
        settings.bargeInRmsThreshold = profileDouble(profileID, "bargeInRmsThreshold", settings.bargeInRmsThreshold)
        settings.bargeInWindowDuration = profileDouble(profileID, "bargeInWindowDuration", settings.bargeInWindowDuration)
        settings.bargeInConsecutiveWindows = profileInteger(
            profileID,
            "bargeInConsecutiveWindows",
            settings.bargeInConsecutiveWindows
        )
        return settings
    }

    private func hasGlobalSettings() -> Bool {
        defaults.object(forKey: key(name: "intermediaryMode")) != nil
            || defaults.object(forKey: key(name: "speechRmsThreshold")) != nil
    }

    private func hasProfileSettings(profileID: UUID) -> Bool {
        defaults.object(forKey: profileKey(profileID: profileID, name: "intermediaryMode")) != nil
            || defaults.object(forKey: profileKey(profileID: profileID, name: "speechRmsThreshold")) != nil
    }

    private func double(_ name: String, _ defaultValue: Double) -> Double {
        let settingKey = key(name: name)
        guard defaults.object(forKey: settingKey) != nil else {
            return defaultValue
        }
        return defaults.double(forKey: settingKey)
    }

    private func integer(_ name: String, _ defaultValue: Int) -> Int {
        let settingKey = key(name: name)
        guard defaults.object(forKey: settingKey) != nil else {
            return defaultValue
        }
        return defaults.integer(forKey: settingKey)
    }

    private func profileDouble(_ profileID: UUID, _ name: String, _ defaultValue: Double) -> Double {
        let settingKey = profileKey(profileID: profileID, name: name)
        guard defaults.object(forKey: settingKey) != nil else {
            return defaultValue
        }
        return defaults.double(forKey: settingKey)
    }

    private func profileInteger(_ profileID: UUID, _ name: String, _ defaultValue: Int) -> Int {
        let settingKey = profileKey(profileID: profileID, name: name)
        guard defaults.object(forKey: settingKey) != nil else {
            return defaultValue
        }
        return defaults.integer(forKey: settingKey)
    }

    private func key(name: String) -> String {
        "\(keyPrefix).\(globalScope).\(name)"
    }

    private func profileKey(profileID: UUID, name: String) -> String {
        "\(keyPrefix).\(profileID.uuidString).\(name)"
    }
}
