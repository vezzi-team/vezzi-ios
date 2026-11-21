import Foundation

enum MotiCollection: String, CaseIterable, Identifiable {
    case pasta, movies, salad

    var id: Self { self }

    var title: String {
        switch self {
        case .pasta: Texts.Home.Discovery.pasta
        case .movies: Texts.Home.Discovery.movies
        case .salad: Texts.Home.Discovery.salad
        }
    }

    private var productCount: Int {
        switch self {
        case .pasta: 5
        case .movies: 6
        case .salad: 4
        }
    }

    private var preferredTypes: Set<String> {
        switch self {
        case .pasta: ["Макаронные изделия", "Сыры твёрдые и полутвёрдые", "Сливки и коктейли", "Масла растительные"]
        case .movies: ["Снеки и чипсы", "Мороженое", "Шоколад плиточный", "Соки и нектары", "Сладкая газировка"]
        case .salad: ["Овощи", "Зелень и салаты", "Сыры мягкие и рассольные", "Масла растительные"]
        }
    }

    /// The process-local hash gives each collection a random order that survives reopening and price updates.
    func products(from items: [CatalogItem]) -> [Product] {
        let types = preferredTypes
        let candidates = items.compactMap { item -> (item: CatalogItem, preferred: Bool, rank: Int)? in
            guard item.offers.contains(where: { $0.offer.inStock != false }) else { return nil }
            var hasher = Hasher()
            hasher.combine(self)
            hasher.combine(item.id)
            return (item, types.contains(item.product.productType ?? ""), hasher.finalize())
        }
        return candidates.sorted { lhs, rhs in
            if lhs.preferred != rhs.preferred { return lhs.preferred }
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.item.id < rhs.item.id
        }
        .prefix(productCount)
        .map { Product(catalog: $0.item) }
    }
}
