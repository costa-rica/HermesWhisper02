import Foundation
import XCTest
@testable import HermesWhisper02

@MainActor
final class AppEnvironmentTests: XCTestCase {
    func testSwitchingProfilesDisconnectsAndInvalidatesCredentials() throws {
        let keychain = KeychainStore(keychain: AppEnvironmentKeychainAccess())
        let first = makeProfile(displayName: "first")
        let second = makeProfile(displayName: "second")
        let voiceController = SpyVoiceController()
        try keychain.save(profileID: first.id, credentials: makeCredentials())
        let environment = AppEnvironment(
            activeProfile: first,
            keychain: keychain,
            voiceController: voiceController
        )

        environment.switchActiveProfile(second)

        XCTAssertEqual(voiceController.disconnectCount, 1)
        XCTAssertEqual(environment.activeProfile, second)
        XCTAssertEqual(environment.conversationStore?.serverProfileID, second.id)
        XCTAssertNil(environment.credentials)
        XCTAssertFalse(environment.isAuthenticated)
    }

    func testSwitchingProfilesLoadsStoredCredentialsForNewProfile() throws {
        let keychain = KeychainStore(keychain: AppEnvironmentKeychainAccess())
        let first = makeProfile(displayName: "first")
        let second = makeProfile(displayName: "second")
        let secondCredentials = makeCredentials(token: "second-token")
        try keychain.save(profileID: second.id, credentials: secondCredentials)
        let environment = AppEnvironment(
            activeProfile: first,
            keychain: keychain,
            voiceController: SpyVoiceController()
        )

        environment.switchActiveProfile(second)

        XCTAssertEqual(environment.credentials, secondCredentials)
        XCTAssertTrue(environment.isAuthenticated)
    }

    func testStartupRestoresPersistedActiveProfile() throws {
        let defaults = makeDefaults()
        let first = makeProfile(displayName: "first")
        let second = makeProfile(displayName: "second")
        let registryStore = try makeRegistryStore()
        try registryStore.save([first, second])
        let initialEnvironment = AppEnvironment(
            activeProfile: first,
            keychain: KeychainStore(keychain: AppEnvironmentKeychainAccess()),
            voiceController: SpyVoiceController(),
            serverRegistryStore: registryStore,
            defaults: defaults
        )
        initialEnvironment.switchActiveProfile(second)

        let restoredEnvironment = AppEnvironment(
            keychain: KeychainStore(keychain: AppEnvironmentKeychainAccess()),
            voiceController: SpyVoiceController(),
            serverRegistryStore: registryStore,
            defaults: defaults
        )

        XCTAssertEqual(restoredEnvironment.activeProfile, second)
        XCTAssertEqual(restoredEnvironment.conversationStore?.serverProfileID, second.id)
    }

    func testStartupFallsBackToFirstRegistryProfileWhenSelectionIsMissing() throws {
        let first = makeProfile(displayName: "first")
        let second = makeProfile(displayName: "second")
        let registryStore = try makeRegistryStore()
        try registryStore.save([first, second])

        let environment = AppEnvironment(
            keychain: KeychainStore(keychain: AppEnvironmentKeychainAccess()),
            voiceController: SpyVoiceController(),
            serverRegistryStore: registryStore,
            defaults: makeDefaults()
        )

        XCTAssertEqual(environment.activeProfile, first)
        XCTAssertEqual(environment.conversationStore?.serverProfileID, first.id)
    }

    private func makeProfile(displayName: String) -> ServerProfile {
        ServerProfile(
            id: UUID(),
            displayName: displayName,
            baseURL: URL(string: "https://example.com")!,
            notes: nil,
            authKind: .bearer2FA
        )
    }

    private func makeCredentials(
        token: String = "token",
        expiresAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> Credentials {
        Credentials(token: token, expiresAt: expiresAt, email: "nrodrig1@gmail.com")
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppEnvironmentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeRegistryStore() throws -> ServerRegistryStore {
        let registryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("server_registry.json", isDirectory: false)
        return try ServerRegistryStore(registryURL: registryURL)
    }
}

private final class SpyVoiceController: VoiceDisconnecting {
    private(set) var disconnectCount = 0

    func disconnect() {
        disconnectCount += 1
    }
}

private final class AppEnvironmentKeychainAccess: KeychainAccessing {
    private var values: [String: Data] = [:]

    func save(data: Data, service: String, account: String) throws {
        values[key(service: service, account: account)] = data
    }

    func load(service: String, account: String) throws -> Data? {
        values[key(service: service, account: account)]
    }

    func delete(service: String, account: String) throws {
        values.removeValue(forKey: key(service: service, account: account))
    }

    private func key(service: String, account: String) -> String {
        "\(service):\(account)"
    }
}
