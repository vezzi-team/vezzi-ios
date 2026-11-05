import Foundation

/// Temporary screen fixtures. They are never imported into the catalog or persisted.
enum HomeMockData {
    static let products = productGroups.compactMap(\.first)
    static let productIDs = Set(productGroups.joined().map(\.id))
    static let dinnerProductIDs = ["pasta", "tomatoes"]

    static func alternatives(for productID: String) -> [HomeProduct] {
        guard let group = productGroups.first(where: { $0.contains(where: { $0.id == productID }) }) else { return [] }
        return group.filter { $0.id != productID }
    }

    /// Each group starts with its Home card, followed by two comparable products.
    private static let productGroups: [[HomeProduct]] = [
        [
            HomeProduct(id: "milk", name: Texts.Home.Mock.milk, brand: Texts.Home.Mock.milkBrand,
                        package: Texts.Home.Mock.oneLiter, category: .dairy, offers: offers(prices: [99, 109, 115])),
            HomeProduct(id: "milk-domik", name: Texts.Home.Mock.domikMilk, brand: Texts.Home.Mock.domikBrand,
                        package: Texts.Home.Mock.domikPackage, category: .dairy, offers: offers(prices: [99, 109, 115])),
            HomeProduct(id: "milk-kubanskaya", name: Texts.Home.Mock.kubanskayaMilk, brand: Texts.Home.Mock.kubanskayaBrand,
                        package: Texts.Home.Mock.kubanskayaPackage, category: .dairy, offers: offers(prices: [99, 109, 115]))
        ],
        [
            HomeProduct(id: "bread", name: Texts.Home.Mock.bread, brand: Texts.Home.Mock.breadBrand,
                        package: Texts.Home.Mock.breadPackage, category: .bakery, offers: offers(prices: [55, 59, 65])),
            HomeProduct(id: "bread-rye", name: Texts.Home.Mock.ryeBread, brand: Texts.Home.Mock.breadBrand,
                        package: Texts.Home.Mock.halfKilogram, category: .bakery, offers: offers(prices: [65, 69, 75])),
            HomeProduct(id: "bread-baguette", name: Texts.Home.Mock.baguette, brand: Texts.Home.Mock.breadBrand,
                        package: Texts.Home.Mock.quarterKilogram, category: .bakery, offers: offers(prices: [59, 65, 69]))
        ],
        [
            HomeProduct(id: "apples", name: Texts.Home.Mock.apples, brand: Texts.Home.Mock.freshFruit,
                        package: Texts.Home.Mock.oneKilogram, category: .produce, offers: offers(prices: [129, 139, 149])),
            HomeProduct(id: "apples-granny-smith", name: Texts.Home.Mock.grannySmithApples, brand: Texts.Home.Mock.freshFruit,
                        package: Texts.Home.Mock.oneKilogram, category: .produce, offers: offers(prices: [149, 159, 169])),
            HomeProduct(id: "apples-golden", name: Texts.Home.Mock.goldenApples, brand: Texts.Home.Mock.freshFruit,
                        package: Texts.Home.Mock.oneKilogram, category: .produce, offers: offers(prices: [119, 129, 139]))
        ],
        [
            HomeProduct(id: "eggs", name: Texts.Home.Mock.eggs, brand: Texts.Home.Mock.eggsBrand,
                        package: Texts.Home.Mock.eggsPackage, category: .eggs, offers: offers(prices: [119, 125, 139])),
            HomeProduct(id: "eggs-c0", name: Texts.Home.Mock.selectedEggs, brand: Texts.Home.Mock.eggsBrand,
                        package: Texts.Home.Mock.eggsPackage, category: .eggs, offers: offers(prices: [139, 149, 159])),
            HomeProduct(id: "eggs-c2", name: Texts.Home.Mock.secondGradeEggs, brand: Texts.Home.Mock.eggsBrand,
                        package: Texts.Home.Mock.eggsPackage, category: .eggs, offers: offers(prices: [99, 109, 119]))
        ],
        [
            HomeProduct(id: "pasta", name: Texts.Home.Mock.pasta, brand: Texts.Home.Mock.pastaBrand,
                        package: Texts.Home.Mock.pastaPackage, category: .pantry, offers: offers(prices: [89, 95, 109])),
            HomeProduct(id: "pasta-penne", name: Texts.Home.Mock.penne, brand: Texts.Home.Mock.pastaBrand,
                        package: Texts.Home.Mock.pastaPackage, category: .pantry, offers: offers(prices: [95, 99, 109])),
            HomeProduct(id: "pasta-fusilli", name: Texts.Home.Mock.fusilli, brand: Texts.Home.Mock.pastaBrand,
                        package: Texts.Home.Mock.pastaPackage, category: .pantry, offers: offers(prices: [89, 95, 105]))
        ],
        [
            HomeProduct(id: "tomatoes", name: Texts.Home.Mock.tomatoes, brand: Texts.Home.Mock.freshVegetables,
                        package: Texts.Home.Mock.oneKilogram, category: .produce, offers: offers(prices: [189, 199, 219])),
            HomeProduct(id: "tomatoes-cherry", name: Texts.Home.Mock.cherryTomatoes, brand: Texts.Home.Mock.freshVegetables,
                        package: Texts.Home.Mock.quarterKilogram, category: .produce, offers: offers(prices: [159, 169, 179])),
            HomeProduct(id: "tomatoes-plum", name: Texts.Home.Mock.plumTomatoes, brand: Texts.Home.Mock.freshVegetables,
                        package: Texts.Home.Mock.oneKilogram, category: .produce, offers: offers(prices: [169, 179, 189]))
        ]
    ]

    private static func offers(prices: [Decimal]) -> [HomeStoreOffer] {
        zip([
            ("pyaterochka", Texts.Home.Mock.pyaterochka, 350.0),
            ("magnit", Texts.Home.Mock.magnit, 500.0),
            ("lenta", Texts.Home.Mock.lenta, 800.0)
        ], prices).map { store, price in
            HomeStoreOffer(id: store.0, name: store.1, price: price,
                           distance: Measurement(value: store.2, unit: .meters))
        }
    }
}
