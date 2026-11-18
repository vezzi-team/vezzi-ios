import Foundation

/// Cards on the deals shelf show promotional offers. Details still compare all stores.
struct HomeShelves {
    private(set) var deals: [Product] = []
    private(set) var essentials: [Product] = []
    private var dealDetails: [String: Product] = [:]

    init(items: [CatalogItem] = []) {
        var staples: [Staple: CatalogItem] = [:]
        for item in items {
            if deals.count < 5 {
                let promotion = item.offers.lazy.filter {
                    $0.isFresh && $0.offer.inStock == true && $0.offer.priceType == "promo"
                }.min {
                    $0.offer.price == $1.offer.price ? $0.id < $1.id : $0.offer.price < $1.offer.price
                }
                if let promotion {
                    deals.append(Product(catalog: CatalogItem(product: item.product, offers: [promotion])))
                    dealDetails[item.id] = Product(catalog: item)
                }
            }

            if let staple = Staple(productType: item.product.productType), staples[staple] == nil,
               item.offers.contains(where: { $0.offer.inStock == true }) {
                staples[staple] = item
            }
            if deals.count == 5 && staples.count == Staple.allCases.count { break }
        }
        essentials = Staple.allCases.compactMap { staples[$0].map { Product(catalog: $0) } }
    }

    func detailProduct(for product: Product) -> Product {
        dealDetails[product.id] ?? product
    }

    private enum Staple: CaseIterable {
        case milk, bread, pasta, eggs, grains, butter

        init?(productType: String?) {
            switch productType?.lowercased() {
            case "молоко", "milk": self = .milk
            case "хлеб", "bread": self = .bread
            case "макаронные изделия", "pasta": self = .pasta
            case "яйца куриные", "eggs": self = .eggs
            case "крупы", "grains": self = .grains
            case "масло сливочное", "butter": self = .butter
            default: return nil
            }
        }
    }
}
