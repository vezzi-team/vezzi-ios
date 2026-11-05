/// Stable, nonlocalized identifiers used to find interface elements in UI tests.
enum AccessibilityID {
    // MARK: - Home

    enum Home {
        static let address = "home.address"
        static let addDinner = "home.dinner.add"

        enum Filters {
            static let bar = "home.filters"

            static func category(_ id: String) -> String {
                "home.filter.\(id)"
            }
        }

        static func product(_ id: String) -> String {
            "home.product.\(id)"
        }

        static func productQuantity(_ id: String) -> String {
            "home.product.quantity.\(id)"
        }

        enum ProductDetail {
            static let close = "home.product.close"
            static let add = "home.product.add"
            static let decrease = "home.product.decrease"
            static let increase = "home.product.increase"
            static let quantity = "home.product.quantity"
            static let hint = "home.product.hint"
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
}
