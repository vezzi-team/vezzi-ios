import Foundation

enum MotiCollection: String, CaseIterable, Identifiable {
    case pasta, movies, salad

    var id: Self { self }

    var headline: String {
        switch self {
        case .pasta: Texts.Home.Discovery.pasta
        case .movies: Texts.Home.Discovery.movies
        case .salad: Texts.Home.Discovery.salad
        }
    }

    var subtitle: String {
        switch self {
        case .pasta: Texts.Home.Discovery.pastaSubtitle
        case .movies: Texts.Home.Discovery.moviesSubtitle
        case .salad: Texts.Home.Discovery.saladSubtitle
        }
    }

    var title: String { "\(headline) \(subtitle)" }

    private var productCount: Int {
        switch self {
        case .pasta: 5
        case .movies: 6
        case .salad: 4
        }
    }

    /// Each group contributes one item before another item of the same kind is chosen.
    private var ingredients: [Ingredient] {
        switch self {
        case .pasta:
            [.init(["Макаронные изделия"], excluding: ["лазань", "каннеллони"]),
             .init(["Кетчупы и соусы", "Соусы (доп.)"], named: ["для пасты", "песто", "болоньезе"]),
             .init(["Сыры твёрдые и полутвёрдые"]), .init(["Сливки и коктейли"], named: ["сливки"]),
             .init(["Масла растительные"], named: ["оливков"])]
        case .movies:
            [.init(["Снеки и чипсы", "Попкорн"], named: ["попкорн"]), .init(["Снеки и чипсы"]),
             .init(["Сладкая газировка"]), .init(["Шоколад плиточный"]), .init(["Соки и нектары"]), .init(["Мороженое"])]
        case .salad:
            [.init(["Зелень и салаты", "Овощи", "Овощи (доп.)"], named: ["салат", "руккол", "шпинат"]),
             .init(["Овощи", "Овощи (доп.)"]), .init(["Сыры мягкие и рассольные"]),
             .init(["Масла растительные"], named: ["оливков"]), .init(["Зелень и салаты"])]
        }
    }

    func products(from items: [CatalogItem]) -> [Product] {
        let recipe = ingredients
        var groups = Array(repeating: [(item: CatalogItem, rank: Int)](), count: recipe.count)
        for item in items {
            guard let group = recipe.firstIndex(where: { $0.matches(item.product) }),
                  item.offers.contains(where: { $0.offer.inStock != false }) else { continue }
            // Vary the picks between sessions, but keep them stable when prices or catalog order change.
            var hasher = Hasher()
            hasher.combine(self)
            hasher.combine(item.id)
            groups[group].append((item, hasher.finalize()))
        }
        for index in groups.indices {
            groups[index].sort { ($0.rank, $0.item.id) < ($1.rank, $1.item.id) }
        }

        var result: [Product] = []
        for offset in 0..<productCount {
            for group in groups where group.indices.contains(offset) {
                result.append(Product(catalog: group[offset].item))
                if result.count == productCount { return result }
            }
        }
        return result
    }

    private struct Ingredient {
        let types: [String]
        let names: [String]
        let exclusions: [String]

        init(_ types: [String], named names: [String] = [], excluding exclusions: [String] = []) {
            self.types = types
            self.names = names
            self.exclusions = exclusions
        }

        func matches(_ product: CatalogProduct) -> Bool {
            guard let type = product.productType, types.contains(type),
                  !exclusions.contains(where: { product.name.localizedCaseInsensitiveContains($0) }) else { return false }
            return names.isEmpty || names.contains { product.name.localizedCaseInsensitiveContains($0) }
        }
    }
}
