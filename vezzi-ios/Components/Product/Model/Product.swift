import Foundation

struct Product: Identifiable {
    let id: String
    let name: String
    let brand: String
    let packageQuantity: Decimal?
    let packageUnit: String?
    let category: ProductCategory?
    var offers: [ProductOffer]

    var nameWithoutBrand: String {
        ProductDisplayText.removing(brand, from: name)
    }

    var package: String {
        [packageQuantity.map { $0.formatted() }, packageUnit.map { Self.unitTitle($0) }].compactMap { $0 }.joined(separator: " ")
    }

    var lowestOffer: ProductOffer? {
        offers.min {
            let leftAvailable = $0.inStock != false
            let rightAvailable = $1.inStock != false
            if leftAvailable != rightAvailable { return leftAvailable }
            if $0.isFresh != $1.isFresh { return $0.isFresh }
            return $0.price == $1.price ? $0.id < $1.id : $0.price < $1.price
        }
    }
    var lowestPrice: Decimal? { lowestOffer?.price }

    private static func unitTitle(_ code: String) -> String {
        switch code {
        case "g": Texts.Product.Unit.gram
        case "ml": Texts.Product.Unit.milliliter
        case "pcs": Texts.Product.Unit.piece
        case "m": Texts.Product.Unit.meter
        case "kg": Texts.Product.Unit.kilogram
        case "l", "L": Texts.Product.Unit.liter
        default: code
        }
    }
}

struct ProductCategory: RawRepresentable, Hashable, Identifiable {
    let rawValue: String
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dairy: Texts.Home.Filters.dairy
        case .produce: Texts.Home.Filters.produce
        case .bakery: Texts.Home.Filters.bakery
        case .pantry: Texts.Home.Filters.pantry
        case .eggs: Texts.Home.Filters.eggs
        default: rawValue
        }
    }

    static let dairy = Self(rawValue: "dairy")
    static let produce = Self(rawValue: "produce")
    static let bakery = Self(rawValue: "bakery")
    static let pantry = Self(rawValue: "pantry")
    static let eggs = Self(rawValue: "eggs")
    static let allCases: [Self] = [.dairy, .produce, .bakery, .pantry, .eggs]
}

struct ProductOffer: Identifiable {
    let id: String
    let storeID: String
    let name: String
    let price: Decimal
    var currency = "RUB"
    var inStock: Bool? = true
    var distance: Measurement<UnitLength>?
    var isFresh = true
    var cardPrice: Decimal?
    var priceConditions: String?
    var address: String?
    var chainName: String?

    var storeTitle: String {
        if let chainName = chainName?.trimmingCharacters(in: .whitespacesAndNewlines), !chainName.isEmpty {
            return chainName
        }
        return ProductDisplayText.removing(address, from: name)
    }
}

extension Product {
    init(catalog item: CatalogItem, distances: [String: Measurement<UnitLength>] = [:]) {
        let offers = Dictionary(grouping: item.offers, by: { $0.store.id }).values
            .compactMap { $0.min(by: Self.preferredOffer) }
            .sorted { $0.store.name == $1.store.name ? $0.store.id < $1.store.id : $0.store.name < $1.store.name }
        self.init(id: item.id, name: item.product.name, brand: item.product.brand ?? "",
                  packageQuantity: item.product.packageQuantity, packageUnit: item.product.packageUnit,
                  category: item.product.category.map(ProductCategory.init(rawValue:)), offers: offers.map {
                      ProductOffer(id: $0.id, storeID: $0.store.id, name: $0.store.name,
                                   price: $0.offer.price, currency: $0.offer.currency, inStock: $0.offer.inStock,
                                   distance: distances[$0.store.id], isFresh: $0.isFresh,
                                   cardPrice: $0.offer.cardPrice, priceConditions: $0.offer.priceConditions,
                                   address: $0.store.address, chainName: $0.store.chainName)
                  })
    }

    nonisolated private static func preferredOffer(_ lhs: CachedOffer, _ rhs: CachedOffer) -> Bool {
        // A stale price must not make an available offer lose to an unavailable one.
        let leftAvailable = lhs.offer.inStock != false
        let rightAvailable = rhs.offer.inStock != false
        if leftAvailable != rightAvailable { return leftAvailable }
        if lhs.isFresh != rhs.isFresh { return lhs.isFresh }
        return lhs.offer.price == rhs.offer.price ? lhs.id < rhs.id : lhs.offer.price < rhs.offer.price
    }
}

private enum ProductDisplayText {
    /// Removes only a known, whole field value; the original catalog name stays intact.
    static func removing(_ detail: String?, from name: String) -> String {
        guard let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty else { return name }
        let pattern = #"(?<![\p{L}\p{N}])[«“"]?"# + NSRegularExpression.escapedPattern(for: detail)
            + #"[»”"]?(?![\p{L}\p{N}])"#
        let separated = name.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        guard separated != name else { return name }
        let result = separated
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—·,;:"))
        return result.isEmpty ? name : result
    }
}

