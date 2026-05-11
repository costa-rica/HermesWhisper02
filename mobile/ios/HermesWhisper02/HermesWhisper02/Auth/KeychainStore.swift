import Foundation
import Security

struct Credentials: Codable, Equatable {
    var token: String
    var expiresAt: Date
    var email: String
}

protocol CredentialStoring {
    func save(profileID: UUID, credentials: Credentials) throws
    func load(profileID: UUID) throws -> Credentials?
    func loadValid(profileID: UUID) throws -> Credentials?
    func delete(profileID: UUID) throws
}

struct KeychainStore: CredentialStoring {
    enum StoreError: Error, Equatable {
        case unexpectedStatus(OSStatus)
    }

    private static let defaultService = "com.dashanddata.hw02.credentials"

    private let service: String
    private let keychain: KeychainAccessing
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        service: String = Self.defaultService,
        keychain: KeychainAccessing = SystemKeychainAccess()
    ) {
        self.service = service
        self.keychain = keychain

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func save(profileID: UUID, credentials: Credentials) throws {
        let data = try encoder.encode(credentials)
        try keychain.save(
            data: data,
            service: service,
            account: profileID.uuidString
        )
    }

    func load(profileID: UUID) throws -> Credentials? {
        guard let data = try keychain.load(
            service: service,
            account: profileID.uuidString
        ) else {
            return nil
        }

        return try decoder.decode(Credentials.self, from: data)
    }

    func loadValid(profileID: UUID) throws -> Credentials? {
        guard let credentials = try load(profileID: profileID) else {
            return nil
        }

        return credentials.expiresAt > Date() ? credentials : nil
    }

    func delete(profileID: UUID) throws {
        try keychain.delete(
            service: service,
            account: profileID.uuidString
        )
    }
}

protocol KeychainAccessing {
    func save(data: Data, service: String, account: String) throws
    func load(service: String, account: String) throws -> Data?
    func delete(service: String, account: String) throws
}

struct SystemKeychainAccess: KeychainAccessing {
    func save(data: Data, service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw KeychainStore.StoreError.unexpectedStatus(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStore.StoreError.unexpectedStatus(addStatus)
        }
    }

    func load(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainStore.StoreError.unexpectedStatus(status)
        }

        return result as? Data
    }

    func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStore.StoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(service: String, account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}
