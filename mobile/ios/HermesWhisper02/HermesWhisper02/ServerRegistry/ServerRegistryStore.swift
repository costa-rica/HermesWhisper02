import Foundation

struct ServerRegistryStore {
    enum StoreError: Error, Equatable {
        case profileNotFound(UUID)
    }

    private let fileManager: FileManager
    private let registryURL: URL

    init(fileManager: FileManager = .default, registryURL: URL? = nil) throws {
        self.fileManager = fileManager

        if let registryURL {
            self.registryURL = registryURL
        } else {
            let applicationSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.registryURL = applicationSupportURL
                .appendingPathComponent("HermesWhisper02", isDirectory: true)
                .appendingPathComponent("server_registry.json", isDirectory: false)
        }
    }

    func load() throws -> [ServerProfile] {
        guard fileManager.fileExists(atPath: registryURL.path) else {
            let profiles = [Self.defaultProfile]
            try save(profiles)
            return profiles
        }

        let data = try Data(contentsOf: registryURL)
        return try Self.decoder.decode([ServerProfile].self, from: data)
    }

    func save(_ profiles: [ServerProfile]) throws {
        let directoryURL = registryURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try Self.encoder.encode(profiles)
        try data.write(to: registryURL, options: [.atomic])
    }

    func add(_ profile: ServerProfile) throws {
        var profiles = try load()
        profiles.append(profile)
        try save(profiles)
    }

    func update(_ profile: ServerProfile) throws {
        var profiles = try load()

        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw StoreError.profileNotFound(profile.id)
        }

        profiles[index] = profile
        try save(profiles)
    }

    func delete(id: UUID) throws {
        let profiles = try load().filter { $0.id != id }
        try save(profiles)
    }

    func reorder(_ profiles: [ServerProfile]) throws {
        try save(profiles)
    }

    static let defaultProfile = ServerProfile(
        id: UUID(uuidString: "D0A46C25-15FD-4E97-95DA-3D2F978E63BE")!,
        displayName: "fsdc-avatar08",
        baseURL: URL(string: "https://api.hermes-whisper.dashanddata.com")!,
        notes: nil,
        authKind: .bearer2FA
    )

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}
