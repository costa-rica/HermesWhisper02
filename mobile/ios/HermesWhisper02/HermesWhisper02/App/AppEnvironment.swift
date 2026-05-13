import Foundation

@MainActor
@Observable
final class AppEnvironment {
    private let keychain: KeychainStore
    private let session: URLSession
    private let voiceController: VoiceDisconnecting?

    var activeProfile: ServerProfile
    var credentials: Credentials?
    var isAuthenticated: Bool
    var conversationStore: ConversationStore?

    var activeServerName: String {
        activeProfile.displayName
    }

    init(
        activeProfile: ServerProfile = ServerRegistryStore.defaultProfile,
        keychain: KeychainStore = KeychainStore(),
        session: URLSession = .shared,
        voiceController: VoiceDisconnecting? = nil
    ) {
        let initialCredentials = try? keychain.loadValid(profileID: activeProfile.id)

        self.activeProfile = activeProfile
        self.keychain = keychain
        self.session = session
        self.voiceController = voiceController ?? VoiceController()
        self.credentials = initialCredentials
        self.isAuthenticated = initialCredentials != nil
        self.conversationStore = try? ConversationStore(serverProfileID: activeProfile.id)
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
        conversationStore = try? ConversationStore(serverProfileID: profile.id)
        refreshCredentials()
    }

    private func authService() -> AuthService {
        AuthService(profile: activeProfile, keychain: keychain, session: session)
    }
}
