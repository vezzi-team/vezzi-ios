import Foundation

/// Shared temporary storefront fixtures. They are never imported into the catalog or persisted.
enum ProductMockData {
    static let products = productGroups.compactMap(\.first)
    static let allProducts = Array(productGroups.joined())
    static let productIDs = Set(productGroups.joined().map(\.id))
    static let dinnerProductIDs = ["pasta", "tomatoes"]

    static func product(for productID: String) -> Product? {
        productGroups.joined().first { $0.id == productID }
    }

    static func alternatives(for productID: String) -> [Product] {
        guard let group = productGroups.first(where: { $0.contains(where: { $0.id == productID }) }) else { return [] }
        return group.filter { $0.id != productID }
    }

    /// Each group starts with its Home card, followed by two comparable products.
    static let productGroups: [[Product]] = [
        [
            Product(id: "milk", name: Texts.Product.Mock.milk, brand: Texts.Product.Mock.milkBrand,
                        packageQuantity: 1, packageUnit: Texts.Product.Unit.liter, category: .dairy, offers: offers(for: "milk", prices: [99, 109, 115])),
            Product(id: "milk-domik", name: Texts.Product.Mock.domikMilk, brand: Texts.Product.Mock.domikBrand,
                        packageQuantity: 980, packageUnit: Texts.Product.Unit.milliliter, category: .dairy, offers: offers(for: "milk-domik", prices: [99, 109, 115])),
            Product(id: "milk-kubanskaya", name: Texts.Product.Mock.kubanskayaMilk, brand: Texts.Product.Mock.kubanskayaBrand,
                        packageQuantity: 930, packageUnit: Texts.Product.Unit.milliliter, category: .dairy, offers: offers(for: "milk-kubanskaya", prices: [99, 109, 115]))
        ],
        [
            Product(id: "bread", name: Texts.Product.Mock.bread, brand: Texts.Product.Mock.breadBrand,
                        packageQuantity: 380, packageUnit: Texts.Product.Unit.gram, category: .bakery, offers: offers(for: "bread", prices: [55, 59, 65])),
            Product(id: "bread-rye", name: Texts.Product.Mock.ryeBread, brand: Texts.Product.Mock.breadBrand,
                        packageQuantity: 500, packageUnit: Texts.Product.Unit.gram, category: .bakery, offers: offers(for: "bread-rye", prices: [65, 69, 75])),
            Product(id: "bread-baguette", name: Texts.Product.Mock.baguette, brand: Texts.Product.Mock.breadBrand,
                        packageQuantity: 250, packageUnit: Texts.Product.Unit.gram, category: .bakery, offers: offers(for: "bread-baguette", prices: [59, 65, 69]))
        ],
        [
            Product(id: "apples", name: Texts.Product.Mock.apples, brand: Texts.Product.Mock.freshFruit,
                        packageQuantity: 1, packageUnit: Texts.Product.Unit.kilogram, category: .produce, offers: offers(for: "apples", prices: [129, 139, 149])),
            Product(id: "apples-granny-smith", name: Texts.Product.Mock.grannySmithApples, brand: Texts.Product.Mock.freshFruit,
                        packageQuantity: 1, packageUnit: Texts.Product.Unit.kilogram, category: .produce, offers: offers(for: "apples-granny-smith", prices: [149, 159, 169])),
            Product(id: "apples-golden", name: Texts.Product.Mock.goldenApples, brand: Texts.Product.Mock.freshFruit,
                        packageQuantity: 1, packageUnit: Texts.Product.Unit.kilogram, category: .produce, offers: offers(for: "apples-golden", prices: [119, 129, 139]))
        ],
        [
            Product(id: "eggs", name: Texts.Product.Mock.eggs, brand: Texts.Product.Mock.eggsBrand,
                        packageQuantity: 10, packageUnit: Texts.Product.Unit.piece, category: .eggs, offers: offers(for: "eggs", prices: [119, 125, 139])),
            Product(id: "eggs-c0", name: Texts.Product.Mock.selectedEggs, brand: Texts.Product.Mock.eggsBrand,
                        packageQuantity: 10, packageUnit: Texts.Product.Unit.piece, category: .eggs, offers: offers(for: "eggs-c0", prices: [139, 149, 159])),
            Product(id: "eggs-c2", name: Texts.Product.Mock.secondGradeEggs, brand: Texts.Product.Mock.eggsBrand,
                        packageQuantity: 10, packageUnit: Texts.Product.Unit.piece, category: .eggs, offers: offers(for: "eggs-c2", prices: [99, 109, 119]))
        ],
        [
            Product(id: "pasta", name: Texts.Product.Mock.pasta, brand: Texts.Product.Mock.pastaBrand,
                        packageQuantity: 450, packageUnit: Texts.Product.Unit.gram, category: .pantry, offers: offers(for: "pasta", prices: [89, 95, 109])),
            Product(id: "pasta-penne", name: Texts.Product.Mock.penne, brand: Texts.Product.Mock.pastaBrand,
                        packageQuantity: 450, packageUnit: Texts.Product.Unit.gram, category: .pantry, offers: offers(for: "pasta-penne", prices: [95, 99, 109])),
            Product(id: "pasta-fusilli", name: Texts.Product.Mock.fusilli, brand: Texts.Product.Mock.pastaBrand,
                        packageQuantity: 450, packageUnit: Texts.Product.Unit.gram, category: .pantry, offers: offers(for: "pasta-fusilli", prices: [89, 95, 105]))
        ],
        [
            Product(id: "tomatoes", name: Texts.Product.Mock.tomatoes, brand: Texts.Product.Mock.freshVegetables,
                        packageQuantity: 1, packageUnit: Texts.Product.Unit.kilogram, category: .produce, offers: offers(for: "tomatoes", prices: [189, 199, 219])),
            Product(id: "tomatoes-cherry", name: Texts.Product.Mock.cherryTomatoes, brand: Texts.Product.Mock.freshVegetables,
                        packageQuantity: 250, packageUnit: Texts.Product.Unit.gram, category: .produce, offers: offers(for: "tomatoes-cherry", prices: [159, 169, 179])),
            Product(id: "tomatoes-plum", name: Texts.Product.Mock.plumTomatoes, brand: Texts.Product.Mock.freshVegetables,
                        packageQuantity: 1, packageUnit: Texts.Product.Unit.kilogram, category: .produce, offers: offers(for: "tomatoes-plum", prices: [169, 179, 189]))
        ]
    ]

    private static func offers(for productID: String, prices: [Decimal]) -> [ProductOffer] {
        zip([
            ("pyaterochka", Texts.Product.Mock.pyaterochka, 350.0),
            ("magnit", Texts.Product.Mock.magnit, 500.0),
            ("lenta", Texts.Product.Mock.lenta, 800.0)
        ], prices).map { store, price in
            ProductOffer(id: productID + "." + store.0, storeID: store.0, name: store.1, price: price,
                           distance: Measurement(value: store.2, unit: .meters))
        }
    }
}
