import CoreGraphics
import Kingfisher

/// Images are disposable independently of the catalog, cart and offline shopping progress.
enum CatalogImageCache {
    static let shared: ImageCache = {
        let cache = ImageCache(name: "catalog-media")
        cache.memoryStorage.config.totalCostLimit = 48 * 1024 * 1024
        cache.diskStorage.config.sizeLimit = 192 * 1024 * 1024
        cache.diskStorage.config.expiration = .days(30)
        return cache
    }()

    static func cardProcessor(width: CGFloat, displayScale: CGFloat) -> DownsamplingImageProcessor {
        // Round up in physical pixels so similar layouts share a thumbnail at full display density.
        let step: CGFloat = 32
        let pixels = max(step, (width * displayScale / step).rounded(.up) * step)
        return DownsamplingImageProcessor(size: CGSize(width: pixels, height: pixels))
    }

    enum ClearError: Error { case imagesRemainOnDisk }

    static func clear(_ cache: ImageCache) async throws {
        await cache.clearCache()
        // Kingfisher suppresses removal errors. Verify on its serial disk queue before confirming.
        guard try await cache.diskStorageSize == 0 else { throw ClearError.imagesRemainOnDisk }
    }

    // Keep server-encoded WebP on disk. Store logos at their downsampled size.
    static let artworkSerializer: DefaultCacheSerializer = {
        var serializer = DefaultCacheSerializer.default
        serializer.preferCacheOriginalData = true
        return serializer
    }()
}
