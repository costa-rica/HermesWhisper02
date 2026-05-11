import Foundation
import XCTest
@testable import HermesWhisper02

final class KeychainStoreTests: XCTestCase {
    private var keychain: InMemoryKeychainAccess!
    private var store: KeychainStore!

    override func setUp() {
        super.setUp()
        keychain = InMemoryKeychainAccess()
        store = KeychainStore(keychain: keychain)
    }

    override func tearDown() {
        store = nil
        keychain = nil
        super.tearDown()
    }

    func testSaveAndLoadRoundTrip() throws {
        let profileID = UUID()
        let credentials = makeCredentials()

        try store.save(profileID: profileID, credentials: credentials)

        XCTAssertEqual(try store.load(profileID: profileID), credentials)
    }

    func testDeleteRemovesCredentials() throws {
        let profileID = UUID()
        try store.save(profileID: profileID, credentials: makeCredentials())

        try store.delete(profileID: profileID)

        XCTAssertNil(try store.load(profileID: profileID))
    }

    func testLoadValidReturnsCredentialsBeforeExpiry() throws {
        let profileID = UUID()
        let credentials = makeCredentials(expiresAt: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(profileID: profileID, credentials: credentials)

        XCTAssertEqual(try store.loadValid(profileID: profileID), credentials)
    }

    func testLoadValidReturnsNilForExpiredCredentials() throws {
        let profileID = UUID()
        try store.save(
            profileID: profileID,
            credentials: makeCredentials(expiresAt: Date(timeIntervalSince1970: 0))
        )

        XCTAssertNil(try store.loadValid(profileID: profileID))
    }

    func testCredentialsAreIsolatedByProfileID() throws {
        let firstID = UUID()
        let secondID = UUID()
        let first = makeCredentials(token: "first-token")
        let second = makeCredentials(token: "second-token")

        try store.save(profileID: firstID, credentials: first)
        try store.save(profileID: secondID, credentials: second)

        XCTAssertEqual(try store.load(profileID: firstID), first)
        XCTAssertEqual(try store.load(profileID: secondID), second)
    }

    private func makeCredentials(
        token: String = "token",
        expiresAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
        email: String = "nrodrig1@gmail.com"
    ) -> Credentials {
        Credentials(token: token, expiresAt: expiresAt, email: email)
    }
}

private final class InMemoryKeychainAccess: KeychainAccessing {
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
