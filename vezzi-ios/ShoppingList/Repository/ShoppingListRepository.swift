import Combine
import Foundation

/// One serial writer for the current account's active cart. Catalog storage remains independent.
@MainActor
final class ShoppingListRepository: ObservableObject {
    @Published private(set) var cart: ShoppingCart?
    @Published private(set) var hasResolvedCart = false
    @Published private(set) var planResult: ShoppingPlanResult?
    @Published private(set) var isBusy = false
    @Published private(set) var failure: ShoppingListFailure?
    @Published private(set) var account: ShoppingListAccount?
    var accountID: String? { account?.id }
    @Published private(set) var hasCacheFailure = false
    @Published private(set) var isPlanCached = false
    let selection: ProductSelection

    private let service: (any ShoppingListService)?
    private let cache: (any ShoppingListCache)?
    private var cachedPlan: CachedShoppingPlan?
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
    private var worker: Task<Void, Never>?
    private var observation: AnyCancellable?

    init(service: (any ShoppingListService)? = nil, selection: ProductSelection? = nil,
         cache: (any ShoppingListCache)? = nil) {
        self.service = service
        self.cache = cache
        let selection = selection ?? ProductSelection()
        self.selection = selection
        previousQuantities = selection.quantities
        observation = selection.$quantities.dropFirst().sink { [weak self] values in
            self?.quantitiesChanged(values)
        }
    }

    nonisolated deinit {}

    func setAccount(_ account: ShoppingListAccount?) {
        guard self.account != account else { return }
        let previousAccount = self.account
        let guestQuantities = accountID == nil ? selection.quantities : [:]
        generation = UUID()
        worker?.cancel()
        worker = nil
        self.account = account
        cart = nil
        hasResolvedCart = false
        planResult = nil
        cachedPlan = nil
        isPlanCached = false
        cacheAccessFailed = false
        failure = nil
        isBusy = false
        pending = account == nil || guestQuantities.isEmpty ? [:] : [.active: guestQuantities]
        locallyEditedBeforeCacheLoad = [.active: Set(guestQuantities.keys)]
        needsReload = true
        needsActiveCartResolution = true
        needsPlan = true
        needsCacheLoad = true
        cacheRevision = UUID()
        if cache != nil, let previousAccount { pendingCacheRemovals.insert(previousAccount) }
        retryCacheRemovals()
        applyQuantities(account == nil ? [:] : guestQuantities)
        startWorker()
    }

    func setPresented(_ presented: Bool) {
        isPresented = presented
        if presented { startWorker() }
    }

    func updateConnectivity(isConnected: Bool) {
        guard self.isConnected != isConnected else { return }
        self.isConnected = isConnected
        if isConnected {
            connectionRevision += 1
            startWorker()
        } else if accountID != nil {
            // Reload before sending pending edits, but let requests determine reachability.
            needsReload = true
        }
    }

    func refresh() async {
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

    private func startWorker(debounce: Bool = false) {
        guard worker == nil, accountID != nil, service != nil || cache != nil,
              needsCacheLoad || needsReload || !pending.isEmpty || (isPresented && needsPlan && !selection.quantities.isEmpty) else { return }
        isBusy = true
        failure = nil
        let generation = generation
        worker = Task { [weak self] in
            if debounce { try? await Task.sleep(for: .milliseconds(300)) }
            guard let self, !Task.isCancelled else { return }
            await self.synchronize(generation: generation)
        }
    }

    private func synchronize(generation: UUID) async {
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
            var mutationCart: ShoppingCart?
            var unavailableCarts: Set<UUID> = []
            while true {
                try check(generation)
                if needsReload {
                    let loaded: ShoppingCart?
                    if !needsActiveCartResolution, let cart {
                        do {
                            let existing = try await service.cart(id: cart.id)
                            if existing.status == "active" { loaded = existing }
                            else { loaded = try await service.activeCart() }
                        }
                        catch where (error as? APIError)?.status == 404 { loaded = try await service.activeCart() }
                    } else {
                        loaded = try await service.activeCart()
                    }
                    try check(generation)
                    cart = loaded?.status == "active" ? loaded : nil
                    hasResolvedCart = true
                    needsActiveCartResolution = false
                    if let cart {
                        bindGuestEdits(to: cart.id)
                        // A cart skipped earlier must be synchronized if it is now current.
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
                guard isPresented, needsPlan, !hasCurrentPendingEdits, let cart, !cart.items.isEmpty else { return }
                let plannedRevision = revision
                let result = try await service.plans(cartID: cart.id, start: .previewOrigin)
                try check(generation)
                // Plan requests are serialized with cart writes; an old POST cannot replace a newer calculation.
                guard plannedRevision == revision, !needsReload else { continue }
                for plan in result.plans {
                    let quantities = Dictionary(plan.stops.flatMap(\.items).map { ($0.product.id, $0.quantity) },
                                                uniquingKeysWith: +)
                    guard quantities == cart.quantities else { throw APIError.invalidResponse }
                }
                planResult = result
                cachedPlan = CachedShoppingPlan(cartID: cart.id, quantities: cart.quantities, origin: .previewOrigin,
                                                calculatedAt: Date(), result: result)
                isPlanCached = false
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
            isPlanCached = planResult != nil
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
        do {
            let snapshot = try await cache?.load(account: account)
            try check(generation)
            if let snapshot {
                try snapshot.validate()
                // A late disk read must not roll back an already restored server cart.
                if needsActiveCartResolution {
                    cart = snapshot.cart
                    hasResolvedCart = snapshot.hasResolvedCart
                }
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
                if !needsActiveCartResolution, let cart { bindGuestEdits(to: cart.id) }
                if hasCurrentPendingEdits { invalidatePlan() }
                if !pending.isEmpty { needsReload = true }
                reconcileSelection()
                if !hasCurrentPendingEdits, planResult == nil, let saved = snapshot.plan,
                   saved.origin == .previewOrigin, cart.map({ saved.matches($0) }) == true {
                    cachedPlan = saved
                    planResult = saved.result
                    isPlanCached = true
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try check(generation)
            cacheAccessFailed = true
            return
        }
        needsCacheLoad = false
        locallyEditedBeforeCacheLoad = [:]
        cacheAccessFailed = false
        saveCache()
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
                                                     hasResolvedCart: self.hasResolvedCart)
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
            guard case let .cart(id) = target, !unavailable.contains(id) else { return nil }
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
