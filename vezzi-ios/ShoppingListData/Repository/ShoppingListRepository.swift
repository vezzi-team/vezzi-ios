import Combine
import Foundation

/// One serial writer for the current account's active cart. Catalog storage remains independent.
@MainActor
final class ShoppingListRepository: ObservableObject {
    @Published private(set) var cart: ShoppingCart?
    @Published private(set) var hasResolvedCart = false
    @Published private(set) var planResult: ShoppingPlanResult?
    @Published private(set) var trip: ShoppingTrip?
    /// A cached cart can be available before the server confirms which plan is active.
    @Published private(set) var hasVerifiedPlanStatus = false
    @Published var showsDeletedCartNotice = false
    @Published private var isStartingTrip = false
    @Published private(set) var tripFailure: ShoppingListFailure?
    @Published private(set) var isBusy = false
    @Published private(set) var failure: ShoppingListFailure?
    @Published private(set) var account: ShoppingListAccount?
    var accountID: String? { account?.id }
    @Published private(set) var hasCacheFailure = false
    @Published private(set) var isPlanCached = false
    @Published private(set) var origin = ShoppingCoordinate.defaultOrigin
    @Published private(set) var originAddress: String?
    @Published private(set) var routeOptions = ShoppingRouteOptions()
    let selection: ProductSelection

    private let service: (any ShoppingListService)?
    private let cache: (any ShoppingListCache)?
    private let addressResolver: (any AddressResolving)?
    private var addressTask: Task<Void, Never>?
    private var addressRevision = UUID()
    private var cachedPlan: CachedShoppingPlan?
    private var hasMovedBeforeCacheLoad = false
    private var needsCacheLoad = true
    private var locallyEditedBeforeCacheLoad: [ShoppingCartEditTarget: Set<String>] = [:]
    private var cacheAccessFailed = false {
        didSet { updateCacheFailure() }
    }
    private var pendingCacheRemovals: Set<ShoppingListAccount> = []
    private var failedCacheRemovals: Set<ShoppingListAccount> = [] {
        didSet { updateCacheFailure() }
    }
    private var cacheRevision = UUID()
    private var cacheTask: Task<Void, Never>?
    private var pending: [ShoppingCartEditTarget: [String: Int]] = [:]
    private var previousQuantities: [String: Int] = [:]
    private var applyingRemote = false
    private var needsReload = true
    private var needsActiveCartResolution = true
    private var needsPlan = true
    private var isPresented = false
    private var isConnected = true
    private var connectionRevision = 0
    private var generation = UUID()
    private var revision = 0
    private var hasEditedRoute = false
    private var worker: Task<Void, Never>?
    private var observation: AnyCancellable?

    init(service: (any ShoppingListService)? = nil, selection: ProductSelection? = nil,
         cache: (any ShoppingListCache)? = nil, addressResolver: (any AddressResolving)? = nil) {
        self.service = service
        self.cache = cache
        self.addressResolver = addressResolver
        let selection = selection ?? ProductSelection()
        self.selection = selection
        previousQuantities = selection.quantities
        observation = selection.$quantities.dropFirst().sink { [weak self] values in
            self?.quantitiesChanged(values)
        }
        startAddressLookup()
    }

    nonisolated deinit { addressTask?.cancel() }

