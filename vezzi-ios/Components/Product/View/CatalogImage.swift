import Combine
import Kingfisher
import SwiftUI

/// A failed view can also catch a reconnect that happened while its request was finishing.
final class CatalogImageRetries: ObservableObject {
    let revision = CurrentValueSubject<Int, Never>(0)
    private var observation: AnyCancellable?

    init(catalog: any CatalogRepository) {
        let connections = catalog.networkAvailable.removeDuplicates().dropFirst().filter { $0 }
        let refreshes = catalog.status.map(\.isRefreshing).removeDuplicates().dropFirst().filter { $0 }
        observation = Publishers.Merge(connections, refreshes).sink { [revision] _ in
            revision.send(revision.value &+ 1)
        }
    }

    nonisolated deinit {}
}

extension EnvironmentValues {
    @Entry var catalogImageRetries: CatalogImageRetries?
    @Entry var catalogImageCache = CatalogImageCache.shared
    @Entry var catalogImageDownloader = ImageDownloader.default
}

/// Product artwork and store logos share downloads and a bounded memory and disk cache.
struct CatalogImage: View {
    let url: URL?
    var fallbackURL: URL?
    enum Usage { case artwork, card(width: CGFloat), logo }
    var usage: Usage = .artwork
    var shimmerStyle: ShimmerStyle = .standard
    var showsLoadingShimmer = true
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.catalogImageRetries) private var retries
    @Environment(\.catalogImageCache) private var cache
    @Environment(\.catalogImageDownloader) private var downloader
    @State private var attempt = 0

    var body: some View {
        if let url {
            let revision = retries?.revision.value ?? 0
            load(image(for: url)) {
                if let fallbackURL, fallbackURL != url {
                    load(image(for: fallbackURL)) { retryOnRefresh(since: revision, content: placeholder) }
                } else if case .logo = usage {
                    // Existing installations can still show their previously cached logo offline.
                    let cached = KFImage(url).setProcessor(CatalogImageCache.legacyLogoProcessor).onlyFromCache()
                    retryOnRefresh(since: revision, content: load(cached, shimmer: false) { placeholder })
                } else {
                    retryOnRefresh(since: revision, content: placeholder)
                }
            }
            .id(fallbackURL)
            .id(attempt)
            .background(placeholder)
            .accessibilityHidden(true)
        } else {
            placeholder.accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func retryOnRefresh(since revision: Int, content: some View) -> some View {
        if let retries {
            content.onReceive(retries.revision) { current in
                if current != revision { attempt = current }
            }
        } else {
            content
        }
    }

    private func load<Failure: View>(_ image: KFImage, shimmer: Bool = true,
                                     @ViewBuilder onFailure: @escaping () -> Failure) -> some View {
        image
            .targetCache(cache)
            .downloader(downloader)
            .loadDiskFileSynchronously(false)
            .asyncCacheTypeCheck()
            .cancelOnDisappear(true)
            .placeholder { placeholder.shimmer(isActive: showsLoadingShimmer && shimmer, style: shimmerStyle) }
            .onFailureView(onFailure)
            .fade(duration: reduceMotion ? 0 : Const.fadeDuration)
            .resizable()
            .contentConfigure { image in
                image.scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.Label.white)
            }
    }

    private enum Const {
        static let fadeDuration: TimeInterval = 0.18
    }

    private var placeholder: Color {
        shimmerStyle == .lighter ? Color.Background.placeholderLighter : Color.Background.placeholder
    }

    private func image(for url: URL) -> KFImage {
        let image = KFImage(url)
        switch usage {
        case .artwork:
            return image.serialize(by: CatalogImageCache.artworkSerializer)
                .scaleFactor(displayScale)
                .backgroundDecode()
        case .card(let width):
            // Only the original is stored on disk, so other widths and details work offline.
            return image.setProcessor(CatalogImageCache.cardProcessor(width: width, displayScale: displayScale))
                .scaleFactor(1)
                .cacheMemoryOnly()
                .cacheOriginalImage()
        case .logo:
            return image.setProcessor(CatalogImageCache.logoProcessor)
                .scaleFactor(1)
                .backgroundDecode()
        }
    }
}

struct StoreLogo: View {
    let url: URL?
    var style: ShimmerStyle = .standard

    var body: some View {
        CatalogImage(url: url, usage: .logo, shimmerStyle: style)
            .clipShape(.circle)
    }
}
