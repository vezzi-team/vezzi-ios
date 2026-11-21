import Foundation

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