    func setAccount(_ account: ShoppingListAccount?) {
        guard self.account != account else { return }
        let previousAccount = self.account
        let guestQuantities = accountID == nil ? selection.quantities : [:]
        let guestRoute = accountID == nil && hasEditedRoute ? (origin, routeOptions, originAddress) : nil
        generation = UUID()
        worker?.cancel()
        worker = nil
        self.account = account
        showsDeletedCartNotice = false
        trip = nil
        hasVerifiedPlanStatus = false
        isStartingTrip = false
        tripFailure = nil
        selection.isShopping = false
        cart = nil
        hasResolvedCart = false
        planResult = nil
        cachedPlan = nil
        isPlanCached = false
        origin = guestRoute?.0 ?? .defaultOrigin
        replaceOriginAddress(guestRoute?.2)
        routeOptions = guestRoute?.1 ?? .init()
        hasEditedRoute = guestRoute != nil
        cacheAccessFailed = false
        failure = nil
        isBusy = false
        pending = account == nil || guestQuantities.isEmpty ? [:] : [.active: guestQuantities]
        locallyEditedBeforeCacheLoad = [.active: Set(guestQuantities.keys)]
        needsReload = true
        needsActiveCartResolution = true
        needsPlan = true
        needsCacheLoad = true
        hasMovedBeforeCacheLoad = false
        cacheRevision = UUID()
        if cache != nil, let previousAccount { pendingCacheRemovals.insert(previousAccount) }
        retryCacheRemovals()
        applyQuantities(account == nil ? [:] : guestQuantities)
        startWorker()
        startAddressLookup()
    }

    func setPresented(_ presented: Bool) {
        isPresented = presented
        if presented { startWorker() }
    }

    func setOrigin(_ coordinate: ShoppingCoordinate) {
        setRoute(origin: coordinate, options: routeOptions)
    }

    func setRoute(origin coordinate: ShoppingCoordinate, options: ShoppingRouteOptions, address: String? = nil) {
        guard coordinate.isValid, options.isValid else { return }
        // Explicit confirmation takes precedence over a late cache read, even without changes.
        hasEditedRoute = true
        let routeChanged = coordinate != origin || options != routeOptions
        if coordinate != origin || address != nil { replaceOriginAddress(address) }
        origin = coordinate
        routeOptions = options
        startAddressLookup()
        guard routeChanged else {
            saveCache()
            return
        }
        revision += 1
        invalidatePlan()
        saveCache()
        // Do not cancel an in-flight POST: let the serial worker reject it and calculate again.
        startWorker()
    }

    // The resolved label belongs to this exact origin, independently of plan calculations.
    private func replaceOriginAddress(_ address: String?) {
        addressTask?.cancel()
        addressTask = nil
        addressRevision = UUID()
        let value = address?.trimmingCharacters(in: .whitespacesAndNewlines)
        originAddress = value?.isEmpty == false ? value : nil
    }

