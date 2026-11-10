import Foundation

/// Serializes catalog changes away from the UI and keeps imports atomic.
actor CatalogSession {
    private var snapshot = CatalogSnapshot()
    private var revision = 0

    func apply(_ batch: CatalogImport, at date: Date) throws -> CatalogSessionUpdate {
        let result = try snapshot.applying(CatalogCacheBatch(import: batch, cachedAt: date))
        try Task.checkCancellation()
        snapshot = result.snapshot
        revision += 1
        return CatalogSessionUpdate(revision: revision, snapshot: snapshot, changes: result.changes)
    }

    func mergeCache(_ stored: CatalogSnapshot) -> CatalogSessionUpdate {
        snapshot = snapshot.mergingCache(stored)
        revision += 1
        return CatalogSessionUpdate(revision: revision, snapshot: snapshot, changes: snapshot.changes(comparedTo: stored))
    }

    func replace(_ batch: CatalogCacheBatch) throws -> CatalogSessionUpdate {
        guard batch.metadata != nil else { throw APIError.invalidResponse }
        var replacement = batch
        replacement.replacesCatalog = true
        let result = try CatalogSnapshot().applying(replacement)
        try Task.checkCancellation()
        snapshot = result.snapshot
        revision += 1
        return CatalogSessionUpdate(revision: revision, snapshot: snapshot, changes: result.changes, replacesCatalog: true)
    }

    func validate(at date: Date) -> CatalogSessionUpdate {
        snapshot = snapshot.validated(at: date)
        revision += 1
        return CatalogSessionUpdate(revision: revision, snapshot: snapshot, changes: CatalogRecordIDs(metadata: true))
    }
}

nonisolated struct CatalogSessionUpdate: Sendable {
    let revision: Int
    let snapshot: CatalogSnapshot
    let changes: CatalogRecordIDs
    var replacesCatalog = false
}
