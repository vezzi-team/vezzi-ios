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
        static let title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Polka"
    }
    
    enum Onboarding {
        static let catalogTitle = NSLocalizedString("OnboardingCatalogTitle", comment: "Build your shopping list")
        static let catalogDescription = NSLocalizedString("OnboardingCatalogDescription", comment: "Tap + on a product in the catalog to add it to your list.")
        static let comparisonTitle = NSLocalizedString("OnboardingComparisonTitle", comment: "Spend less or walk less")
        static let comparisonDescription = NSLocalizedString("OnboardingComparisonDescription", comment: "Compare prices and walking times in My list, then pick your route.")
        static let shoppingTitle = NSLocalizedString("OnboardingShoppingTitle", comment: "Check off your purchases")
        static let shoppingDescription = NSLocalizedString("OnboardingShoppingDescription", comment: "Tap the products you’ve picked up to see your total and what’s left.")
        static let routesTitle = NSLocalizedString("OnboardingRoutesTitle", comment: "Choose your route")
        static let routesDescription = NSLocalizedString("OnboardingRoutesDescription", comment: "See the stops on the map and compare walking times before you head out.")
        static let skip = NSLocalizedString("OnboardingSkip", comment: "Skip")
        static let next = NSLocalizedString("OnboardingNext", comment: "Continue")
        static let guest = NSLocalizedString("OnboardingGuest", comment: "Continue as a guest")
        static let start = NSLocalizedString("OnboardingStart", comment: "Start shopping")

        static func progress(_ current: Int, _ total: Int) -> String {
            String.localizedStringWithFormat(NSLocalizedString("OnboardingProgress", comment: "Current page and total number of onboarding pages"), current, total)
        }
    }

    // MARK: - Shared Controls

    enum Common {
        static let showMore = NSLocalizedString("CommonShowMore", comment: "Show more")
        static let scrollToTop = NSLocalizedString("ScrollToTop", comment: "Scroll to top")
    }

    // MARK: - Tab Bar

    enum Tabbar {
        static let home = NSLocalizedString("TabHome", comment: "Home")
        static let shoppingList = NSLocalizedString("TabShoppingList", comment: "List")
        static let catalog = NSLocalizedString("TabCatalog", comment: "Catalog")
        static let search = NSLocalizedString("TabSearch", comment: "Search")
    }

    // MARK: - Home

    enum Home {
        enum Discovery {
            static let emptyCollection = NSLocalizedString("HomeDiscoveryEmptyCollection", comment: "No products in this collection yet")
            static let surveyTitle = NSLocalizedString("HomeSurveyTitle", comment: "Take a survey")
            static let surveySubtitle = NSLocalizedString("HomeSurveySubtitle", comment: "Survey invitation")
            static let surveyStart = NSLocalizedString("HomeSurveyStart", comment: "Start survey")
            static let moti = NSLocalizedString("HomeDiscoveryMoti", comment: "Moti’s picks")
            static let deals = NSLocalizedString("HomeDiscoveryDeals", comment: "Deals shelf")
            static let essentials = NSLocalizedString("HomeDiscoveryEssentials", comment: "Today’s essentials")
            static let pasta = NSLocalizedString("HomeDiscoveryPasta", comment: "Pasta")
            static let movies = NSLocalizedString("HomeDiscoveryMovies", comment: "Movies")
            static let salad = NSLocalizedString("HomeDiscoverySalad", comment: "Salad")
            static let pastaSubtitle = NSLocalizedString("HomeDiscoveryPastaSubtitle", comment: "in 15 minutes")
            static let moviesSubtitle = NSLocalizedString("HomeDiscoveryMoviesSubtitle", comment: "and popcorn")
            static let saladSubtitle = NSLocalizedString("HomeDiscoverySaladSubtitle", comment: "for lunch")
        }

        enum Main {
            static let address = NSLocalizedString("HomeAddress", comment: "Address")
            static let nearbyStores = NSLocalizedString("HomeNearbyStores", comment: "5 stores nearby")
            static let dinnerTitle = NSLocalizedString("HomeDinnerTitle", comment: "Dinner ideas")
            static let dinnerSubtitle = NSLocalizedString("HomeDinnerSubtitle", comment: "Simple, delicious, ready in 20 minutes")
            static let collectProducts = NSLocalizedString("HomeCollectProducts", comment: "Add ingredients")
            static let dinnerAdded = NSLocalizedString("HomeDinnerAdded", comment: "Ingredients added")
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
        static let emptyCategory = NSLocalizedString("CatalogEmptyCategory", comment: "Empty product category")
        static func showAll(in category: String) -> String {
            String.localizedStringWithFormat(NSLocalizedString("CatalogShowAllInCategory", comment: "Open all products in a category"), category)
        }

        static let uncategorized = NSLocalizedString("CatalogUncategorized", comment: "Category for products without a category")
        static let title = NSLocalizedString("CatalogTitle", comment: "Product catalog")
        static let offlineTitle = NSLocalizedString("CatalogOfflineTitle", comment: "Offline catalog")
        static let failedTitle = NSLocalizedString("CatalogFailedTitle", comment: "Refresh failed")
        static let staleMessage = NSLocalizedString("CatalogStaleMessage", comment: "Saved prices may be outdated")
        static let noCacheMessage = NSLocalizedString("CatalogNoCacheMessage", comment: "No cached products")
        static let description = NSLocalizedString("CatalogDescription", comment: "About the catalog")
        static let refresh = NSLocalizedString("CatalogRefresh", comment: "Refresh")
        static let updating = NSLocalizedString("CatalogUpdating", comment: "Updating")
        static let signInRequired = NSLocalizedString("CatalogSignInRequired", comment: "Sign in to your account")
        static let syntheticMessage = NSLocalizedString("CatalogSyntheticMessage", comment: "Prices are synthetic")
        static let cacheTitle = NSLocalizedString("CatalogCacheTitle", comment: "Catalog persistence failed")
        static let stalePrice = NSLocalizedString("CatalogStalePrice", comment: "Stale price")
        static func cardPrice(_ price: String) -> String {
            String.localizedStringWithFormat(NSLocalizedString("CatalogCardPrice", comment: "Loyalty-card price"), price)
        }
    }

    enum Product {
        enum Details {
            static let title = NSLocalizedString("ProductDetailsTitle", comment: "Product details")
            static let brand = NSLocalizedString("ProductDetailsBrand", comment: "Brand")
            static let weight = NSLocalizedString("ProductDetailsWeight", comment: "Weight")
            static let volume = NSLocalizedString("ProductDetailsVolume", comment: "Volume")
        }

        enum Promotion {
            static func comparison(_ discount: String, _ price: String) -> String {
                String.localizedStringWithFormat(NSLocalizedString("ProductPromotionComparison", comment: "Discount compared with the highest price at another store"), discount, price)
            }
        }

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
            static let promotion = NSLocalizedString("ProductPromotionalOffer", comment: "Promotional offer")
            static let selected = NSLocalizedString("ProductSelectedStore", comment: "Selected store")
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
            static let addedToList = NSLocalizedString("ProductAddedToList", comment: "Confirmation after adding a product")
            static let openList = NSLocalizedString("ProductOpenShoppingList", comment: "Opens the shopping list")
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
        enum Controls {
            static let save = NSLocalizedString("ProfileControlsSave", comment: "Save")
        }

        enum Addresses {
            static let title = NSLocalizedString("ProfileAddressesTitle", comment: "My address")
            static let edit = NSLocalizedString("ProfileEditAddress", comment: "Change address")
        }

        enum Shopping {
            static let title = NSLocalizedString("ProfileShoppingTitle", comment: "How to shop")
            static let economical = NSLocalizedString("ProfileShoppingEconomical", comment: "Save money")
            static let priceDescription = NSLocalizedString("ProfileShoppingPriceDescription", comment: "Lowest total for your list")
            static let timeDescription = NSLocalizedString("ProfileShoppingTimeDescription", comment: "Spend less time shopping")
        }

        enum Support {
            static let title = NSLocalizedString("ProfileSupportTitle", comment: "Contact us")
            static let subtitle = NSLocalizedString("ProfileSupportSubtitle", comment: "Help with prices and shopping")
        }

        enum About {
            static let tagline = NSLocalizedString("ProfileAboutTagline", comment: "Your list. A better choice.")
            static let description = NSLocalizedString("ProfileAboutDescription", comment: "Compare grocery prices in nearby stores and choose a convenient shopping route.")
            static func version(_ value: String) -> String {
                String.localizedStringWithFormat(NSLocalizedString("ProfileAboutVersion", comment: "App version"), value)
            }
        }

        enum Main {
            static let title = NSLocalizedString("ProfileMainTitle", comment: "Profile")
            static let personalDetails = NSLocalizedString("ProfileMainPersonalDetails", comment: "My details")
            static let email = NSLocalizedString("ProfileEmail", comment: "Email address")
            static let settings = NSLocalizedString("ProfileMainSettings", comment: "Settings")
            static let debug = NSLocalizedString("ProfileMainDebug", comment: "Debug")
            static let about = NSLocalizedString("ProfileMainAbout", comment: "About Polka")
            static let terms = NSLocalizedString("ProfileMainTerms", comment: "Terms of use and privacy")
        }

        enum Settings {
            static let language = NSLocalizedString("ProfileLanguage", comment: "App language")
            static let languagePrompt = NSLocalizedString("ProfileLanguagePrompt", comment: "Open the app’s settings to change its language?")
            static let openSettings = NSLocalizedString("ProfileOpenSettings", comment: "Open Settings")
            static let appearance = NSLocalizedString("ProfileAppearance", comment: "Appearance")
            static let system = NSLocalizedString("ProfileAppearanceSystem", comment: "System")
            static let light = NSLocalizedString("ProfileAppearanceLight", comment: "Light")
            static let dark = NSLocalizedString("ProfileAppearanceDark", comment: "Dark")
            static let signOut = NSLocalizedString("ProfileSettingsSignOut", comment: "Sign out")
            static let confirmSignOut = NSLocalizedString("ProfileSettingsConfirmSignOut", comment: "Confirm signing out")
            static let signOutConfirmation = NSLocalizedString("ProfileSettingsSignOutConfirmation", comment: "Sign out of your account?")
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
        static let loading = NSLocalizedString("EmptyStateLoading", comment: "Loading")
        static let offlineTitle = NSLocalizedString("EmptyStateOfflineTitle", comment: "No internet connection")
        static let offlineDescription = NSLocalizedString("EmptyStateOfflineDescription", comment: "Connect to the internet to load data.")
    }

    // MARK: - Search

    enum Search {
        static let mode = NSLocalizedString("SearchMode", comment: "Search priority")
        static let cheaper = NSLocalizedString("SearchCheaper", comment: "Best price")
        static let faster = NSLocalizedString("SearchFaster", comment: "Fastest")

        static func showMore(in section: String, address: String?) -> String {
            [Common.showMore, section, address].compactMap { $0 }.joined(separator: ", ")
        }

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
    }

    // MARK: - Shopping List

    enum ShoppingList {
        static func planningProblem(for result: ShoppingPlanResult?) -> String? {
            guard let result, result.plans.isEmpty else { return nil }
            switch result.problem {
            case "items_unavailable": return itemsUnavailable
            case "store_limit_too_low": return storeLimit
            case "time_limit_too_low": return timeLimit
            case "radius_too_small":
                return result.minRequiredRadiusMeters.map { Routes.Settings.requiredRadius($0) } ?? radiusLimit
            case "route_unavailable": return routeUnavailable
            default: return noPlans
            }
        }
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
        static let routeTitle = NSLocalizedString("ShoppingListRouteTitle", comment: "Route")
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
        static let refreshForFastestRoutes = NSLocalizedString("ShoppingListRefreshForFastestRoutes", comment: "Refresh the list when online to see the fastest routes.")
        static let cacheError = NSLocalizedString("ShoppingListCacheError", comment: "Local storage is unavailable. Some changes may be lost when you close the app. Try again.")
        static let limitTitle = NSLocalizedString("ShoppingListLimitTitle", comment: "List limit reached")
        static let limitDescription = NSLocalizedString("ShoppingListLimitDescription", comment: "A list can contain up to 30 different products. Remove a product before adding another.")
        static let understood = NSLocalizedString("ShoppingListUnderstood", comment: "OK")
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

    enum Trip {
        static let cartAlreadyDeleted = NSLocalizedString("TripCartAlreadyDeleted", comment: "The completed trip's list was already deleted")
        static let home = NSLocalizedString("TripHome", comment: "Home")
        static let returnHome = NSLocalizedString("TripReturnHome", comment: "Return to the starting point")
        static let arrivedHome = NSLocalizedString("TripArrivedHome", comment: "I’m home")
        static let finishQuestion = NSLocalizedString("TripFinishQuestion", comment: "Finish shopping?")
        static let keepList = NSLocalizedString("TripKeepList", comment: "Keep list")
        static let deleteList = NSLocalizedString("TripDeleteList", comment: "Delete list")
        static func progressCount(_ count: Int, _ total: Int) -> String {
            String.localizedStringWithFormat(NSLocalizedString("TripProgressCount", comment: "Bought %ld of %ld"), count, total)
        }
        static func progressAmount(_ spent: String, _ total: String) -> String {
            String.localizedStringWithFormat(NSLocalizedString("TripProgressAmount", comment: "%@ of %@"), spent, total)
        }
        static let route = NSLocalizedString("TripRoute", comment: "Route")
        static let shopping = NSLocalizedString("TripShopping", comment: "Shopping")
        static let summary = NSLocalizedString("TripSummary", comment: "Summary")
        static let exit = NSLocalizedString("TripExit", comment: "Exit")
        static let resume = NSLocalizedString("TripResume", comment: "Continue shopping")
        static let arrived = NSLocalizedString("TripArrived", comment: "I’m at the store")
        static let nextRoute = NSLocalizedString("TripNextRoute", comment: "View route")
        static let viewSummary = NSLocalizedString("TripViewSummary", comment: "View summary")
        static let finish = NSLocalizedString("TripFinish", comment: "Finish shopping")
        static let active = NSLocalizedString("TripActive", comment: "Shopping in progress")
        static let activeHint = NSLocalizedString("TripActiveHint", comment: "Finish your current shopping trip to edit the list.")
        static let startError = NSLocalizedString("TripStartError", comment: "Couldn’t start shopping. Refresh the routes and try again.")
        static let saveError = NSLocalizedString("TripSaveError", comment: "Couldn’t save the change. Please try again.")
        static let products = NSLocalizedString("TripProducts", comment: "Products")
        static let boughtAtStore = NSLocalizedString("TripBoughtAtStore", comment: "Bought in this store")
        static let amount = NSLocalizedString("TripAmount", comment: "Amount spent")
        static let total = NSLocalizedString("TripTotal", comment: "Shopping total")
        static let byStore = NSLocalizedString("TripByStore", comment: "By store")
        static let noneBought = NSLocalizedString("TripNoneBought", comment: "Nothing bought yet")
        static let offlineMarks = NSLocalizedString("TripOfflineMarks", comment: "Offline purchase marks")
        static let offlineFinish = NSLocalizedString("TripOfflineFinish", comment: "Pending completion while offline")
        static let markHint = NSLocalizedString("TripMarkHint", comment: "Tap a product to mark it as bought.")
        static let editHint = NSLocalizedString("TripEditHint", comment: "Tap a store to edit your purchases.")
        static let nextStore = NSLocalizedString("TripNextStore", comment: "Next store")
        static let address = NSLocalizedString("TripAddress", comment: "Store address")
        static let fromStart = NSLocalizedString("TripFromStart", comment: "From home")
        static func fromStore(_ name: String) -> String {
            String(format: NSLocalizedString("TripFromStore", comment: "From %@"), name)
        }
        static func stop(_ position: Int, _ count: Int) -> String {
            String(format: NSLocalizedString("TripStop", comment: "Stop %ld of %ld"), position, count)
        }
        static func count(_ bought: Int, _ total: Int) -> String {
            String(format: NSLocalizedString("TripCount", comment: "%ld of %ld"), bought, total)
        }
        static func bought(_ count: Int, _ total: Int) -> String {
            String(format: NSLocalizedString("TripBought", comment: "Bought %ld of %ld products"), count, total)
        }
        static func quantity(_ count: Int) -> String {
            String(format: NSLocalizedString("TripQuantity", comment: "×%ld"), count)
        }
    }

    enum Routes {
        enum AddressSearch {
            static let hintTitle = NSLocalizedString("AddressSearchHintTitle", comment: "Choose an address")
            static let loading = NSLocalizedString("AddressSearchLoading", comment: "Searching for addresses")
            static let emptyDescription = NSLocalizedString("AddressSearchEmptyDescription", comment: "Check the spelling or try another address.")
            static let failureTitle = NSLocalizedString("AddressSearchFailureTitle", comment: "Could not find the address")
            static let title = NSLocalizedString("AddressSearchTitle", comment: "Find an address")
            static let prompt = NSLocalizedString("AddressSearchPrompt", comment: "Street and house number")
            static let hint = NSLocalizedString("AddressSearchHint", comment: "Enter a street and house number")
            static let empty = NSLocalizedString("AddressSearchEmpty", comment: "No addresses found")
            static let failure = NSLocalizedString("AddressSearchFailure", comment: "Check your connection and try again.")
            static let dismiss = NSLocalizedString("AddressSearchDismiss", comment: "Hide")
        }

        enum Settings {
            static let title = NSLocalizedString("RoutesSettingsTitle", comment: "Address and route")
            static let mapTitle = NSLocalizedString("RoutesSettingsMapTitle", comment: "Starting point")
            static let direction = NSLocalizedString("RoutesSettingsDirection", comment: "Route direction")
            static let roundTrip = NSLocalizedString("RoutesSettingsRoundTrip", comment: "Round trip")
            static let oneWay = NSLocalizedString("RoutesSettingsOneWay", comment: "One way")
            static let start = NSLocalizedString("RoutesSettingsStart", comment: "Start")
            static let radius = NSLocalizedString("RoutesSettingsRadius", comment: "Radius from the starting point")
            static let noLimit = NSLocalizedString("RoutesSettingsNoLimit", comment: "No limit")
            static let moveMap = NSLocalizedString("RoutesSettingsMoveMap", comment: "Move the map")
            static let returnToArea = NSLocalizedString("RoutesSettingsReturnToArea", comment: "Return to the available area")
            static let confirm = NSLocalizedString("RoutesSettingsConfirm", comment: "Save route settings")
            static let findingAddress = NSLocalizedString("RoutesSettingsFindingAddress", comment: "Finding address…")
            static let selectedPoint = NSLocalizedString("RoutesSettingsSelectedPoint", comment: "Selected point on the map")

            static func walkingMode(_ options: ShoppingRouteOptions) -> String {
                String.localizedStringWithFormat(NSLocalizedString("RoutesSettingsWalkingMode", comment: "Walking and route direction"),
                                                 options.returnToStart ? roundTrip : oneWay)
            }

            static func requiredRadius(_ meters: Int) -> String {
                String.localizedStringWithFormat(NSLocalizedString("RoutesSettingsRequiredRadius", comment: "Increase the search radius"),
                                                 Routes.distance(meters))
            }

            static func returnLeg(meters: Int, seconds: Int) -> String {
                String.localizedStringWithFormat(NSLocalizedString("RoutesSettingsReturnLeg", comment: "Walk back to the starting point"),
                                                 ShoppingList.minutes(Int(ceil(Double(seconds) / 60))), Routes.distance(meters))
            }
        }

        static let zoomIn = NSLocalizedString("RoutesZoomIn", comment: "Zoom in")
        static let zoomOut = NSLocalizedString("RoutesZoomOut", comment: "Zoom out")
        static let currentLocation = NSLocalizedString("RoutesCurrentLocation", comment: "Your location")
        static let locating = NSLocalizedString("RoutesLocating", comment: "Finding your location")
        static let mapAttribution = NSLocalizedString("RoutesMapAttribution", comment: "Map data credits")
        static let mapSources = NSLocalizedString("RoutesMapSources", comment: "Map sources")
        static let myLocation = NSLocalizedString("RoutesMyLocation", comment: "Use my location")
        static let openSettings = NSLocalizedString("RoutesOpenSettings", comment: "Open settings")
        static let locationDenied = NSLocalizedString("RoutesLocationDenied", comment: "Location access is off. Enable it in Settings or choose a point on the map.")
        static let locationUnavailable = NSLocalizedString("RoutesLocationUnavailable", comment: "Could not get your location. Try again or choose a point on the map.")
        static let mapUnavailable = NSLocalizedString("RoutesMapUnavailable", comment: "The map could not load. Check your connection and try again.")
        static let back = NSLocalizedString("RoutesBack", comment: "Back")
        static let yourStart = NSLocalizedString("RoutesYourStart", comment: "Your start")
        static let expandDetails = NSLocalizedString("RoutesExpandDetails", comment: "Show route details")
        static let collapseDetails = NSLocalizedString("RoutesCollapseDetails", comment: "Collapse route details")
        static let options = NSLocalizedString("RoutesOptions", comment: "Routes")
        static let withShopping = NSLocalizedString("RoutesWithShopping", comment: "including shopping")
        static let calculating = NSLocalizedString("RoutesCalculating", comment: "Calculating routes…")
        static let retry = NSLocalizedString("RoutesRetry", comment: "Try again")
        static let offline = NSLocalizedString("RoutesOffline", comment: "No connection. Reconnect to calculate a route from this point.")
        static func option(_ number: Int) -> String {
            String.localizedStringWithFormat(NSLocalizedString("RoutesOption", comment: "Route number"), Int64(number))
        }

        static func startShopping(_ price: Decimal) -> String {
            String(format: NSLocalizedString("RoutesStartShopping", comment: "Start shopping and total price"),
                   price.formatted(.currency(code: "RUB").precision(.fractionLength(0...2))))
        }

        static func walkingDistance(_ meters: Int) -> String {
            String(format: NSLocalizedString("RoutesWalkingDistance", comment: "Walking distance"), distance(meters))
        }

        static func leg(seconds: Int, meters: Int, isFirst: Bool) -> String {
            let key = isFirst ? "RoutesFirstLeg" : "RoutesNextLeg"
            return String(format: NSLocalizedString(key, comment: "Time and distance of a walking leg"),
                          ShoppingList.minutes(Int(ceil(Double(seconds) / 60))), distance(meters))
        }

        static func coordinate(_ point: ShoppingCoordinate) -> String {
            point.latitude.formatted(.number.precision(.fractionLength(4))) + ", "
                + point.longitude.formatted(.number.precision(.fractionLength(4)))
        }

        static func distance(_ meters: Int) -> String {
            Measurement(value: Double(meters), unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .road))
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