    private func startAddressLookup() {
        guard originAddress == nil, addressTask == nil, let addressResolver else { return }
        let point = origin
        let revision = addressRevision
        addressTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let address = try? await addressResolver.address(for: point)
            guard !Task.isCancelled, let self, self.addressRevision == revision, self.origin == point else { return }
            self.addressTask = nil
            self.replaceOriginAddress(address)
            self.saveCache()
        }
    }

    func updateConnectivity(isConnected: Bool) {
        guard self.isConnected != isConnected else { return }
        self.isConnected = isConnected
        if isConnected {
            connectionRevision += 1
            startWorker()
            startAddressLookup()
        } else if accountID != nil {
            // Reload before sending pending edits, but let requests determine reachability.
            needsReload = true
        }
    }

    func refresh() async {
        startAddressLookup()
        needsReload = true
        // A failed refresh must not discard a calculation for the unchanged cart.
        needsPlan = true
        retryCacheRemovals()
        saveCache()
        startWorker()
        await worker?.value
        await cacheTask?.value
    }

    private func quantitiesChanged(_ values: [String: Int]) {
        defer { previousQuantities = values }
        guard !applyingRemote else { return }
        let target = cart.map { ShoppingCartEditTarget.cart($0.id) } ?? .active
        for id in Set(previousQuantities.keys).union(values.keys) where previousQuantities[id] != values[id] {
            pending[target, default: [:]][id] = values[id, default: 0]
            // Keep newer intent even if the server acknowledges it before disk recovers.
            if needsCacheLoad { locallyEditedBeforeCacheLoad[target, default: []].insert(id) }
        }
        revision += 1
        invalidatePlan()
        saveCache()
        startWorker(debounce: true)
    }

    private func invalidatePlan() {
        planResult = nil
        cachedPlan = nil
        isPlanCached = false
        needsPlan = true
    }

    private func startWorker(debounce: Bool = false, newlyConfirmedPlan: UUID? = nil) {
        guard worker == nil, !isStartingTrip, accountID != nil, service != nil || cache != nil,
              needsCacheLoad || needsReload || !pending.isEmpty || trip?.needsSync == true ||
                (trip == nil && isPresented && needsPlan && !selection.quantities.isEmpty) else { return }
        isBusy = true
        failure = nil
        let generation = generation
        worker = Task { [weak self] in
            if debounce { try? await Task.sleep(for: .milliseconds(300)) }
            guard let self, !Task.isCancelled else { return }
            await self.synchronize(generation: generation, newlyConfirmedPlan: newlyConfirmedPlan)
        }
    }

    private func synchronize(generation: UUID, newlyConfirmedPlan: UUID?) async {
        let connectionRevision = connectionRevision
        defer {
            if self.generation == generation {
                worker = nil
                isBusy = false
                // A reconnect received during a failing request must not be lost.
                if failure != nil, isConnected, self.connectionRevision != connectionRevision {
                    startWorker()
                }
            }
        }
        do {
            try await restoreCache(generation: generation)
            guard let service else { return }
            if cacheAccessFailed { saveCache() }
            var mutationCart: ShoppingCart?
            var unavailableCarts: Set<UUID> = []
            while true {
                try check(generation)
                if trip?.needsSync == true, let progress = service as? any ShoppingProgressService {
                    try await synchronizeTrip(service: progress, generation: generation, newlyConfirmedPlan: newlyConfirmedPlan)
                    continue
                }
                if needsReload {
                    let progress = service as? any ShoppingProgressService
                    let preferredID = needsActiveCartResolution ? trip?.cartID : cart?.id
                    let (loaded, restoredPlan) = try await loadCartAndPlan(preferredID: preferredID, service: service, generation: generation)
                    try check(generation)
                    // Taps on the cached trip take priority over in-flight reads.
                    if trip?.needsSync == true, progress != nil { continue }
                    cart = loaded
                    if let loaded, let restoredPlan {
                        acceptActivePlan(restoredPlan, cartID: loaded.id)
                    } else if progress != nil || loaded == nil {
                        clearVerifiedTrip()
                    } else if trip?.cartID != loaded?.id {
                        trip = nil
                        selection.isShopping = false
                    }
                    hasResolvedCart = true
                    needsActiveCartResolution = false
                    if let cart {
                        bindGuestEdits(to: cart.id)
                        if unavailableCarts.remove(cart.id) != nil, unavailableCarts.isEmpty { failure = nil }
                    }
                    mutationCart = nil
                    if let cachedPlan, cart.map({ cachedPlan.matches($0) }) != true || hasCurrentPendingEdits {
                        invalidatePlan()
                    }
                    needsReload = false
                    reconcileSelection()
                    saveCache()
                }
                if cart == nil && pending[.active, default: [:]].values.contains(where: { $0 > 0 }) {
                    await cacheTask?.value
                    try check(generation)
                    let created = try await service.createCart(name: Texts.ShoppingList.title)
                    try check(generation)
                    cart = created
                    bindGuestEdits(to: created.id)
                    mutationCart = created
                    reconcileSelection()
                    saveCache()
                }
                if cart == nil, pending[.active] != nil {
                    pending[.active] = nil
                    saveCache()
                }
                if let cartID = nextPendingCart(excluding: unavailableCarts) {
                    do {
                        mutationCart = try await synchronizeNextEdit(in: cartID, knownCart: mutationCart,
                                                                     service: service, generation: generation)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        try check(generation)
                        let cause = ShoppingListFailure.from(error)
                        // A different cart's conflict must not block this cart's edits or calculation.
                        // Connectivity and authentication failures still stop the shared worker.
                        guard cartID != cart?.id, cause != .authenticationRequired, cause != .offline else { throw error }
                        unavailableCarts.insert(cartID)
                        mutationCart = nil
                        failure = cause == .cartUnavailable || (error as? APIError)?.status == 404
                            ? .cartUnavailable : .otherCartSyncFailed
                    }
                    continue
                }
                guard trip == nil, isPresented, needsPlan, !hasCurrentPendingEdits, let cart, !cart.items.isEmpty else { return }
                let plannedRevision = revision
                let plannedOrigin = origin
                let plannedOptions = routeOptions
                let result: ShoppingPlanResult
                do {
                    result = try await service.plans(cartID: cart.id, start: plannedOrigin, options: plannedOptions)
                } catch where plannedRevision != revision {
                    // A failed calculation for an earlier cart or route must not stop its replacement.
                    continue
                }
                try check(generation)
                // Plan requests are serialized with cart writes; an old POST cannot replace a newer calculation.
                guard plannedRevision == revision, !needsReload else { continue }
                for plan in result.rankedPlans {
                    let quantities = Dictionary(plan.stops.flatMap(\.items).map { ($0.product.id, $0.quantity) },
                                                uniquingKeysWith: +)
                    guard quantities == cart.quantities else { throw APIError.invalidResponse }
                }
                cachedPlan = CachedShoppingPlan(cartID: cart.id, quantities: cart.quantities, origin: plannedOrigin,
                                               calculatedAt: Date(), result: result, routeOptions: plannedOptions)
                isPlanCached = false
                planResult = result
                needsPlan = false
                saveCache()
                return
            }
        } catch is CancellationError {
            // The account changed; its replacement worker owns presentation state.
        } catch {
            guard self.generation == generation else { return }
            // POST /items adds quantities. Always reload before retrying an ambiguous response.
            needsReload = true
            failure = ShoppingListFailure.from(error)
            if trip?.pendingFinish != nil, failure != .offline { tripFailure = failure }
            isPlanCached = planResult != nil
        }
    }

    private func loadCartAndPlan(preferredID: UUID?, service: any ShoppingListService,
                                 generation: UUID) async throws -> (ShoppingCart?, ShoppingPlan?) {
        let progress = service as? any ShoppingProgressService
        var checkedCartID: UUID?
        if let preferredID {
            let preferred: ShoppingCart?
            do { preferred = try await service.cart(id: preferredID) }
            catch let error as APIError where error.status == 404 { preferred = nil }
            try check(generation)
            if let preferred {
                guard preferred.id == preferredID else { throw APIError.invalidResponse }
                if preferred.status == "active" {
                    let plan = try await progress?.activePlan(cartID: preferredID)
                    try check(generation)
                    if !needsActiveCartResolution || plan != nil || progress == nil { return (preferred, plan) }
                    // The saved cart exists but its trip ended. Resolve the account's current cart.
                    checkedCartID = preferredID
                }
            }
        }
        guard let latest = try await service.activeCart(), latest.status == "active" else { return (nil, nil) }
        try check(generation)
        guard checkedCartID != latest.id, let progress else { return (latest, nil) }
        do { return (latest, try await progress.activePlan(cartID: latest.id)) }
        catch {
            try check(generation)
            if cart == nil, trip == nil {
                // The cart remains usable offline even when the subsequent progress request fails.
                cart = latest
                hasResolvedCart = true
                reconcileSelection()
                saveCache()
            }
            throw error
        }
    }

    // MARK: - Account cache

    private func restoreCache(generation: UUID) async throws {
        guard needsCacheLoad, let account else { return }
        // Finish the previous account's writes/removal before reading this account.
        await cacheTask?.value
        try check(generation)
        // Never restore discarded edits while a logout cleanup is still failing.
        guard !pendingCacheRemovals.contains(account) else { return }
        let snapshot: ShoppingListCacheSnapshot?
        do {
            snapshot = try await cache?.load(account: account)
            try check(generation)
            try snapshot?.validate()
        } catch {
            try check(generation)
            cacheAccessFailed = true
            return
        }
        if let snapshot {
            if !hasEditedRoute, origin != snapshot.origin || routeOptions != snapshot.routeOptions {
                if origin != snapshot.origin { replaceOriginAddress(snapshot.originAddress) }
                origin = snapshot.origin
                routeOptions = snapshot.routeOptions
                revision += 1
                // Cache recovery may follow a server calculation made from the fallback origin.
                invalidatePlan()
            }
            if !hasEditedRoute, originAddress == nil, let address = snapshot.originAddress {
                replaceOriginAddress(address)
            }
            try await restoreTripAndCart(from: snapshot, generation: generation)
            try check(generation)
            // New edits and acknowledged intent only mask older edits for the same cart.
            for (target, edits) in snapshot.pending {
                var editedIDs = locallyEditedBeforeCacheLoad[target, default: []]
                if target == .active, !needsActiveCartResolution, let cart {
                    // Older unbound edits will join this cart; confirmed edits on it still win.
                    editedIDs.formUnion(locallyEditedBeforeCacheLoad[.cart(cart.id), default: []])
                }
                let restored = edits.filter { !editedIDs.contains($0.key) }
                let merged = restored.merging(pending[target, default: [:]]) { _, latest in latest }
                if !merged.isEmpty { pending[target] = merged }
            }
            if let cart, trip != nil || !needsActiveCartResolution { bindGuestEdits(to: cart.id) }
            if hasCurrentPendingEdits { invalidatePlan() }
            if !pending.isEmpty { needsReload = true }
            reconcileSelection()
            if trip == nil, !hasCurrentPendingEdits, planResult == nil, let saved = snapshot.plan,
               saved.origin == origin, saved.routeOptions == routeOptions, cart.map({ saved.matches($0) }) == true {
                cachedPlan = saved
                isPlanCached = true
                planResult = saved.result
            }
        }
        needsCacheLoad = false
        locallyEditedBeforeCacheLoad = [:]
        cacheAccessFailed = false
        startAddressLookup()
        saveCache()
    }

    /// Preserve a newer server cart unless the recovered snapshot owns an active or unfinished trip.
    private func restoreTripAndCart(from snapshot: ShoppingListCacheSnapshot, generation: UUID) async throws {
        if needsActiveCartResolution {
            cart = snapshot.cart
            hasResolvedCart = snapshot.hasResolvedCart
            trip = snapshot.trip
            selection.isShopping = trip != nil
        } else if let saved = snapshot.trip, saved.cartID == cart?.id {
            // Keep the freshly loaded plan and overlay the durable navigation and user intent.
            if var current = trip, current.plan.id == saved.plan.id {
                if !hasMovedBeforeCacheLoad, current.contains(saved.page) { current.page = saved.page }
                current.pendingMarks = (saved.pendingMarks ?? [:]).merging(current.pendingMarks ?? [:]) { _, local in local }
                current.pendingFinish = saved.pendingFinish ?? current.pendingFinish
                try current.applyPendingMarks()
                trip = current
            } else if trip == nil, saved.needsSync {
                trip = saved
                selection.isShopping = true
            }
        } else if let saved = snapshot.trip, trip == nil, let progress = service as? any ShoppingProgressService {
            // A temporary disk failure may have let the ordinary cart load first.
            // Verify the old trip before replacing that cart. Pending completion verifies itself.
            let resume: Bool
            if saved.pendingFinish != nil { resume = true }
            else {
                do { resume = try await progress.activePlan(cartID: saved.cartID)?.id == saved.plan.id }
                catch let error as APIError where error.status == 404 { resume = false }
                try check(generation)
            }
            if resume {
                cart = snapshot.cart
                trip = saved
                selection.isShopping = true
                invalidatePlan()
                needsReload = true
            }
        }
    }

    private func saveCache() {
        guard !needsCacheLoad, let cache, let account else { return }
        let previous = cacheTask
        let generation = generation
        cacheRevision = UUID()
        let cacheRevision = cacheRevision
        cacheTask = Task { [weak self] in
            await previous?.value
            guard let self, self.generation == generation, self.cacheRevision == cacheRevision else { return }
            // Coalesce queued writes and read the newest values when the writer is ready.
            let snapshot = ShoppingListCacheSnapshot(cart: self.cart, pending: self.pending, plan: self.cachedPlan,
                                                     hasResolvedCart: self.hasResolvedCart, origin: self.origin,
                                                     routeOptions: self.routeOptions, originAddress: self.originAddress, trip: self.trip)
            do {
                try await cache.save(snapshot, account: account)
                if self.generation == generation { self.cacheAccessFailed = false }
            } catch {
                if self.generation == generation { self.cacheAccessFailed = true }
            }
        }
    }

    private func retryCacheRemovals() {
        guard let cache, !pendingCacheRemovals.isEmpty else { return }
        let accounts = pendingCacheRemovals.sorted { $0.sessionID.uuidString < $1.sessionID.uuidString }
        let previous = cacheTask
        cacheTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            for account in accounts where self.pendingCacheRemovals.contains(account) {
                do {
                    try await cache.remove(account: account)
                    self.pendingCacheRemovals.remove(account)
                    self.failedCacheRemovals.remove(account)
                } catch {
                    // Keep the account blocked from cache reads until a later retry succeeds.
                    self.failedCacheRemovals.insert(account)
                }
            }
        }
    }

    private func updateCacheFailure() {
        let failed = cacheAccessFailed || !failedCacheRemovals.isEmpty
        if hasCacheFailure != failed { hasCacheFailure = failed }
    }

    // MARK: - Cart-bound edits

    private var hasCurrentPendingEdits: Bool {
        pending[.active] != nil || cart.map { pending[.cart($0.id)] != nil } == true
    }

    private func synchronizeNextEdit(in cartID: UUID, knownCart: ShoppingCart?,
                                     service: any ShoppingListService, generation: UUID) async throws -> ShoppingCart {
        let target: ShoppingCart
        if let knownCart, knownCart.id == cartID { target = knownCart }
        else if let cart, cart.id == cartID { target = cart }
        else { target = try await service.cart(id: cartID) }
        try check(generation)
        guard target.id == cartID else { throw APIError.invalidResponse }
        guard target.status == "active" else { throw ShoppingListFailure.cartUnavailable }
        guard let entry = nextPendingItem(in: cartID) else { return target }
        let exists = target.quantities[entry.key] != nil
        if target.quantities[entry.key, default: 0] == entry.value {
            acknowledge(entry, in: cartID)
            saveCache()
            return target
        }
        if entry.value > 0 && !exists && target.items.count >= ProductSelection.maximumProductCount {
            throw ShoppingListFailure.limit
        }
        // Persist absolute edits before a potentially ambiguous POST response.
        await cacheTask?.value
        try check(generation)
        let updated = try await service.updateItem(cartID: cartID, productID: entry.key,
                                                  quantity: entry.value, exists: exists)
        try check(generation)
        guard updated.id == cartID else { throw APIError.invalidResponse }
        if cart?.id == cartID { cart = updated }
        acknowledge(entry, in: cartID)
        reconcileSelection()
        saveCache()
        return updated
    }

    private func bindGuestEdits(to cartID: UUID) {
        guard let edits = pending.removeValue(forKey: .active) else { return }
        let target = ShoppingCartEditTarget.cart(cartID)
        pending[target] = pending[target, default: [:]].merging(edits) { _, guest in guest }
        if needsCacheLoad {
            // Only the edits bound now may mask this cart's older disk values.
            let guestKeys = locallyEditedBeforeCacheLoad[.active, default: []].intersection(edits.keys)
            locallyEditedBeforeCacheLoad[target, default: []].formUnion(guestKeys)
        }
    }

    private func nextPendingCart(excluding unavailable: Set<UUID>) -> UUID? {
        pending.keys.compactMap { target -> UUID? in
            guard case let .cart(id) = target, id != trip?.cartID, !unavailable.contains(id) else { return nil }
            return id
        }.min { $0.uuidString < $1.uuidString }
    }

    private func nextPendingItem(in cartID: UUID) -> (key: String, value: Int)? {
        pending[.cart(cartID), default: [:]].sorted {
            if ($0.value == 0) != ($1.value == 0) { return $0.value == 0 }
            return $0.key < $1.key
        }.first
    }

    private func acknowledge(_ entry: (key: String, value: Int), in cartID: UUID) {
        let target = ShoppingCartEditTarget.cart(cartID)
        // A newer local edit takes precedence over this response.
        if pending[target]?[entry.key] == entry.value { pending[target]?[entry.key] = nil }
        if pending[target]?.isEmpty == true { pending[target] = nil }
    }

    private func reconcileSelection() {
        if let trip {
            applyQuantities(Dictionary(trip.items.map { ($0.product.id, $0.quantity) }, uniquingKeysWith: +))
            return
        }
        var values = cart?.quantities ?? [:]
        let bound = cart.map { pending[.cart($0.id), default: [:]] } ?? [:]
        for (id, quantity) in bound.merging(pending[.active, default: [:]], uniquingKeysWith: { _, guest in guest }) {
            values[id] = quantity == 0 ? nil : quantity
        }
        applyQuantities(values)
    }

    private func applyQuantities(_ values: [String: Int]) {
        applyingRemote = true
        selection.replaceQuantities(values)
        previousQuantities = values
        applyingRemote = false
    }

    private func check(_ generation: UUID) throws {
        try Task.checkCancellation()
        guard self.generation == generation else { throw CancellationError() }
    }
}

