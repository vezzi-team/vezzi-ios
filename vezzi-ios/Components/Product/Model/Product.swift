import Foundation

struct Product: Identifiable {
    let id: String
    let name: String
    let brand: String
    let packageQuantity: Decimal?
    let packageUnit: String?
    let category: ProductCategory?
    var offers: [ProductOffer]

    var package: String {
        [packageQuantity.map { $0.formatted() }, packageUnit].compactMap { $0 }.joined(separator: " ")
    }

    var lowestOffer: ProductOffer? { offers.min { $0.price < $1.price } }
    var lowestPrice: Decimal? { lowestOffer?.price }
}

enum ProductCategory: String, CaseIterable, Identifiable {
    case dairy
    case produce
    case bakery
    case pantry
    case eggs

    var id: Self { self }
}

struct ProductOffer: Identifiable {
    let id: String
    let storeID: String
    let name: String
    let price: Decimal
    var currency = "RUB"
    var inStock: Bool? = true
    var distance: Measurement<UnitLength>?
}

