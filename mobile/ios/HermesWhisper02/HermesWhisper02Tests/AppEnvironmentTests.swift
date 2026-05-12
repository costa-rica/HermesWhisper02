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
