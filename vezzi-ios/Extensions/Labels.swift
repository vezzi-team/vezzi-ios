//
//  Labels.swift
//  vezzi-ios
//
//  Created by Roman Tverdohleb on 01.11.2026.
//

import Foundation

final class Texts {
    
    // MARK: - App Info
    
    enum AppInfo {
        static let title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Planzo"
    }
    
    // MARK: - Tab Bar

    enum Tabbar {
        static let home = NSLocalizedString("TabHome", comment: "Home")
        static let shoppingList = NSLocalizedString("TabShoppingList", comment: "List")
        static let stores = NSLocalizedString("TabStores", comment: "Stores")
        static let search = NSLocalizedString("TabSearch", comment: "Search")
    }

    // MARK: - Home

    enum Home {
        enum Main {
            static let address = NSLocalizedString("HomeAddress", comment: "Address")
            static let nearbyStores = NSLocalizedString("HomeNearbyStores", comment: "5 stores nearby")
            static let dinnerTitle = NSLocalizedString("HomeDinnerTitle", comment: "Dinner ideas")
            static let dinnerSubtitle = NSLocalizedString("HomeDinnerSubtitle", comment: "Simple, delicious, ready in 20 minutes")
            static let collectProducts = NSLocalizedString("HomeCollectProducts", comment: "Add ingredients")
            static let dinnerAdded = NSLocalizedString("HomeDinnerAdded", comment: "Ingredients added")
            static let forYou = NSLocalizedString("HomeForYou", comment: "For you")
        }

        enum Product {
            static let priceFrom = NSLocalizedString("HomePriceFrom", comment: "from")
            static let offeredAtStores = NSLocalizedString("HomeOfferedAtStores", comment: "Stores")
            static let availableNearby = NSLocalizedString("HomeAvailableNearby", comment: "Available nearby")
            static let alternatives = NSLocalizedString("HomeProductAlternatives", comment: "Other options")
            static let close = NSLocalizedString("HomeClose", comment: "Close")
            static let compareHint = NSLocalizedString("HomeCompareHint", comment: "Add to your list to compare")
            static let inList = NSLocalizedString("HomeInList", comment: "In your list")

            static func inStores(_ count: Int) -> String {
                String.localizedStringWithFormat(NSLocalizedString("HomeInStores", comment: "Number of stores with an offer"), count)
            }
        }

        enum Quantity {
            static let add = NSLocalizedString("HomeAdd", comment: "Add")

            static func addProduct(_ name: String) -> String {
                String.localizedStringWithFormat(NSLocalizedString("HomeAddProduct", comment: "Add a product"), name)
            }

            static func quantityOf(_ name: String) -> String {
                String.localizedStringWithFormat(NSLocalizedString("HomeQuantityOf", comment: "Product quantity"), name)
            }

            static func decreaseQuantity(_ name: String) -> String {
                String.localizedStringWithFormat(NSLocalizedString("HomeDecreaseQuantity", comment: "Decrease product quantity"), name)
            }

            static func increaseQuantity(_ name: String) -> String {
                String.localizedStringWithFormat(NSLocalizedString("HomeIncreaseQuantity", comment: "Increase product quantity"), name)
            }
        }

