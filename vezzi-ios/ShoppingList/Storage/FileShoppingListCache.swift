import CryptoKit
import Foundation

/// Atomic snapshots are physically isolated by account and persisted sign-in session.
actor FileShoppingListCache: ShoppingListCache {
    private let directory: URL?

    init(directory: URL? = nil) {
        self.directory = directory
    }

    func load(account: ShoppingListAccount) throws -> ShoppingListCacheSnapshot? {
        let data: Data
        do { data = try Data(contentsOf: fileURL(account: account)) }
        catch CocoaError.fileReadNoSuchFile { return nil }
        let envelope = try PropertyListDecoder().decode(Envelope.self, from: data)
        guard envelope.version == Envelope.currentVersion, envelope.account == account else {
            throw ShoppingListCacheError.invalidSnapshot
        }
        try envelope.snapshot.validate()
        return envelope.snapshot
    }

    func save(_ snapshot: ShoppingListCacheSnapshot, account: ShoppingListAccount) throws {
        try snapshot.validate()
        let url = try fileURL(account: account)
        var folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(Envelope(version: Envelope.currentVersion, account: account, snapshot: snapshot))
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func remove(account: ShoppingListAccount) throws {
        let url = try fileURL(account: account)
        // Version 1 used an unscoped file. Never read it; remove it on explicit account cleanup.
        let legacy = url.deletingLastPathComponent().appendingPathComponent(fileName(accountID: account.id)).appendingPathExtension("plist")
        for file in [url, legacy] {
            do { try FileManager.default.removeItem(at: file) }
            catch CocoaError.fileNoSuchFile { }
        }
    }

    private func fileURL(account: ShoppingListAccount) throws -> URL {
        let folder: URL
        if let directory { folder = directory }
        else {
            folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
                .appendingPathComponent("ShoppingList", isDirectory: true)
        }
        let name = fileName(accountID: account.id) + "." + account.sessionID.uuidString
        return folder.appendingPathComponent(name).appendingPathExtension("plist")
    }

    private func fileName(accountID: String) -> String {
        SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private struct Envelope: Codable {
        static let currentVersion = 2
        let version: Int
        let account: ShoppingListAccount
        let snapshot: ShoppingListCacheSnapshot
    }
}
