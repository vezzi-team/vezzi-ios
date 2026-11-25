import Kingfisher
import SwiftUI
import XCTest
@testable import vezzi_ios

@MainActor
final class CatalogImageTests: XCTestCase {
    func testWebPArtworkAndProcessedLogoSurviveCacheReopeningOffline() async throws {
        // Two pixels (red and green), encoded as a lossless WebP.
        let webP = try XCTUnwrap(Data(base64Encoded: "UklGRh4AAABXRUJQVlA4TBEAAAAvAQAAAA+w//Mf8x8VMqL/AQA="))
        let png = try Data(contentsOf: XCTUnwrap(PreviewCatalogRepository.artworkURL))
        let server = AuthenticationHTTPStub { request, requests in
            guard requests.count <= 2 else { return .failure(.notConnectedToInternet) }
            return request.url?.pathExtension == "webp"
                ? HTTPStubReply(body: webP, headers: ["Content-Type": "image/webp"])
                : HTTPStubReply(body: png, headers: ["Content-Type": "image/png"])
        }
        defer { AuthenticationURLProtocol.unregister(server.host) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloader = ImageDownloader(name: server.host)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthenticationURLProtocol.self]
        downloader.sessionConfiguration = configuration
        let assets: [(String, KingfisherOptionsInfo)] = [
            ("photo.webp", [.cacheSerializer(CatalogImageCache.artworkSerializer)]),
            ("store.png", [.processor(DownsamplingImageProcessor(size: CGSize(width: 48, height: 48)))])
        ]
        for offline in [false, true] {
            let cache = try ImageCache(name: "media", cacheDirectoryURL: directory)
            let manager = KingfisherManager(downloader: downloader, cache: cache)
            for (file, options) in assets {
                let url = try XCTUnwrap(URL(string: "https://\(server.host)/\(file)"))
                let result = try await manager.retrieveImage(with: url, options: options + (offline ? [.onlyFromCache] : [.waitForCache]))
                XCTAssertEqual(result.cacheType, offline ? .disk : .none)
                XCTAssertGreaterThan(result.image.size.width, 0)
            }
        }
        XCTAssertEqual(server.requests.count, 2)
    }

