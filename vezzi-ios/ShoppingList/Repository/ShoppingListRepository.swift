import Combine
import Foundation

/// One serial writer for the current account's active cart. Catalog storage remains independent.
@MainActor
final class ShoppingListRepository: ObservableObject {
    @Published private(set) var cart: ShoppingCart?
    @Published private(set) var planResult: ShoppingPlanResult?
    @Published private(set) var isBusy = false
    @Published private(set) var failure: ShoppingListFailure?
    @Published private(set) var accountID: String?
    let selection: ProductSelection

    private let service: (any ShoppingListService)?
    private var pending: [String: Int] = [:]
    private var previousQuantities: [String: Int] = [:]
    private var applyingRemote = false
    private var needsReload = true
    private var needsPlan = true
    private var isPresented = false
    private var generation = UUID()
    private var revision = 0
    private var worker: Task<Void, Never>?
    private var observation: AnyCancellable?

    init(service: (any ShoppingListService)? = nil, selection: ProductSelection? = nil) {
        self.service = service
        let selection = selection ?? ProductSelection()
        self.selection = selection
        previousQuantities = selection.quantities
        observation = selection.$quantities.dropFirst().sink { [weak self] values in
            self?.quantitiesChanged(values)
        }
    }

    nonisolated deinit {}

    func setAccount(_ id: String?) {
        guard accountID != id else { return }
        let guestQuantities = accountID == nil ? selection.quantities : [:]
        generation = UUID()
        worker?.cancel()
        worker = nil
        accountID = id
        cart = nil
        planResult = nil
        failure = nil
        isBusy = false
        pending = id == nil ? [:] : guestQuantities
        needsReload = true
        needsPlan = true
        applyQuantities(id == nil ? [:] : guestQuantities)
        startWorker()
    }

    func setPresented(_ presented: Bool) {
        isPresented = presented
        if presented { startWorker() }
    }

    func refresh() async {
        needsReload = true
        invalidatePlan()
        startWorker()
        await worker?.value
    }

    private func quantitiesChanged(_ values: [String: Int]) {
        defer { previousQuantities = values }
        guard !applyingRemote else { return }
        for id in Set(previousQuantities.keys).union(values.keys) where previousQuantities[id] != values[id] {
            pending[id] = values[id, default: 0]
        }
        revision += 1
        invalidatePlan()
        startWorker(debounce: true)
    }

    private func invalidatePlan() {
        planResult = nil
        needsPlan = true
    }

    private func startWorker(debounce: Bool = false) {
        guard worker == nil, accountID != nil, service != nil,
              needsReload || !pending.isEmpty || (isPresented && needsPlan && !selection.quantities.isEmpty) else { return }
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
        defer {
            if self.generation == generation {
                worker = nil
                isBusy = false
            }
        }
        guard let service else { return }
        do {
            while true {
                try check(generation)
                if needsReload {
                    let loaded: ShoppingCart?
                    if let cart {
                        do { loaded = try await service.cart(id: cart.id) }
                        catch where (error as? APIError)?.status == 404 { loaded = try await service.activeCart() }
                    } else {
                        loaded = try await service.activeCart()
                    }
                    try check(generation)
                    cart = loaded?.status == "active" ? loaded : nil
                    needsReload = false
                    reconcileSelection()
                }
                if cart == nil && pending.values.contains(where: { $0 > 0 }) {
                    let created = try await service.createCart(name: Texts.ShoppingList.title)
                    try check(generation)
                    cart = created
                    reconcileSelection()
                }
                if let entry = nextPendingItem(), let cart {
                    let exists = cart.quantities[entry.key] != nil
                    if cart.quantities[entry.key, default: 0] == entry.value {
                        pending[entry.key] = nil
                        continue
                    }
                    if entry.value > 0 && !exists && cart.items.count >= ProductSelection.maximumProductCount {
                        throw ShoppingListFailure.limit
                    }
                    let updated = try await service.updateItem(cartID: cart.id, productID: entry.key,
                                                              quantity: entry.value, exists: exists)
                    try check(generation)
                    self.cart = updated
                    // A newer local edit takes precedence over this response.
                    if pending[entry.key] == entry.value { pending[entry.key] = nil }
                    reconcileSelection()
                    continue
                }
                if cart == nil { pending = [:] }
                guard isPresented, needsPlan, let cart, !cart.items.isEmpty else { return }
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
                needsPlan = false
                return
            }
        } catch is CancellationError {
            // The account changed; its replacement worker owns presentation state.
        } catch {
            guard self.generation == generation else { return }
            // POST /items adds quantities. Always reload before retrying an ambiguous response.
            needsReload = true
            failure = ShoppingListFailure.from(error)
        }
    }

    private func nextPendingItem() -> (key: String, value: Int)? {
        pending.sorted {
            if ($0.value == 0) != ($1.value == 0) { return $0.value == 0 }
            return $0.key < $1.key
        }.first
    }

    private func reconcileSelection() {
        var values = cart?.quantities ?? [:]
        for (id, quantity) in pending { values[id] = quantity == 0 ? nil : quantity }
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