extension ShoppingListRepository {
    func canStartTrip(_ id: UUID) -> Bool {
        account != nil && trip == nil && !isBusy && !isStartingTrip && !hasCurrentPendingEdits &&
            planResult?.rankedPlans.contains { $0.id == id } == true
    }

    func moveTrip(to page: ShoppingTrip.Page) {
        guard trip?.contains(page) == true, trip?.page != page else { return }
        if needsCacheLoad { hasMovedBeforeCacheLoad = true }
        trip?.page = page
        saveCache()
    }

    func clearTripFailure() { tripFailure = nil }

    @discardableResult
    func togglePurchase(itemID: Int64, planID: UUID) -> Bool {
        guard var current = trip, current.plan.id == planID, current.togglePurchase(itemID: itemID) else { return false }
        trip = current
        saveCache()
        startWorker()
        return true
    }

    /// The cart worker must never recalculate (and replace) the plan being activated.
    @discardableResult
    func startTrip(_ id: UUID) async -> Bool {
        guard canStartTrip(id), let progress = service as? any ShoppingProgressService, let cart else { return false }
        let generation = generation
        isStartingTrip = true
        selection.isShopping = true
        tripFailure = nil
        defer {
            if self.generation == generation {
                isStartingTrip = false
                selection.isShopping = trip != nil
                startWorker()
            }
        }
        do {
            let plan = try await progress.startPlan(id: id, cartID: cart.id)
            try check(generation)
            acceptActivePlan(plan, cartID: cart.id, startedHere: true)
            saveCache()
            return true
        } catch {
            guard self.generation == generation else { return false }
            tripFailure = ShoppingListFailure.from(error)
            needsReload = true
            if let status = (error as? APIError)?.status, [404, 409].contains(status) { needsPlan = true }
            return false
        }
    }

