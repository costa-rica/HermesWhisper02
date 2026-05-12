import Foundation

enum VoiceInteractionMode: String, CaseIterable, Identifiable {
    case pushToTalk
    case continuous

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .pushToTalk:
            "Push to talk"
        case .continuous:
            "Continuous"
        }
    }

    var pttMode: Bool {
        self == .pushToTalk
    }
}

struct VoiceInteractionModeStore {
    private let defaults: UserDefaults
    private let keyPrefix = "voice.interactionMode"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(profileID: UUID) -> VoiceInteractionMode {
        guard
            let rawValue = defaults.string(forKey: key(profileID: profileID)),
            let mode = VoiceInteractionMode(rawValue: rawValue)
        else {
            return .continuous
        }
        return mode
    }

    func save(_ mode: VoiceInteractionMode, profileID: UUID) {
        defaults.set(mode.rawValue, forKey: key(profileID: profileID))
    }

    private func key(profileID: UUID) -> String {
        "\(keyPrefix).\(profileID.uuidString)"
    }
}
