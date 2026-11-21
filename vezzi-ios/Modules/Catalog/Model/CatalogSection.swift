import Foundation

struct CatalogSection: Identifiable {
    let id: ProductCategory
    let preview: [Product]

    static func sections(from items: [CatalogItem]) -> [Self] {
        var previews: [ProductCategory: [Product]] = [:]
        for item in items {
            let category = ProductCategory(catalogValue: item.product.category)
            if (previews[category]?.count ?? 0) < 4 {
                previews[category, default: []].append(Product(catalog: item))
            }
        }
        return previews.keys.sorted { comesFirst($0, $1) }.map { Self(id: $0, preview: previews[$0, default: []]) }
    }

    private static func comesFirst(_ lhs: ProductCategory, _ rhs: ProductCategory) -> Bool {
        if lhs == .uncategorized { return false }
        if rhs == .uncategorized { return true }
        let left = priority[lhs.rawValue.lowercased(), default: .max]
        let right = priority[rhs.rawValue.lowercased(), default: .max]
        if left != right { return left < right }
        let order = lhs.title.localizedStandardCompare(rhs.title)
        return order == .orderedSame ? lhs.rawValue < rhs.rawValue : order == .orderedAscending
    }

    // The export has no demand metric. Keep grocery staples first, with a stable fallback for new categories.
    private static let priority: [String: Int] = [
        "молочные продукты": 0, "dairy": 0, "молоко": 0, "milk": 0,
        "хлеб и выпечка": 1, "bakery": 1, "хлеб": 1, "bread": 1,
        "овощи и фрукты": 2, "produce": 2, "яйца": 3, "eggs": 3,
        "мясо и птица": 4, "бакалея": 5, "pantry": 5, "сыры": 6,
        "рыба и морепродукты": 7, "напитки": 8, "замороженные продукты": 9,
        "кондитерские изделия": 10, "соусы и специи": 11
    ]
}

extension ProductCategory {
    init(catalogValue: String?) {
        self.init(rawValue: catalogValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }
}