    @discardableResult
    func finishShopping(_ choice: ShoppingTrip.ListDisposition) async -> Bool {
        guard let current = trip, current.cartID == cart?.id, service is any ShoppingProgressService,
              current.pendingFinish == nil || current.pendingFinish == choice else { return false }
        let generation = generation
        tripFailure = nil
        trip?.pendingFinish = choice
        saveCache()
        startWorker(newlyConfirmedPlan: current.pendingFinish == nil ? current.plan.id : nil)
        await worker?.value
        return self.generation == generation && trip == nil && tripFailure == nil && (choice == .delete || cart?.id == current.cartID)
    }

    private func synchronizeTrip(service: any ShoppingProgressService, generation: UUID, newlyConfirmedPlan: UUID?) async throws {
        // An edit or completion must survive termination, including a lost server reply.
        // A newer cache write may have coalesced the one we initially waited for.
        var writing: UUID
        repeat {
            writing = cacheRevision
            await cacheTask?.value
            try check(generation)
        } while writing != cacheRevision
        guard !needsCacheLoad, !cacheAccessFailed else { throw ShoppingListFailure.unavailable }
        guard let current = trip else { return }
        if let (id, status) = current.pendingMarks?.min(by: { $0.key < $1.key }) {
            let updated: ShoppingPlan
            do {
                updated = try await service.updatePlanItem(planID: current.plan.id, cartID: current.cartID, itemID: id, status: status)
            } catch let error as APIError where error.status == 404 || error.status == 409 {
                // Another device can finish this trip. Never replay its edits against the replacement.
                try check(generation)
                let active = try await service.activePlan(cartID: current.cartID)
                try check(generation)
                guard active?.id != current.plan.id else { throw error }
                if let active { acceptActivePlan(active, cartID: current.cartID) }
                else { clearVerifiedTrip() }
                tripFailure = .cartUnavailable
                reconcileSelection()
                saveCache()
                throw ShoppingListFailure.cartUnavailable
            }
            try check(generation)
            guard var latest = trip, latest.plan.id == updated.id, current.plan.id == updated.id,
                  updated.stops.contains(where: { $0.items.contains { $0.itemID == id && $0.status == status } }) else {
                throw APIError.invalidResponse
            }
            if latest.pendingMarks?[id] == status { latest.pendingMarks?[id] = nil }
            if latest.pendingMarks?.isEmpty == true { latest.pendingMarks = nil }
            latest.plan = updated
            try latest.applyPendingMarks()
            trip = latest
            saveCache()
        } else if let choice = current.pendingFinish {
            try await finish(current, choice: choice, resuming: newlyConfirmedPlan != current.plan.id,
                             service: service, generation: generation)
        }
    }