    func testCardThumbnailsReuseOneOriginalAcrossSizesAndCacheReopening() async throws {
        let png = try Data(contentsOf: XCTUnwrap(PreviewCatalogRepository.artworkURL))
        let server = AuthenticationHTTPStub { _, requests in
            requests.count == 1 ? HTTPStubReply(body: png, headers: ["Content-Type": "image/png"])
                : .failure(.notConnectedToInternet)
        }
        defer { AuthenticationURLProtocol.unregister(server.host) }
        let url = try XCTUnwrap(URL(string: "https://\(server.host)/product.png"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloader = ImageDownloader(name: server.host)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthenticationURLProtocol.self]
        downloader.sessionConfiguration = configuration

        for (scale, pixels) in [(3, 96), (2, 64)] {
            let cache = try ImageCache(name: "cards", cacheDirectoryURL: directory)
            let manager = KingfisherManager(downloader: downloader, cache: cache)
            let processor = CatalogImageCache.cardProcessor(width: 31, displayScale: CGFloat(scale))
            let options: KingfisherOptionsInfo = [.processor(processor), .scaleFactor(1), .cacheMemoryOnly,
                                                   .cacheOriginalImage, .waitForCache]
            let thumbnail = try await manager.retrieveImage(with: url, options: options + (scale == 2 ? [.onlyFromCache] : []))
            XCTAssertEqual(thumbnail.image.cgImage?.width, pixels)
            XCTAssertEqual(cache.imageCachedType(forKey: url.cacheKey, processorIdentifier: processor.identifier), .memory)
            cache.clearMemoryCache()
            XCTAssertEqual(cache.imageCachedType(forKey: url.cacheKey, processorIdentifier: processor.identifier), .none)
            if scale == 2 {
                let original = try await manager.retrieveImage(with: url, options: [.onlyFromCache])
                XCTAssertEqual(original.image.cgImage?.width, 128)
            }
        }
        XCTAssertEqual(server.requests.count, 1)
    }

    func testVisibleImageRetriesAfterReconnectionAndManualRefresh() async throws {
        let png = try Data(contentsOf: XCTUnwrap(PreviewCatalogRepository.artworkURL))
        let server = AuthenticationHTTPStub { request, requests in
            if request.url?.path == "/retry", requests.filter({ $0.url == request.url }).count <= 2 {
                return HTTPStubReply(delay: 0.15, error: URLError(.notConnectedToInternet))
            }
            return HTTPStubReply(body: png, headers: ["Content-Type": "image/png"])
        }
        defer { AuthenticationURLProtocol.unregister(server.host) }
        let manager = try makeManager(for: server)
        defer { try? FileManager.default.removeItem(at: manager.cache.diskStorage.directoryURL) }
        let catalog = DefaultCatalogRepository(source: FixedCatalogSource(batch: CatalogImport()))
        catalog.updateConnectivity(isConnected: false)
        let retries = CatalogImageRetries(catalog: catalog)
        let retryURL = try XCTUnwrap(URL(string: "https://\(server.host)/retry"))
        let loadedURL = try XCTUnwrap(URL(string: "https://\(server.host)/loaded"))
        let window = try show(VStack {
            CatalogImage(url: retryURL)
            CatalogImage(url: loadedURL)
        }
            .environment(\.catalogImageRetries, retries)
            .environment(\.catalogImageCache, manager.cache)
            .environment(\.catalogImageDownloader, manager.downloader))
        defer { window.isHidden = true }

        try await waitUntil { server.count("/retry") == 1 }
        catalog.updateConnectivity(isConnected: true)
        try await waitUntil { server.count("/retry") == 2 && manager.cache.isCached(forKey: loadedURL.cacheKey) }
        // Evicting the good image makes an unintended restart of that view observable as a new request.
        try await CatalogImageCache.clear(manager.cache)
        try await catalog.refresh()
        try await waitUntil { manager.cache.isCached(forKey: retryURL.cacheKey) }
        XCTAssertEqual(server.count("/retry"), 3)
        XCTAssertEqual(server.count("/loaded"), 1)
    }

    func testDismissingDetailsCancelsTheFallbackBeforeItCanRefillTheCache() async throws {
        let png = try Data(contentsOf: XCTUnwrap(PreviewCatalogRepository.artworkURL))
        let server = AuthenticationHTTPStub { request, _ in
            if request.url?.path == "/wide" { return HTTPStubReply(status: 404) }
            return HTTPStubReply(body: png, headers: ["Content-Type": "image/png"], delay: 1)
        }
        defer { AuthenticationURLProtocol.unregister(server.host) }
        let manager = try makeManager(for: server)
        defer { try? FileManager.default.removeItem(at: manager.cache.diskStorage.directoryURL) }
        let wide = try XCTUnwrap(URL(string: "https://\(server.host)/wide"))
        let square = try XCTUnwrap(URL(string: "https://\(server.host)/square"))
        let window = try show(CatalogImage(url: wide, fallbackURL: square)
            .environment(\.catalogImageCache, manager.cache)
            .environment(\.catalogImageDownloader, manager.downloader))
        defer { window.isHidden = true }
        let hostWasReleased = { [weak host = window.rootViewController] in host == nil }
        try await waitUntil { server.count("/square") == 1 }
        window.rootViewController = nil
        try await CatalogImageCache.clear(manager.cache)
        try await Task.sleep(for: .milliseconds(1_200))
        XCTAssertTrue(hostWasReleased())
        XCTAssertFalse(manager.cache.isCached(forKey: square.cacheKey))
    }

    func testFailedDiskRemovalCanBeRetried() async throws {
        let cache = ImageCache(name: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache.diskStorage.directoryURL) }
        let configuration = cache.diskStorage.config
        try cache.diskStorage.store(value: Data([1, 2, 3]), forKey: "image")
        cache.diskStorage.config = .init(name: configuration.name, sizeLimit: configuration.sizeLimit,
                                         fileManager: RefusingRemovalFileManager())
        do {
            try await CatalogImageCache.clear(cache)
            XCTFail("Clearing should report that the image is still on disk")
        } catch CatalogImageCache.ClearError.imagesRemainOnDisk {}
        cache.diskStorage.config = configuration
        XCTAssertTrue(cache.diskStorage.isCached(forKey: "image"))
        try await CatalogImageCache.clear(cache)
        let bytes = try await cache.diskStorageSize
        XCTAssertEqual(bytes, 0)
    }

    private func makeManager(for server: AuthenticationHTTPStub) throws -> KingfisherManager {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthenticationURLProtocol.self]
        let downloader = ImageDownloader(name: server.host)
        downloader.sessionConfiguration = configuration
        let cache = try ImageCache(name: server.host, cacheDirectoryURL: FileManager.default.temporaryDirectory)
        return KingfisherManager(downloader: downloader, cache: cache)
    }

    private func show(_ view: some View) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        return window
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), file: file, line: line)
    }
}

nonisolated private final class RefusingRemovalFileManager: FileManager, @unchecked Sendable {
    override func removeItem(at url: URL) throws { throw CocoaError(.fileWriteNoPermission) }
}
