import Foundation

/// Feedback when a catalog view has no visible products, independent of its current query.
nonisolated enum CatalogEmptyState: Equatable {
    case loading
    case offline
    case empty

    init(status: CatalogStatus, cacheState: CatalogCacheState) {
        if !status.hasSnapshot && (status.isRefreshing || cacheState == .loading) {
            self = .loading
        } else if !status.hasSnapshot && (status.isOffline || status.failure == .offline) {
            self = .offline
        } else {
            self = .empty
        }
    }
}
