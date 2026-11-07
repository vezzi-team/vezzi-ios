import Foundation
import Security

/// Accessed only by the authentication actor. A pair of tokens is replaced as one Keychain item.
nonisolated protocol AuthenticationSessionStore: Sendable {
    func load() throws -> StoredAuthentication?
    func save(_ session: StoredAuthentication) throws
    func remove() throws
    func invalidatedSessionID() throws -> UUID?
    func markInvalidated(_ id: UUID) throws
    func clearInvalidation() throws
}

nonisolated struct KeychainSessionStore: AuthenticationSessionStore {
    private let service: String
    private let invalidationURL: URL?
    private let account = "authentication.session.v1"

    init(service: String = (Bundle.main.bundleIdentifier ?? "vezzi-ios") + ".authentication", invalidationURL: URL? = nil) {
        self.service = service
        self.invalidationURL = invalidationURL
    }

    func load() throws -> StoredAuthentication? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AuthenticationStorageError.keychain(status) }
        guard let data = result as? Data else { throw AuthenticationStorageError.invalidRecord }
        do { return try JSONDecoder().decode(StoredAuthentication.self, from: data) }
        catch { throw AuthenticationStorageError.invalidRecord }
    }

    func save(_ session: StoredAuthentication) throws {
        let data: Data
        do { data = try JSONEncoder().encode(session) }
        catch { throw AuthenticationStorageError.invalidRecord }
        let attributes: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw AuthenticationStorageError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw AuthenticationStorageError.keychain(status)
        }
    }

    func remove() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AuthenticationStorageError.keychain(status) }
    }

    // Only a local session UUID is stored outside Keychain, never credentials or user data.
    // It prevents a rejected record from being restored when Keychain deletion is unavailable.
    func invalidatedSessionID() throws -> UUID? {
        do {
            return try JSONDecoder().decode(UUID.self, from: Data(contentsOf: markerURL()))
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            throw AuthenticationStorageError.invalidationFile
        }
    }

    func markInvalidated(_ id: UUID) throws {
        do {
            let url = try markerURL()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(id).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            throw AuthenticationStorageError.invalidationFile
        }
    }

    func clearInvalidation() throws {
        do {
            try FileManager.default.removeItem(at: markerURL())
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            throw AuthenticationStorageError.invalidationFile
        }
    }

    private func markerURL() throws -> URL {
        if let invalidationURL { return invalidationURL }
        return try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                           appropriateFor: nil, create: false)
            .appendingPathComponent("Authentication", isDirectory: true)
            .appendingPathComponent(service + ".invalidated.json")
    }

    private var baseQuery: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }
}

nonisolated enum AuthenticationStorageError: Error, Equatable, Sendable {
    case keychain(OSStatus)
    case invalidRecord
    case invalidationFile
}
