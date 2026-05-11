import XCTest
@testable import HermesWhisper02

final class ServerRegistryStoreTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        tempDirectoryURL = nil
    }

    func testWriteAndReadRoundTrip() throws {
        let store = try makeStore()
        let profile = makeProfile(displayName: "local", baseURL: "http://127.0.0.1:8765")

        try store.save([profile])

        XCTAssertEqual(try store.load(), [profile])
    }

    func testPrepopulatesEmptyStore() throws {
        let store = try makeStore()

        let profiles = try store.load()

        XCTAssertEqual(profiles, [ServerRegistryStore.defaultProfile])
        XCTAssertEqual(try store.load(), [ServerRegistryStore.defaultProfile])
    }

    func testDeleteRemovesProfile() throws {
        let store = try makeStore()
        let first = makeProfile(displayName: "first")
        let second = makeProfile(displayName: "second")
        try store.save([first, second])

        try store.delete(id: first.id)

        XCTAssertEqual(try store.load(), [second])
    }

    func testReorderPersistsNewOrder() throws {
        let store = try makeStore()
        let first = makeProfile(displayName: "first")
        let second = makeProfile(displayName: "second")
        let third = makeProfile(displayName: "third")
        try store.save([first, second, third])

        try store.reorder([third, first, second])

        XCTAssertEqual(try store.load(), [third, first, second])
    }

    func testUpdateReplacesMatchingProfile() throws {
        let store = try makeStore()
        let original = makeProfile(displayName: "original")
        let untouched = makeProfile(displayName: "untouched")
        var updated = original
        updated.displayName = "updated"
        updated.notes = "edited"
        try store.save([original, untouched])

        try store.update(updated)

        XCTAssertEqual(try store.load(), [updated, untouched])
    }

    private func makeStore() throws -> ServerRegistryStore {
        try ServerRegistryStore(
            registryURL: tempDirectoryURL
                .appendingPathComponent("HermesWhisper02", isDirectory: true)
                .appendingPathComponent("server_registry.json", isDirectory: false)
        )
    }

    private func makeProfile(
        id: UUID = UUID(),
        displayName: String,
        baseURL: String = "https://example.com",
        notes: String? = nil
    ) -> ServerProfile {
        ServerProfile(
            id: id,
            displayName: displayName,
            baseURL: URL(string: baseURL)!,
            notes: notes,
            authKind: .bearer2FA
        )
    }
}