    private func finish(_ trip: ShoppingTrip, choice: ShoppingTrip.ListDisposition, resuming: Bool,
                        service: any ShoppingProgressService, generation: UUID) async throws {
        let kept = try await service.finishPlan(id: trip.plan.id, cartID: trip.cartID, list: choice, resuming: resuming)
        try check(generation)
        clearVerifiedTrip()
        tripFailure = nil
        if kept == nil {
            // Discard only edits bound to the removed cart, never transfer them to its successor.
            pending[.cart(trip.cartID)] = nil
            if choice == .keep { showsDeletedCartNotice = true }
        }
        cart = kept
        invalidatePlan()
        reconcileSelection()
        needsActiveCartResolution = kept == nil
        needsReload = true
        saveCache()
    }

    private func clearVerifiedTrip() {
        trip = nil
        selection.isShopping = false
        if !hasVerifiedPlanStatus { hasVerifiedPlanStatus = true }
    }

    private func acceptActivePlan(_ plan: ShoppingPlan, cartID: UUID, startedHere: Bool = false) {
        guard let first = plan.stops.first else { return }
        if var current = trip, current.plan.id == plan.id, current.cartID == cartID {
            current.plan = plan
            if !current.contains(current.page) { current.page = .route(first.id) }
            trip = current
        } else {
            let start = startedHere ? origin : plan.points.first ?? origin
            trip = ShoppingTrip(cartID: cartID, plan: plan, origin: start,
                                originAddress: start == origin ? originAddress : nil, page: .route(first.id))
        }
        selection.isShopping = true
        if !hasVerifiedPlanStatus { hasVerifiedPlanStatus = true }
        if cachedPlan != nil || planResult != nil { invalidatePlan() }
    }
}
