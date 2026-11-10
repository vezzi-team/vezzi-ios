import Foundation

struct Product: Identifiable {
    let id: String
    let name: String
    let brand: String
    let packageQuantity: Decimal?
    let packageUnit: String?
    let category: ProductCategory?
    var offers: [ProductOffer]

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
        guard let address = address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty else { return nil }
        // Strip only the known city prefix; keep the complete address for maps and catalog data.
        let shortened = address.replacingOccurrences(
            of: #"^(?:(?:г\.?\s*|город\s+)?Санкт-Петербург|Saint Petersburg|St\.?\s+Petersburg)\s*,\s*"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        return shortened.isEmpty ? address : shortened
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

