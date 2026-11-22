import Foundation

nonisolated enum ShoppingItemStatus: String, Codable, Sendable {
    case planned, bought, missing
}

/// The plan freezes the store assignments and prices when the shopper starts.
nonisolated struct ShoppingTrip: Codable, Sendable {
    enum Page: Codable, Hashable {
        case route(String)
        case store(String)
        case returnHome
        case summary
        case editStore(String)
    }

    enum ListDisposition: String, Codable, Sendable { case keep, delete }

    let cartID: UUID
    var plan: ShoppingPlan
    let origin: ShoppingCoordinate
    let originAddress: String?
    var page: Page
    var pendingFinish: ListDisposition?
    // Older saved trips contain only confirmed statuses and omit this field.
    var pendingMarks: [Int64: ShoppingItemStatus]?

    var needsSync: Bool { pendingMarks?.isEmpty == false || pendingFinish != nil }

    mutating func togglePurchase(itemID: Int64) -> Bool {
        guard pendingFinish == nil else { return false }
        for stop in plan.stops.indices {
            guard let row = plan.stops[stop].items.firstIndex(where: { $0.itemID == itemID }) else { continue }
            let status: ShoppingItemStatus = plan.stops[stop].items[row].isBought ? .planned : .bought
            plan.stops[stop].items[row].status = status
            if pendingMarks == nil { pendingMarks = [:] }
            pendingMarks?[itemID] = status
            return true
        }
        return false
    }

    /// PATCH and refresh both return whole plans. Keep newer local choices visible.
    mutating func applyPendingMarks() throws {
        guard let pendingMarks, !pendingMarks.isEmpty else { return }
        var applied = 0
        for stop in plan.stops.indices {
            for row in plan.stops[stop].items.indices {
                if let id = plan.stops[stop].items[row].itemID, let status = pendingMarks[id] {
                    plan.stops[stop].items[row].status = status
                    applied += 1
                }
            }
        }
        guard applied == pendingMarks.count else { throw ShoppingListFailure.unavailable }
    }

    var items: [ShoppingPlanItem] { plan.stops.flatMap(\.items) }
    var boughtCount: Int { items.filter(\.isBought).count }
    var spent: Decimal { items.reduce(0) { $0 + $1.spent } }
    var returnsHome: Bool { plan.returnWalkingSeconds != nil || plan.returnWalkingMeters != nil }

    var pages: [Page] {
        plan.stops.flatMap { [Page.route($0.id), .store($0.id)] } + (returnsHome ? [.returnHome, .summary] : [.summary])
    }

    var navigationPath: [Page] {
        let steps = pages
        if case .editStore = page { return steps + [page] }
        guard let index = steps.firstIndex(of: page) else { return [] }
        return Array(steps[...index])
    }

    func contains(_ page: Page) -> Bool {
        switch page {
        case .summary: true
        case .returnHome: returnsHome
        case .route(let id), .store(let id), .editStore(let id): plan.stops.contains { $0.id == id }
        }
    }
}

extension ShoppingPlanItem {
    nonisolated var isBought: Bool { status == .bought }
    nonisolated var spent: Decimal { isBought ? unitPrice * Decimal(quantity) : 0 }
}

extension ShoppingPlanStop {
    nonisolated var coordinate: ShoppingCoordinate? {
        guard let latitude = store.latitude, let longitude = store.longitude else { return nil }
        return ShoppingCoordinate(latitude: latitude, longitude: longitude)
    }
    nonisolated var boughtItems: [ShoppingPlanItem] { items.filter(\.isBought) }
    nonisolated var spent: Decimal { items.reduce(0) { $0 + $1.spent } }
}

