import Foundation

enum ProductStoreSort: String, CaseIterable {
    case priceAscending
    case priceDescending
    case distanceAscending
    case distanceDescending

    /// Resolve distances from the same source used to display store rows.
    func sorted(_ offers: [ProductOffer], distance: (ProductOffer) -> Measurement<UnitLength>) -> [ProductOffer] {
        offers.sorted { lhs, rhs in
            switch self {
            case .priceAscending, .priceDescending:
                guard lhs.price != rhs.price else { return lhs.id < rhs.id }
                return self == .priceAscending ? lhs.price < rhs.price : lhs.price > rhs.price
            case .distanceAscending, .distanceDescending:
                let left = distance(lhs).converted(to: .meters).value
                let right = distance(rhs).converted(to: .meters).value
                guard left != right else { return lhs.id < rhs.id }
                return self == .distanceAscending ? left < right : left > right
            }
        }
    }
}
