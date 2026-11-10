import Foundation

enum ProductSearchMode: String, CaseIterable, Identifiable {
    case cheaper
    case faster

    var id: Self { self }
}

struct SearchSection: Identifiable {
    let id: String
    let title: String
    let address: String?
    let storeID: String?
    let walkingMinutes: Int?
    let products: [Product]
}

struct SearchStoreInfo {
    let walkingMinutes: Int
    let distance: Measurement<UnitLength>
}
