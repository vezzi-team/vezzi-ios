import ActivityKit
import Combine
import Kingfisher
import OSLog
import UIKit

private extension ShoppingTrip {
    var activityStore: CatalogStore? {
        guard pendingFinish == nil else { return nil }
        switch page {
        case .route(let id), .store(let id), .editStore(let id):
            return plan.stops.first { $0.id == id }?.store
        case .returnHome, .summary:
            return nil
        }
    }
}

extension ShoppingActivityAttributes.ContentState {
    init(trip: ShoppingTrip) {
        let stage: ShoppingActivityAttributes.Stage
        if trip.pendingFinish != nil {
            stage = .finishing
        } else {
            switch trip.page {
            case .route: stage = .walking
            case .store, .editStore: stage = .shopping
            case .returnHome: stage = .returning
            case .summary: stage = .summary
            }
        }
        let store = trip.activityStore
        let name = [store?.chainName, store?.name].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        self.init(stage: stage, storeID: store?.id, storeName: name.map { String($0.unicodeScalars.prefix(100)) },
                  bought: trip.boughtCount, total: trip.items.count, spent: trip.spent)
    }
}

/// Serializes system writes and coalesces new trip snapshots while an update is in flight.
@MainActor
final class ShoppingLiveActivity {
    private typealias LiveActivity = Activity<ShoppingActivityAttributes>
    private let list: ShoppingListRepository
    private let authentication: AuthenticationSession
    private let defaults: UserDefaults
    private let requestKey = "shopping.lastRequestedLiveActivity"
    private var observation: AnyCancellable?
    private var logoObservation: AnyCancellable?
    private var logoTask: Task<Void, Never>?
    private var logoURL: URL?
    private var logoData: Data?
    private var isUpdating = false
    private var needsUpdate = false

    init(list: ShoppingListRepository, authentication: AuthenticationSession,
         catalog: any CatalogRepository, defaults: UserDefaults = .standard) {
        self.list = list
        self.authentication = authentication
        self.defaults = defaults
        observation = Publishers.Merge4(list.$trip.map { _ in () }, list.$account.map { _ in () },
                                        list.$hasVerifiedPlanStatus.map { _ in () }, authentication.$isRestoring.map { _ in () })
            .sink { [weak self] in self?.refresh() }
        let urls = list.$trip.map { $0?.activityStore }.removeDuplicates()
            .map { store -> AnyPublisher<URL?, Never> in
                guard let store else { return Just(nil).eraseToAnyPublisher() }
                return catalog.observeStoreLogoURLs().map { $0[store.id] ?? store.logoURL }
                    .prepend(store.logoURL).eraseToAnyPublisher()
            }
            .switchToLatest().removeDuplicates()
        logoObservation = urls.combineLatest(catalog.networkAvailable.removeDuplicates())
            .sink { [weak self] url, connected in self?.loadLogo(url, retry: connected) }
    }

    nonisolated deinit { logoTask?.cancel() }

    private func loadLogo(_ url: URL?, retry: Bool) {
        guard logoURL != url || (retry && url != nil && logoData == nil) else { return }
        logoTask?.cancel()
        logoURL = url
        logoData = nil
        refresh()
        guard let url else { return }
        logoTask = Task { [weak self] in
            let thumbnail = try? await Self.loadThumbnail(for: url, cache: CatalogImageCache.shared)
            guard !Task.isCancelled, let thumbnail else { return }
            self?.logoData = thumbnail
            self?.refresh()
        }
    }

    static func loadThumbnail(for url: URL, cache: ImageCache,
                              manager: KingfisherManager = .shared) async throws -> Data? {
        let options: KingfisherOptionsInfo = [.targetCache(cache), .scaleFactor(1), .backgroundDecode]
        let image: UIImage
        do {
            image = try await manager.retrieveImage(with: url, options: options + [.processor(CatalogImageCache.logoProcessor)]).image
        } catch {
            try Task.checkCancellation()
            image = try await manager.retrieveImage(with: url, options: options + [
                .processor(CatalogImageCache.legacyLogoProcessor), .onlyFromCache
            ]).image
        }
        try Task.checkCancellation()
        return thumbnail(image)
    }

    // ActivityKit allows 4 KB for the whole payload. Leave room for base64, the name and trip metrics.
    static func thumbnail(_ image: UIImage) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        for side: CGFloat in [48, 32] {
            let canvas = CGRect(x: 0, y: 0, width: side, height: side)
            let scale = min(side / image.size.width, side / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let icon = UIGraphicsImageRenderer(size: canvas.size, format: format).image { context in
                UIColor.white.setFill()
                context.fill(canvas)
                image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                      width: size.width, height: size.height))
            }
            if let data = icon.pngData(), data.count <= 1800 { return data }
            if let data = icon.jpegData(compressionQuality: 0.72), data.count <= 1800 { return data }
        }
        return nil
    }

    func refresh() {
        needsUpdate = true
        guard !isUpdating else { return }
        isUpdating = true
        // @Published notifies before assignment. Read a coherent snapshot on the next actor turn.
        Task { [weak self] in
            guard let self else { return }
            while needsUpdate {
                needsUpdate = false
                await reconcile()
            }
            isUpdating = false
        }
    }

    private func reconcile() async {
        guard !authentication.isRestoring || list.account != nil else { return }
        let session = list.account?.sessionID
        let trip = list.trip
        let activities = LiveActivity.activities
        // A disk snapshot can predate the trip already displayed on the Lock Screen.
        let awaitingPlan = session != nil && !list.hasVerifiedPlanStatus && (trip == nil || activities.contains {
            $0.attributes.sessionID == session && $0.attributes.planID != trip?.plan.id
        })
        var current: LiveActivity?
        for activity in activities {
            if activity.attributes.sessionID == session {
                if awaitingPlan { continue }
                if activity.attributes.planID == trip?.plan.id, current == nil {
                    current = activity
                    continue
                }
            }
            await activity.end(nil, dismissalPolicy: .immediate)
            if needsUpdate { return }
        }
        guard !awaitingPlan else { return }
        guard let session, let trip else {
            defaults.removeObject(forKey: requestKey)
            return
        }
        var state = ShoppingActivityAttributes.ContentState(trip: trip)
        if state.storeID != nil {
            state.storeLogo = logoData
            if state.storeLogo == nil, logoURL != nil, current?.content.state.storeID == state.storeID {
                state.storeLogo = current?.content.state.storeLogo
            }
        }
        let content = ActivityContent(state: state, staleDate: nil)
        if let current {
            if current.content.state != state { await current.update(content) }
            return
        }
        let key = session.uuidString + "/" + trip.plan.id.uuidString
        // Respect a dismissal from the Lock Screen, including after relaunch.
        guard defaults.string(forKey: requestKey) != key, ActivityAuthorizationInfo().areActivitiesEnabled,
              UIApplication.shared.applicationState == .active else { return }
        do {
            _ = try LiveActivity.request(attributes: .init(sessionID: session, planID: trip.plan.id),
                                         content: content, pushType: nil)
            defaults.set(key, forKey: requestKey)
        } catch {
            Logger(subsystem: "vezzi.vezzi-ios", category: "ShoppingActivity").error("Could not start shopping Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }
}
