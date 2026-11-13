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
    
    // MARK: - Shared Controls

    enum Common {
        static let scrollToTop = NSLocalizedString("ScrollToTop", comment: "Scroll to top")
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

        enum Filters {
            static let dairy = NSLocalizedString("HomeFilterDairy", comment: "Dairy")
            static let produce = NSLocalizedString("HomeFilterProduce", comment: "Fruit & vegetables")
            static let bakery = NSLocalizedString("HomeFilterBakery", comment: "Bakery")
            static let pantry = NSLocalizedString("HomeFilterPantry", comment: "Pantry")
            static let eggs = NSLocalizedString("HomeFilterEggs", comment: "Eggs")
        }

        enum Mock {
            static let homeAddress = NSLocalizedString("HomeAddressHome", comment: "6 Leninsky Prospekt")
            static let workAddress = NSLocalizedString("HomeAddressWork", comment: "28 Nevsky Prospekt")
        }
    }

    enum Catalog {
        static let title = NSLocalizedString("CatalogTitle", comment: "Product catalog")
        static let offlineTitle = NSLocalizedString("CatalogOfflineTitle", comment: "Offline catalog")
        static let failedTitle = NSLocalizedString("CatalogFailedTitle", comment: "Refresh failed")
        static let staleMessage = NSLocalizedString("CatalogStaleMessage", comment: "Saved prices may be outdated")
        static let noCacheMessage = NSLocalizedString("CatalogNoCacheMessage", comment: "No cached products")
        static let refreshMessage = NSLocalizedString("CatalogRefreshMessage", comment: "How to refresh")
        static let refresh = NSLocalizedString("CatalogRefresh", comment: "Refresh")
        static let updating = NSLocalizedString("CatalogUpdating", comment: "Updating")
        static let signInTitle = NSLocalizedString("CatalogSignInTitle", comment: "Catalog requires sign-in")
        static let signInMessage = NSLocalizedString("CatalogSignInMessage", comment: "Sign in to load the catalog")
        static let signIn = NSLocalizedString("CatalogSignIn", comment: "Sign in")
        static let syntheticTitle = NSLocalizedString("CatalogSyntheticTitle", comment: "Demo prices")
        static let syntheticMessage = NSLocalizedString("CatalogSyntheticMessage", comment: "Prices are synthetic")
        static let cacheTitle = NSLocalizedString("CatalogCacheTitle", comment: "Catalog persistence failed")
        static let stalePrice = NSLocalizedString("CatalogStalePrice", comment: "Stale price")
        static func cardPrice(_ price: String) -> String {
            String.localizedStringWithFormat(NSLocalizedString("CatalogCardPrice", comment: "Loyalty-card price"), price)
        }
    }

    enum Product {
        static let inStock = NSLocalizedString("SearchInStock", comment: "In stock")
        static let outOfStock = NSLocalizedString("SearchOutOfStock", comment: "Out of stock")

        enum Mock {
            static let milk = NSLocalizedString("HomeMilk", comment: "Prostokvashino 3.5% UHT milk")
            static let milkBrand = NSLocalizedString("HomeMilkBrand", comment: "Prostokvashino")
            static let domikMilk = NSLocalizedString("HomeDomikMilk", comment: "Domik v Derevne 3.5% UHT milk")
            static let domikBrand = NSLocalizedString("HomeDomikBrand", comment: "Domik v Derevne")
            static let kubanskayaMilk = NSLocalizedString("HomeKubanskayaMilk", comment: "2.5% milk")
            static let kubanskayaBrand = NSLocalizedString("HomeKubanskayaBrand", comment: "Kubanskaya Buryonka")
            static let bread = NSLocalizedString("HomeBread", comment: "White bread")
            static let ryeBread = NSLocalizedString("HomeRyeBread", comment: "Rye bread")
            static let baguette = NSLocalizedString("HomeBaguette", comment: "Baguette")
            static let breadBrand = NSLocalizedString("HomeBreadBrand", comment: "Family bakery")
            static let apples = NSLocalizedString("HomeApples", comment: "Gala apples")
            static let grannySmithApples = NSLocalizedString("HomeGrannySmithApples", comment: "Granny Smith apples")
            static let goldenApples = NSLocalizedString("HomeGoldenApples", comment: "Golden Delicious apples")
            static let freshFruit = NSLocalizedString("HomeFreshFruit", comment: "Fresh fruit")
            static let eggs = NSLocalizedString("HomeEggs", comment: "Eggs")
            static let selectedEggs = NSLocalizedString("HomeSelectedEggs", comment: "C0 eggs")
            static let secondGradeEggs = NSLocalizedString("HomeSecondGradeEggs", comment: "C2 eggs")
            static let eggsBrand = NSLocalizedString("HomeEggsBrand", comment: "Farm eggs")
            static let pasta = NSLocalizedString("HomePasta", comment: "Spaghetti")
            static let penne = NSLocalizedString("HomePenne", comment: "Penne pasta")
            static let fusilli = NSLocalizedString("HomeFusilli", comment: "Fusilli pasta")
            static let pastaBrand = NSLocalizedString("HomePastaBrand", comment: "Makfa")
            static let tomatoes = NSLocalizedString("HomeTomatoes", comment: "Tomatoes")
            static let cherryTomatoes = NSLocalizedString("HomeCherryTomatoes", comment: "Cherry tomatoes")
            static let plumTomatoes = NSLocalizedString("HomePlumTomatoes", comment: "Plum tomatoes")
            static let freshVegetables = NSLocalizedString("HomeFreshVegetables", comment: "Fresh vegetables")
            static let pyaterochka = NSLocalizedString("HomePyaterochka", comment: "Pyaterochka")
            static let magnit = NSLocalizedString("HomeMagnit", comment: "Magnit")
            static let lenta = NSLocalizedString("HomeLenta", comment: "Lenta")
        }

        enum Unit {
            static let meter = NSLocalizedString("ProductUnitMeter", comment: "m")
            static let liter = NSLocalizedString("ProductUnitLiter", comment: "L")
            static let milliliter = NSLocalizedString("ProductUnitMilliliter", comment: "ml")
            static let kilogram = NSLocalizedString("ProductUnitKilogram", comment: "kg")
            static let gram = NSLocalizedString("ProductUnitGram", comment: "g")
            static let piece = NSLocalizedString("ProductUnitPiece", comment: "pcs")
        }

        enum Stores {
            static let selected = NSLocalizedString("ProductSelectedStore", comment: "Selected store")
            static let showMore = NSLocalizedString("ProductShowMoreStores", comment: "Show more")
            static let showLess = NSLocalizedString("ProductShowLessStores", comment: "Show less")

            enum Sort {
                static let title = NSLocalizedString("ProductStoreSort", comment: "Sort stores")
                static let priceAscending = NSLocalizedString("ProductStoreSortPriceAscending", comment: "Cheaper")
                static let priceDescending = NSLocalizedString("ProductStoreSortPriceDescending", comment: "Pricier")
                static let distanceAscending = NSLocalizedString("ProductStoreSortDistanceAscending", comment: "Closer")
                static let distanceDescending = NSLocalizedString("ProductStoreSortDistanceDescending", comment: "Farther")
            }
        }

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
    }

    // MARK: - Authentication and Profile

    enum Authentication {
        static let passwordTooShort = NSLocalizedString("AuthenticationPasswordTooShort", comment: "Use at least 8 characters to create an account")
        static let passwordTooLong = NSLocalizedString("AuthenticationPasswordTooLong", comment: "Use no more than 128 characters")
        static let invalidCredentials = NSLocalizedString("AuthenticationInvalidCredentials", comment: "Incorrect email or password")
        static let emailAlreadyRegistered = NSLocalizedString("AuthenticationEmailAlreadyRegistered", comment: "This email is already registered. Try signing in")
        static let invalidInput = NSLocalizedString("AuthenticationInvalidInput", comment: "Check your email and password and try again")
        static let offline = NSLocalizedString("AuthenticationOffline", comment: "Couldn’t connect. Check your internet connection")
        static let timedOut = NSLocalizedString("AuthenticationTimedOut", comment: "The server took too long to respond. Please try again")
        static let rateLimited = NSLocalizedString("AuthenticationRateLimited", comment: "Too many attempts. Please try again later")
        static let sessionExpired = NSLocalizedString("AuthenticationSessionExpired", comment: "Your session has expired. Please sign in again")
        static let sessionCleanupFailed = NSLocalizedString("AuthenticationSessionCleanupFailed", comment: "Your session has ended, but its saved data couldn’t be cleared. Please try again")
        static let storageError = NSLocalizedString("AuthenticationStorageError", comment: "Couldn’t securely save or read your session. Please try again")
        static let errorTitle = NSLocalizedString("AuthenticationErrorTitle", comment: "Couldn’t complete the action")
        static let dismissError = NSLocalizedString("AuthenticationDismissError", comment: "OK")
        static let retry = NSLocalizedString("AuthenticationRetry", comment: "Try again")
        static let title = NSLocalizedString("AuthenticationTitle", comment: "Sign in")
        static let greeting = NSLocalizedString("AuthenticationGreeting", comment: "Hi, I’m Moti!")
        static let subtitle = NSLocalizedString("AuthenticationSubtitle", comment: "Sign in to keep shopping and find ideas for dinner")
        static let welcome = NSLocalizedString("AuthenticationWelcome", comment: "Glad to see you!")
        static let email = NSLocalizedString("AuthenticationEmail", comment: "Email")
        static let emailPlaceholder = NSLocalizedString("AuthenticationEmailPlaceholder", comment: "you@example.com")
        static let password = NSLocalizedString("AuthenticationPassword", comment: "Password")
        static let passwordPlaceholder = NSLocalizedString("AuthenticationPasswordPlaceholder", comment: "Enter your password")
        static let missingPassword = NSLocalizedString("AuthenticationMissingPassword", comment: "Enter your password")
        static let tryAgain = NSLocalizedString("AuthenticationTryAgain", comment: "Let’s try again")
        static let checkingCredentials = NSLocalizedString("AuthenticationCheckingCredentials", comment: "Checking your details…")
        static let creatingAccount = NSLocalizedString("AuthenticationCreatingAccount", comment: "Creating your account…")
        static let continueShopping = NSLocalizedString("AuthenticationContinueShopping", comment: "You can keep shopping")
        static let invalidEmail = NSLocalizedString("AuthenticationInvalidEmail", comment: "Enter a valid email address")
        static let unavailable = NSLocalizedString("AuthenticationUnavailable", comment: "Couldn’t sign in. Please try again.")
        static let signIn = NSLocalizedString("AuthenticationSignIn", comment: "Sign in")
        static let signingIn = NSLocalizedString("AuthenticationSigningIn", comment: "Signing in…")
        static let successTitle = NSLocalizedString("AuthenticationSuccessTitle", comment: "Welcome")
        static let register = NSLocalizedString("AuthenticationRegister", comment: "Create an account")
        static let close = NSLocalizedString("AuthenticationClose", comment: "Close")
        static let cancel = NSLocalizedString("AuthenticationCancel", comment: "Cancel")
    }

    enum Profile {
        enum Main {
            static let title = NSLocalizedString("ProfileMainTitle", comment: "Profile")
            static let subtitle = NSLocalizedString("ProfileMainSubtitle", comment: "Address, preferences and settings")
            static let yourProfile = NSLocalizedString("ProfileMainYourProfile", comment: "Your profile")
            static let personalDetails = NSLocalizedString("ProfileMainPersonalDetails", comment: "Personal details")
            static let shopping = NSLocalizedString("ProfileMainShopping", comment: "Shopping")
            static let address = NSLocalizedString("ProfileMainAddress", comment: "Shopping address")
            static let priority = NSLocalizedString("ProfileMainPriority", comment: "Shopping priority")
            static let settings = NSLocalizedString("ProfileMainSettings", comment: "Settings")
            static let debug = NSLocalizedString("ProfileMainDebug", comment: "Debug")
            static let notifications = NSLocalizedString("ProfileMainNotifications", comment: "Notifications")
            static let help = NSLocalizedString("ProfileMainHelp", comment: "Help")
            static let about = NSLocalizedString("ProfileMainAbout", comment: "About")
            static let terms = NSLocalizedString("ProfileMainTerms", comment: "Terms of use and privacy")
        }

        enum Settings {
            static let balanced = NSLocalizedString("ProfileSettingsBalanced", comment: "Balance price and time")
            static let lowestPrice = NSLocalizedString("ProfileSettingsLowestPrice", comment: "Lowest price")
            static let fastest = NSLocalizedString("ProfileSettingsFastest", comment: "Save time")
            static let enabled = NSLocalizedString("ProfileSettingsEnabled", comment: "On")
            static let disabled = NSLocalizedString("ProfileSettingsDisabled", comment: "Off")
            static let signOut = NSLocalizedString("ProfileSettingsSignOut", comment: "Sign out")
            static let signOutConfirmation = NSLocalizedString("ProfileSettingsSignOutConfirmation", comment: "Sign out of your account?")
        }

        enum Information {
            static let help = NSLocalizedString("ProfileInformationHelp", comment: "Browse products on Home and add them to your list with the + button. Open a product to compare offers and alternatives.")
            static let about = NSLocalizedString("ProfileInformationAbout", comment: "Plan your shopping, compare offers and discover ideas for dinner.")
            static let version = NSLocalizedString("ProfileInformationVersion", comment: "Version")
            static let notifications = NSLocalizedString("ProfileInformationNotifications", comment: "Notifications aren’t sent in this preview. You can try the preference here.")
            static let terms = NSLocalizedString("ProfileInformationTerms", comment: "Terms of use and the privacy policy will be available before account registration launches.")
        }

    }

    // MARK: - Debug

    enum Debug {
        enum Moti {
            static let title = NSLocalizedString("DebugMotiTitle", comment: "Moti animations")
            static let state = NSLocalizedString("DebugMotiState", comment: "Current state")
            static let emotions = NSLocalizedString("DebugMotiEmotions", comment: "Emotion")
            static let playback = NSLocalizedString("DebugMotiPlayback", comment: "Playback")
            static let idle = NSLocalizedString("DebugMotiIdle", comment: "Idle")
            static let typing = NSLocalizedString("DebugMotiTyping", comment: "Typing")
            static let error = NSLocalizedString("DebugMotiError", comment: "Error")
            static let loading = NSLocalizedString("DebugMotiLoading", comment: "Loading")
            static let success = NSLocalizedString("DebugMotiSuccess", comment: "Success")
            static let noMotion = NSLocalizedString("DebugMotiNoMotion", comment: "Without motion")
            static let rapidTransitions = NSLocalizedString("DebugMotiRapidTransitions", comment: "Test rapid transitions")
            static let stop = NSLocalizedString("DebugMotiStop", comment: "Stop transitions")
            static let playbackHint = NSLocalizedString("DebugMotiPlaybackHint", comment: "Rapid transitions switch emotions every 0.12 seconds. The system Reduce Motion setting is always respected.")
        }
    }

    // MARK: - Storage

    enum Storage {
        static let cacheUnavailable = NSLocalizedString("StorageCacheUnavailable", comment: "Non-blocking cache failure")
        static let retry = NSLocalizedString("StorageRetry", comment: "Try again")
    }

    enum EmptyState {
        static let offlineTitle = NSLocalizedString("EmptyStateOfflineTitle", comment: "No internet connection")
        static let offlineDescription = NSLocalizedString("EmptyStateOfflineDescription", comment: "Connect to the internet to load data.")
    }

    // MARK: - Search

    enum Search {
        static let mode = NSLocalizedString("SearchMode", comment: "Search priority")
        static let cheaper = NSLocalizedString("SearchCheaper", comment: "Best price")
        static let faster = NSLocalizedString("SearchFaster", comment: "Fastest")

        static func walkingTime(_ minutes: Int) -> String {
            String.localizedStringWithFormat(NSLocalizedString("SearchWalkingTime", comment: "Walking time to the store"), minutes)
        }

        enum Mock {
            static let milk = NSLocalizedString("SearchMockMilk", comment: "Milk")
            static let bread = NSLocalizedString("SearchMockBread", comment: "Bread")
            static let perekrestok = NSLocalizedString("SearchMockPerekrestok", comment: "Perekrestok")
        }

        static let prompt = NSLocalizedString("SearchPrompt", comment: "Find products")
        static let emptyTitle = NSLocalizedString("SearchEmptyTitle", comment: "No products yet")
        static let emptyDescription = NSLocalizedString("SearchEmptyDescription", comment: "Products will appear here when the catalog is available.")
        static let noResultsTitle = NSLocalizedString("SearchNoResultsTitle", comment: "Nothing found")
        static let noResultsDescription = NSLocalizedString("SearchNoResultsDescription", comment: "Try another name or check your search for typos.")
        static let noOffers = NSLocalizedString("SearchNoOffers", comment: "No store offers available")
        static let unknownPriceDate = NSLocalizedString("SearchUnknownPriceDate", comment: "Price update date unknown")
        static let resultLimit = NSLocalizedString("SearchResultLimit", comment: "Up to 50 products are shown. Refine your search to find more.")
    }

    // MARK: - Shopping List

    enum ShoppingList {
        static let title = NSLocalizedString("ShoppingListTitle", comment: "My list")
        static let mockAddress = NSLocalizedString("ShoppingListMockAddress", comment: "Komendantsky Avenue")
        static let walking = NSLocalizedString("ShoppingListWalking", comment: "Walking")
        static let bestTotal = NSLocalizedString("ShoppingListBestTotal", comment: "Best price for the whole list")
        static let fastTotal = NSLocalizedString("ShoppingListFastTotal", comment: "Fastest calculated option")
        static let fastestVariant = NSLocalizedString("ShoppingListFastestVariant", comment: "Fastest option")
        static let cheapestVariant = NSLocalizedString("ShoppingListCheapestVariant", comment: "Best price")
        static let updating = NSLocalizedString("ShoppingListUpdating", comment: "Updating your list and calculating options…")
        static let cart = NSLocalizedString("ShoppingListCart", comment: "Basket")
        static let showRoute = NSLocalizedString("ShoppingListShowRoute", comment: "View routes")
        static let routeTitle = NSLocalizedString("ShoppingListRouteTitle", comment: "Walking route")
        static let start = NSLocalizedString("ShoppingListStart", comment: "Starting point")
        static let close = NSLocalizedString("ShoppingListClose", comment: "Close")
        static let emptyTitle = NSLocalizedString("ShoppingListEmptyTitle", comment: "Your list is empty")
        static let emptyDescription = NSLocalizedString("ShoppingListEmptyDescription", comment: "Add products — we’ll compare prices and shopping time.")
        static let findProducts = NSLocalizedString("ShoppingListFindProducts", comment: "Add products")
        static let loadErrorTitle = NSLocalizedString("ShoppingListLoadErrorTitle", comment: "Couldn’t load your list")
        static let signIn = NSLocalizedString("ShoppingListSignIn", comment: "Sign in")
        static let signInDescription = NSLocalizedString("ShoppingListSignInDescription", comment: "Sign in to save your list and calculate prices and routes.")
        static let loadError = NSLocalizedString("ShoppingListLoadError", comment: "Could not update your list or calculate a route. Try again.")
        static let cartUnavailable = NSLocalizedString("ShoppingListCartUnavailable", comment: "Saved changes belong to a list that is no longer available. They have not been applied to your current list.")
        static let otherCartSyncFailed = NSLocalizedString("ShoppingListOtherCartSyncFailed", comment: "Changes to another list could not be synced. They are kept on this device for retry. Your current list is available.")
        static let cachedCalculation = NSLocalizedString("ShoppingListCachedCalculation", comment: "Showing a saved calculation. Prices and routes may have changed.")
        static let cacheError = NSLocalizedString("ShoppingListCacheError", comment: "Local storage is unavailable. Some changes may be lost when you close the app. Try again.")
        static let limitTitle = NSLocalizedString("ShoppingListLimitTitle", comment: "List limit reached")
        static let limitDescription = NSLocalizedString("ShoppingListLimitDescription", comment: "A list can contain up to 30 different products. Remove a product before adding another.")
        static let understood = NSLocalizedString("ShoppingListUnderstood", comment: "OK")
        static let addressTitle = NSLocalizedString("ShoppingListAddressTitle", comment: "Starting address")
        static let addressDescription = NSLocalizedString("ShoppingListAddressDescription", comment: "For now, calculations use a fixed starting point on Komendantsky Avenue. Address selection will be available with map integration.")
        static let itemsUnavailable = NSLocalizedString("ShoppingListItemsUnavailable", comment: "Some products have no confirmed fresh offers. Change your list or try again later.")
        static let storeLimit = NSLocalizedString("ShoppingListStoreLimit", comment: "This list requires more than three stores. Try reducing the list.")
        static let timeLimit = NSLocalizedString("ShoppingListTimeLimit", comment: "No complete route fits the current 60-minute limit. Try reducing the list.")
        static let radiusLimit = NSLocalizedString("ShoppingListRadiusLimit", comment: "Not all products are available in the selected area.")
        static let routeUnavailable = NSLocalizedString("ShoppingListRouteUnavailable", comment: "A walking route is currently unavailable. Try again later.")
        static let noPlans = NSLocalizedString("ShoppingListNoPlans", comment: "No complete shopping option was found for this list.")
        static let unavailableProduct = NSLocalizedString("ShoppingListUnavailableProduct", comment: "Product unavailable in the catalog")
        static let routeApproximation = NSLocalizedString("ShoppingListRouteApproximation", comment: "This route connects stores with straight lines and is not a walking navigation route.")

        static func products(_ count: Int) -> String {
            String.localizedStringWithFormat(NSLocalizedString("ShoppingListProductCount", comment: "Count"), Int64(count))
        }

        static func stores(_ count: Int) -> String {
            String.localizedStringWithFormat(NSLocalizedString("ShoppingListStoreCount", comment: "Count"), Int64(count))
        }

        static func minutes(_ count: Int) -> String {
            String.localizedStringWithFormat(NSLocalizedString("ShoppingListMinutes", comment: "Count"), Int64(count))
        }

        static func faster(_ count: Int) -> String {
            String.localizedStringWithFormat(NSLocalizedString("ShoppingListFaster", comment: "Count"), Int64(count))
        }

        static func savings(_ price: Decimal) -> String {
            String(format: NSLocalizedString("ShoppingListSavings", comment: "Savings"),
                   price.formatted(.currency(code: "RUB").precision(.fractionLength(0...2))))
        }
    }

    // MARK: - Demo Module
    
    enum Demo {
        static let title = NSLocalizedString("DemoTitle", comment: "Welcome")
        static let subtitle = NSLocalizedString("DemoSubtitle", comment: "This is demo subtitle")
        static let showSubtitle = NSLocalizedString("DemoShowSubtitle", comment: "Show subtitle")
    }
}

// MARK: - Authentication errors

extension AuthenticationFailure {
    @MainActor var message: String {
        switch self {
        case .invalidEmail: return Texts.Authentication.invalidEmail
        case .missingPassword: return Texts.Authentication.missingPassword
        case .passwordTooShort: return Texts.Authentication.passwordTooShort
        case .passwordTooLong: return Texts.Authentication.passwordTooLong
        case .invalidCredentials: return Texts.Authentication.invalidCredentials
        case .emailAlreadyRegistered: return Texts.Authentication.emailAlreadyRegistered
        case .invalidInput: return Texts.Authentication.invalidInput
        case .offline: return Texts.Authentication.offline
        case .timedOut: return Texts.Authentication.timedOut
        case .rateLimited: return Texts.Authentication.rateLimited
        case .sessionExpired: return Texts.Authentication.sessionExpired
        case .sessionCleanupFailed: return Texts.Authentication.sessionCleanupFailed
        case .storage: return Texts.Authentication.storageError
        case .unavailable: return Texts.Authentication.unavailable
        }
    }

}
