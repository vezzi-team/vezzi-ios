/// Stable, nonlocalized identifiers used to find interface elements in UI tests.
enum AccessibilityID {
    enum Routes {
        enum AddressSearch {
            static let cancel = "routes.addressSearch.cancel"
            static let results = "routes.addressSearch.results"
            static func suggestion(_ id: String) -> String { "routes.addressSearch.suggestion.\(id)" }
        }
        enum Settings {
            static let panel = "routes.settings.panel"
            static let direction = "routes.settings.direction"
            static let radius = "routes.settings.radius"
            static let coordinate = "routes.settings.coordinate"
            static let pin = "routes.settings.pin"
            static let expand = "routes.settings.expand"
            static let returnToArea = "routes.settings.returnToArea"
            static let returnToAreaInPanel = "routes.settings.returnToAreaInPanel"
            static func radiusOption(_ meters: Int) -> String { "routes.settings.radius.\(meters)" }
        }
        static let zoomIn = "routes.zoomIn"
        static let zoomOut = "routes.zoomOut"
        static let deviceLocation = "routes.deviceLocation"
        static let attribution = "routes.attribution"
        static let map = "routes.map"
        static let options = "routes.options"
        static let origin = "routes.origin"
        static let back = "routes.back"
        static let panel = "routes.panel"
        static let recalculating = "routes.recalculating"
        static let summary = "routes.summary"
        static let startShopping = "routes.startShopping"
        static let locate = "routes.locate"
        static let confirmOrigin = "routes.confirmOrigin"
    }
    // MARK: - Home

    enum Home {
        static let empty = "home.empty"
        static let offline = "home.offline"
        static let profile = "home.profile"
        static let address = "home.address"
        static let motiCollections = "home.motiCollections"
        static let collectionProducts = "home.motiCollection.products"
        static let closeMotiCollection = "home.motiCollection.close"
        static let deals = "home.deals"
        static let essentials = "home.essentials"
        static let addDinner = "home.dinner.add"
    }

    enum Product {
        static func card(_ id: String) -> String {
            "home.product.\(id)"
        }

        static func quantity(_ id: String) -> String {
            "home.product.quantity.\(id)"
        }

        enum Detail {
            static let price = "home.product.detail.price"
            static let selectedStore = "home.product.detail.selectedStore"
            static let name = "home.product.detail.name"
            static let navigationTitle = "home.product.detail.navigationTitle"
            static let navigationSubtitle = "home.product.detail.navigationSubtitle"
            static let close = "home.product.close"
            static let add = "home.product.add"
            static let decrease = "home.product.decrease"
            static let increase = "home.product.increase"
            static let quantity = "home.product.quantity"
            static let hint = "home.product.hint"
            static let toggleStores = "home.product.detail.toggleStores"
            static let sortStores = "home.product.detail.sortStores"

            static func sortOption(_ order: String) -> String {
                "home.product.detail.sort.\(order)"
            }

            static func store(_ storeID: String) -> String {
                "home.product.detail.store.\(storeID)"
            }
        }

        enum Quantity {
            static let additionMessage = "product.addition.message"
            static let additionCheckmark = "product.addition.checkmark"

            static func add(_ productID: String) -> String {
                "home.quantity.add.\(productID)"
            }

            static func decrease(_ productID: String) -> String {
                "home.quantity.decrease.\(productID)"
            }

            static func increase(_ productID: String) -> String {
                "home.quantity.increase.\(productID)"
            }
        }
    }

    enum Catalog {
        static let banner = "catalog.status"
        static let categoryScrollToTop = "catalog.category.scrollToTop"

        static func showMore(_ category: ProductCategory) -> String { "catalog.more.\(category.id)" }
        static func heading(_ category: ProductCategory) -> String { "catalog.heading.\(category.id)" }

        enum Filters {
            static let bar = "catalog.filters"
            static func button(_ category: ProductCategory) -> String { "catalog.filter.category.\(category.id)" }
        }
    }

    static func closeCollection(_ collection: StorefrontCollection) -> String {
        switch collection {
        case .moti: Home.closeMotiCollection
        case .category: "catalog.category.close"
        }
    }

    static func collectionProducts(_ collection: StorefrontCollection) -> String {
        switch collection {
        case .moti: Home.collectionProducts
        case .category(let category): "catalog.category.products.\(category.id)"
        }
    }

    enum ShoppingList {
        static let address = "shoppingList.address"
        static let mode = "shoppingList.mode"
        static let summary = "shoppingList.summary"
        static let totalPrice = "shoppingList.totalPrice"
        static let comparisonPrice = "shoppingList.comparisonPrice"
        static let planStatus = "shoppingList.planStatus"
        static let loading = "shoppingList.loading"
        static let stores = "shoppingList.stores"
        static let storePopover = "shoppingList.storePopover"
        static let feedback = "shoppingList.feedback"
        static let route = "shoppingList.route"
        static let routePreview = "shoppingList.routePreview"
        static let empty = "shoppingList.empty"
        static let offline = "shoppingList.offline"
        static let addProducts = "shoppingList.addProducts"
    }

    enum Search {
        static let scrollToTop = "search.scrollToTop"
        static let mode = "search.mode"
        static let cancel = "search.cancel"
        static let results = "search.results"
        static let empty = "search.empty"
        static let offline = "search.offline"

        static func section(_ id: String) -> String { "search.section.\(id)" }
    }

    enum Authentication {
        static let email = "authentication.email"
        static let password = "authentication.password"
        static let success = "authentication.success"
        static let terms = "authentication.terms"
        static let signIn = "authentication.signIn"
        static let register = "authentication.register"
        static let close = "authentication.close"
        static let error = "authentication.error"
    }

    enum Profile {
        static let screen = "profile.screen"
        static let motiDebug = "profile.motiDebug"
        static let personalDetails = "profile.personalDetails"
        static let signOut = "profile.signOut"
        static let confirmSignOut = "profile.confirmSignOut"
        static let address = "profile.address"
        static let notifications = "profile.notifications"

        static func destination(_ id: String) -> String {
            "profile.destination.\(id)"
        }
    }

    enum Debug {
        enum Moti {
            static let screen = "debug.moti.screen"
            static let currentState = "debug.moti.currentState"
            static let noMotion = "debug.moti.noMotion"
            static let rapidTransitions = "debug.moti.rapidTransitions"

            static func state(_ id: String) -> String {
                "debug.moti.state.\(id)"
            }
        }
    }
}
