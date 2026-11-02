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
