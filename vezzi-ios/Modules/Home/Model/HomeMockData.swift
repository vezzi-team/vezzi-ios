import Foundation

/// Temporary screen fixtures. They are never imported into the catalog or persisted.
enum HomeMockData {
    static let products: [HomeProduct] = [
        HomeProduct(id: "milk", name: Texts.Home.Mock.milk, brand: Texts.Home.Mock.milkBrand,
                    package: Texts.Home.Mock.oneLiter, offers: offers(prices: [99, 109, 115])),
        HomeProduct(id: "bread", name: Texts.Home.Mock.bread, brand: Texts.Home.Mock.breadBrand,
                    package: Texts.Home.Mock.breadPackage, offers: offers(prices: [55, 59, 65])),
        HomeProduct(id: "apples", name: Texts.Home.Mock.apples, brand: Texts.Home.Mock.freshFruit,
                    package: Texts.Home.Mock.oneKilogram, offers: offers(prices: [129, 139, 149])),
        HomeProduct(id: "eggs", name: Texts.Home.Mock.eggs, brand: Texts.Home.Mock.eggsBrand,
                    package: Texts.Home.Mock.eggsPackage, offers: offers(prices: [119, 125, 139])),
        HomeProduct(id: "pasta", name: Texts.Home.Mock.pasta, brand: Texts.Home.Mock.pastaBrand,
                    package: Texts.Home.Mock.pastaPackage, offers: offers(prices: [89, 95, 109])),
        HomeProduct(id: "tomatoes", name: Texts.Home.Mock.tomatoes, brand: Texts.Home.Mock.freshVegetables,
                    package: Texts.Home.Mock.oneKilogram, offers: offers(prices: [189, 199, 219]))
    ]

    static let dinnerProductIDs = ["pasta", "tomatoes"]

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
