/// Stable, nonlocalized identifiers used to find interface elements in UI tests.
enum AccessibilityID {
    // MARK: - Home

    enum Home {
        static let profile = "home.profile"
        static let address = "home.address"
        static let scrollToTop = "home.scrollToTop"
        static let addDinner = "home.dinner.add"

        enum Filters {
            static let bar = "home.filters"

            static func category(_ id: String) -> String {
                "home.filter.\(id)"
            }
        }
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
    }

    enum Search {
        static let scrollToTop = "search.scrollToTop"
        static let mode = "search.mode"
        static let cancel = "search.cancel"
        static let results = "search.results"
        static let empty = "search.empty"

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
