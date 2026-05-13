import Foundation

@MainActor
@Observable
final class AppEnvironment {
    private static let activeProfileIDKey = "serverRegistry.activeProfileID"

    private let keychain: KeychainStore
    private let session: URLSession
    private let voiceController: VoiceDisconnecting?
    private let defaults: UserDefaults

    var activeProfile: ServerProfile
    var credentials: Credentials?
    var isAuthenticated: Bool
    var conversationStore: ConversationStore?

    var activeServerName: String {
        activeProfile.displayName
    }

    init(
        activeProfile: ServerProfile? = nil,
        keychain: KeychainStore = KeychainStore(),
        session: URLSession = .shared,
        voiceController: VoiceDisconnecting? = nil,
        serverRegistryStore: ServerRegistryStore? = try? ServerRegistryStore(),
        defaults: UserDefaults = .standard
    ) {
        let initialProfile = activeProfile ?? Self.resolveInitialProfile(
            serverRegistryStore: serverRegistryStore,
            defaults: defaults
        )
        let initialCredentials = try? keychain.loadValid(profileID: initialProfile.id)

        self.activeProfile = initialProfile
        self.keychain = keychain
        self.session = session
        self.voiceController = voiceController ?? VoiceController()
        self.defaults = defaults
        self.credentials = initialCredentials
        self.isAuthenticated = initialCredentials != nil
        self.conversationStore = try? ConversationStore(serverProfileID: initialProfile.id)
    }

    func login(email: String, password: String) async throws {
        try await authService().login(email: email, password: password)
    }

    func verify(email: String, code: String) async throws {
        let credentials = try await authService().verify(email: email, code: code)
        try keychain.save(profileID: activeProfile.id, credentials: credentials)
        self.credentials = credentials
        isAuthenticated = true
    }

    func logout() throws {
        try authService().logout()
        credentials = nil
        isAuthenticated = false
    }

    func refreshCredentials() {
        credentials = try? keychain.loadValid(profileID: activeProfile.id)
        isAuthenticated = credentials != nil
    }

    func switchActiveProfile(_ profile: ServerProfile) {
        voiceController?.disconnect()
        activeProfile = profile
        defaults.set(profile.id.uuidString, forKey: Self.activeProfileIDKey)
        defaults.synchronize()
        conversationStore = try? ConversationStore(serverProfileID: profile.id)
        refreshCredentials()
    }

    private func authService() -> AuthService {
        AuthService(profile: activeProfile, keychain: keychain, session: session)
    }

    private static func resolveInitialProfile(
        serverRegistryStore: ServerRegistryStore?,
        defaults: UserDefaults
    ) -> ServerProfile {
        let profiles = (try? serverRegistryStore?.load()) ?? [ServerRegistryStore.defaultProfile]

        if let rawID = defaults.string(forKey: activeProfileIDKey),
           let selectedID = UUID(uuidString: rawID),
           let selectedProfile = profiles.first(where: { $0.id == selectedID }) {
            return selectedProfile
        }

        return profiles.first ?? ServerRegistryStore.defaultProfile
    }
}
