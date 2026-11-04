/// Stable, nonlocalized identifiers used to find interface elements in UI tests.
enum AccessibilityID {
    // MARK: - Home

    enum Home {
        static let address = "home.address"
        static let addDinner = "home.dinner.add"

        static func product(_ id: String) -> String {
            "home.product.\(id)"
        }

        static func productQuantity(_ id: String) -> String {
            "home.product.quantity.\(id)"
        }

        enum ProductDetail {
            static let close = "home.product.close"
            static let add = "home.product.add"
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