        enum Mock {
            static let homeAddress = NSLocalizedString("HomeAddressHome", comment: "6 Leninsky Prospekt")
            static let workAddress = NSLocalizedString("HomeAddressWork", comment: "28 Nevsky Prospekt")
            static let milk = NSLocalizedString("HomeMilk", comment: "Prostokvashino 3.5% UHT milk")
            static let milkBrand = NSLocalizedString("HomeMilkBrand", comment: "Prostokvashino")
            static let domikMilk = NSLocalizedString("HomeDomikMilk", comment: "Domik v Derevne 3.5% UHT milk")
            static let domikBrand = NSLocalizedString("HomeDomikBrand", comment: "Domik v Derevne")
            static let domikPackage = NSLocalizedString("HomeDomikPackage", comment: "980 ml")
            static let kubanskayaMilk = NSLocalizedString("HomeKubanskayaMilk", comment: "2.5% milk")
            static let kubanskayaBrand = NSLocalizedString("HomeKubanskayaBrand", comment: "Kubanskaya Buryonka")
            static let kubanskayaPackage = NSLocalizedString("HomeKubanskayaPackage", comment: "930 ml")
            static let oneLiter = NSLocalizedString("HomeOneLiter", comment: "1 L")
            static let bread = NSLocalizedString("HomeBread", comment: "White bread")
            static let ryeBread = NSLocalizedString("HomeRyeBread", comment: "Rye bread")
            static let baguette = NSLocalizedString("HomeBaguette", comment: "Baguette")
            static let breadBrand = NSLocalizedString("HomeBreadBrand", comment: "Family bakery")
            static let breadPackage = NSLocalizedString("HomeBreadPackage", comment: "380 g")
            static let apples = NSLocalizedString("HomeApples", comment: "Gala apples")
            static let grannySmithApples = NSLocalizedString("HomeGrannySmithApples", comment: "Granny Smith apples")
            static let goldenApples = NSLocalizedString("HomeGoldenApples", comment: "Golden Delicious apples")
            static let freshFruit = NSLocalizedString("HomeFreshFruit", comment: "Fresh fruit")
            static let oneKilogram = NSLocalizedString("HomeOneKilogram", comment: "1 kg")
            static let halfKilogram = NSLocalizedString("HomeHalfKilogram", comment: "500 g")
            static let quarterKilogram = NSLocalizedString("HomeQuarterKilogram", comment: "250 g")
            static let eggs = NSLocalizedString("HomeEggs", comment: "Eggs")
            static let selectedEggs = NSLocalizedString("HomeSelectedEggs", comment: "C0 eggs")
            static let secondGradeEggs = NSLocalizedString("HomeSecondGradeEggs", comment: "C2 eggs")
            static let eggsBrand = NSLocalizedString("HomeEggsBrand", comment: "Farm eggs")
            static let eggsPackage = NSLocalizedString("HomeEggsPackage", comment: "10 pcs")
            static let pasta = NSLocalizedString("HomePasta", comment: "Spaghetti")
            static let penne = NSLocalizedString("HomePenne", comment: "Penne pasta")
            static let fusilli = NSLocalizedString("HomeFusilli", comment: "Fusilli pasta")
            static let pastaBrand = NSLocalizedString("HomePastaBrand", comment: "Makfa")
            static let pastaPackage = NSLocalizedString("HomePastaPackage", comment: "450 g")
            static let tomatoes = NSLocalizedString("HomeTomatoes", comment: "Tomatoes")
            static let cherryTomatoes = NSLocalizedString("HomeCherryTomatoes", comment: "Cherry tomatoes")
            static let plumTomatoes = NSLocalizedString("HomePlumTomatoes", comment: "Plum tomatoes")
            static let freshVegetables = NSLocalizedString("HomeFreshVegetables", comment: "Fresh vegetables")
            static let pyaterochka = NSLocalizedString("HomePyaterochka", comment: "Pyaterochka")
            static let magnit = NSLocalizedString("HomeMagnit", comment: "Magnit")
            static let lenta = NSLocalizedString("HomeLenta", comment: "Lenta")
        }
    }

    // MARK: - Storage

    enum Storage {
        static let cacheUnavailable = NSLocalizedString("StorageCacheUnavailable", comment: "Non-blocking cache failure")
        static let retry = NSLocalizedString("StorageRetry", comment: "Try again")
    }

    // MARK: - Search

    enum Search {
        static let prompt = NSLocalizedString("SearchPrompt", comment: "Find products")
        static let emptyTitle = NSLocalizedString("SearchEmptyTitle", comment: "No products yet")
        static let emptyDescription = NSLocalizedString("SearchEmptyDescription", comment: "Products will appear here when the catalog is available.")
        static let noResultsTitle = NSLocalizedString("SearchNoResultsTitle", comment: "No products found")
        static let noResultsDescription = NSLocalizedString("SearchNoResultsDescription", comment: "Try another name, brand or category.")
        static let noOffers = NSLocalizedString("SearchNoOffers", comment: "No store offers available")
        static let inStock = NSLocalizedString("SearchInStock", comment: "In stock")
        static let outOfStock = NSLocalizedString("SearchOutOfStock", comment: "Out of stock")
        static let unknownPriceDate = NSLocalizedString("SearchUnknownPriceDate", comment: "Price update date unknown")
        static let refreshError = NSLocalizedString("SearchRefreshError", comment: "Unable to update prices. Saved data is still available.")
        static let resultLimit = NSLocalizedString("SearchResultLimit", comment: "Up to 50 products are shown. Refine your search to find more.")
    }

    // MARK: - Demo Module
    
    enum Demo {
        static let title = NSLocalizedString("DemoTitle", comment: "Welcome")
        static let subtitle = NSLocalizedString("DemoSubtitle", comment: "This is demo subtitle")
        static let showSubtitle = NSLocalizedString("DemoShowSubtitle", comment: "Show subtitle")
    }
}
