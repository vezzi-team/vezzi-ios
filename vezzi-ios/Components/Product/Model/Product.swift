import Foundation

struct Product: Identifiable {
    let id: String
    let name: String
    let brand: String
    let packageQuantity: Decimal?
    let packageUnit: String?
    let category: ProductCategory?
    var offers: [ProductOffer]
    var promotion: ProductPromotion?

    var displayName: String {
        let unpackaged = ProductDisplayText.removingPackage(quantity: packageQuantity, unit: packageUnit, from: name)
        return ProductDisplayText.removing(brand, from: unpackaged)
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

    var displayAddress: String? {
        StoreDisplayText.address(address)
    }
}

struct ProductPromotion {
    let offer: ProductOffer
    let comparisonPrice: Decimal

    init?(offer: ProductOffer, comparisonPrice: Decimal) {
        guard comparisonPrice > offer.price else { return nil }
        self.offer = offer
        self.comparisonPrice = comparisonPrice
    }

    var savingsFraction: Decimal {
        (comparisonPrice - offer.price) / comparisonPrice
    }
}

extension Product {
    init(catalog item: CatalogItem, distances: [String: Measurement<UnitLength>] = [:]) {
        self.init(item: item, stores: Self.representativeOffers(for: item), distances: distances)
    }

    init?(deal item: CatalogItem) {
        // A higher promotion in the same currency cannot beat a cheaper fresh, in-stock one.
        var candidates: [String: DealCandidate] = [:]
        for cached in item.offers where cached.isFresh && cached.offer.inStock == true && cached.offer.priceType == "promo" {
            let currency = cached.offer.currency
            if let previous = candidates[currency], !Self.isCheaper(cached, previous.cached) { continue }
            candidates[currency] = DealCandidate(cached: cached, comparisonPrice: cached.offer.price)
        }
        guard !candidates.isEmpty else { return nil }

        let stores = Self.representativeOffers(for: item)
        for representative in stores.values {
            let currency = representative.offer.currency
            guard let candidate = candidates[currency] else { continue }
            if representative.offer.price < candidate.cached.offer.price {
                candidates[currency] = nil
            } else if representative.offer.price > candidate.comparisonPrice, representative.store.id != candidate.cached.store.id,
                      representative.isFresh, representative.offer.inStock == true {
                candidates[currency]?.comparisonPrice = representative.offer.price
            }
        }

        let best = candidates.values.lazy.filter { $0.comparisonPrice > $0.cached.offer.price }
            .min { Self.isCheaper($0.cached, $1.cached) }
        guard let best, let promotion = ProductPromotion(offer: ProductOffer(cached: best.cached, distance: nil),
                                                         comparisonPrice: best.comparisonPrice) else { return nil }
        self.init(item: item, stores: stores, distances: [:])
        self.promotion = promotion
    }

    private struct DealCandidate {
        let cached: CachedOffer
        var comparisonPrice: Decimal
    }

    private init(item: CatalogItem, stores: [String: CachedOffer], distances: [String: Measurement<UnitLength>]) {
        let sorted = stores.values.sorted {
            $0.store.name == $1.store.name ? $0.store.id < $1.store.id : $0.store.name < $1.store.name
        }
        self.init(id: item.id, name: item.product.name, brand: item.product.brand ?? "",
                  packageQuantity: item.product.packageQuantity, packageUnit: item.product.packageUnit,
                  category: item.product.category.map(ProductCategory.init(rawValue:)),
                  offers: sorted.map { ProductOffer(cached: $0, distance: distances[$0.store.id]) })
    }

    private static func representativeOffers(for item: CatalogItem) -> [String: CachedOffer] {
        Dictionary(item.offers.lazy.map { ($0.store.id, $0) }, uniquingKeysWith: { preferredOffer($0, $1) ? $0 : $1 })
    }

    nonisolated private static func isCheaper(_ lhs: CachedOffer, _ rhs: CachedOffer) -> Bool {
        lhs.offer.price == rhs.offer.price ? lhs.id < rhs.id : lhs.offer.price < rhs.offer.price
    }

    nonisolated private static func preferredOffer(_ lhs: CachedOffer, _ rhs: CachedOffer) -> Bool {
        // A stale price must not make an available offer lose to an unavailable one.
        let leftAvailable = lhs.offer.inStock != false
        let rightAvailable = rhs.offer.inStock != false
        if leftAvailable != rightAvailable { return leftAvailable }
        if lhs.isFresh != rhs.isFresh { return lhs.isFresh }
        return isCheaper(lhs, rhs)
    }
}

private extension ProductOffer {
    init(cached: CachedOffer, distance: Measurement<UnitLength>?) {
        self.init(id: cached.id, storeID: cached.store.id, name: cached.store.name,
                  price: cached.offer.price, currency: cached.offer.currency, inStock: cached.offer.inStock,
                  distance: distance, isFresh: cached.isFresh, cardPrice: cached.offer.cardPrice,
                  priceConditions: cached.offer.priceConditions, address: cached.store.address, chainName: cached.store.chainName)
    }
}

private enum ProductDisplayText {
    private static let packageSuffix = try? NSRegularExpression(
        pattern: #"(?:,\s+|(?<![0-9]),\s*)([0-9]+(?:[.,][0-9]+)?)\s*([\p{L}]+)\.?\s*$"#)

    /// Remove a trailing package only when it duplicates the structured mass or volume.
    static func removingPackage(quantity: Decimal?, unit: String?, from name: String) -> String {
        guard let quantity, let unit,
              let package = normalizedPackage(quantity: quantity, unit: unit),
              let match = packageSuffix?.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let suffixRange = Range(match.range, in: name),
              let quantityRange = Range(match.range(at: 1), in: name),
              let unitRange = Range(match.range(at: 2), in: name),
              let suffixQuantity = Decimal(string: name[quantityRange].replacingOccurrences(of: ",", with: "."),
                                           locale: Locale(identifier: "en_US_POSIX")),
              let suffix = normalizedPackage(quantity: suffixQuantity, unit: String(name[unitRange])),
              suffix == package else { return name }
        let result = name[..<suffixRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? name : result
    }

    private static func normalizedPackage(quantity: Decimal, unit: String) -> (unit: String, amount: Decimal)? {
        guard !quantity.isNaN, quantity > 0 else { return nil }
        switch unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "g", "г", "гр": return ("g", quantity)
        case "kg", "кг": return ("g", quantity * 1_000)
        case "ml", "мл": return ("ml", quantity)
        case "l", "л": return ("ml", quantity * 1_000)
        default: return nil
        }
    }

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

nonisolated enum StoreDisplayText {
    static func address(_ address: String?) -> String? {
        guard let address = address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty else { return nil }
        // Strip only the known city prefix; keep the complete address for maps and catalog data.
        let shortened = address.replacingOccurrences(
            of: #"^(?:(?:г\.?\s*|город\s+)?Санкт-Петербург|Saint Petersburg|St\.?\s+Petersburg)\s*,\s*"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        return (shortened.isEmpty ? address : shortened).addressCapitalized
    }
}
