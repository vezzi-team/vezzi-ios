import XCTest
@testable import vezzi_ios

@MainActor
final class ProductDisplayNameTests: XCTestCase {
    func testRemovesOnlyMatchingTrailingMassOrVolume() {
        let cases: [(String, Decimal, String, String)] = [
            ("Картофель фри, 450 г", 450, "g", "Картофель фри"),
            ("Молоко 3,5%, 930мл", 930, "ml", "Молоко 3,5%"),
            ("Вода, 0,5 л", 500, "ml", "Вода"),
            ("Сахар, 1000 г", 1, "kg", "Сахар"),
            ("Milk, 1 L", 1_000, "ml", "Milk"),
            ("Соль,500ГР.", 500, "g", "Соль"),
            ("Товар №1, 500 г", 500, "г", "Товар №1"),
            ("Молоко, пастеризованное, 1 л", 1, "l", "Молоко, пастеризованное"),
            ("Молоко, 1,5 л", Decimal(string: "1.5")!, "L", "Молоко"),
            ("Мука, 500\u{00A0}г", 500, "g", "Мука")
        ]
        for (name, quantity, unit, expected) in cases {
            let product = product(name, quantity: quantity, unit: unit)
            XCTAssertEqual(product.displayName, expected, name)
            XCTAssertEqual(product.name, name)
            XCTAssertEqual(product.packageQuantity, quantity)
            XCTAssertEqual(product.packageUnit, unit)
        }
    }

    func testPreservesDistinctCharacteristicsAndIncompleteOrMismatchedPackages() {
        let cases: [(String, Decimal?, String?)] = [
            ("Сыр, 45%", 450, "g"),
            ("Картофель фри, 450 г", 500, "g"),
            ("Молоко, 500 мл", 500, "g"),
            ("Молоко, 500 мл", nil, "ml"),
            ("Молоко, 500 мл", 500, nil),
            ("Молоко, 500 мл", nil, nil),
            ("Молоко 500 мл", 500, "ml"),
            ("Молоко, 2 × 500 мл", 1_000, "ml"),
            ("Вода, 500 мл, газированная", 500, "ml"),
            ("Мука 1,5 кг", 5, "kg"),
            ("Яйца, 10 шт", 10, "pcs"),
            (", 500 мл", 500, "ml")
        ]
        for (name, quantity, unit) in cases {
            XCTAssertEqual(product(name, quantity: quantity, unit: unit).displayName, name, name)
        }
    }

    func testPackageRemovalComposesWithBrandWithoutEmptyingTheName() {
        XCTAssertEqual(product("4 сезона Картофель фри, 450 г", brand: "4 сезона", quantity: 450, unit: "g").displayName,
                       "Картофель фри")
        XCTAssertEqual(product("Бренд, 450 г", brand: "Бренд", quantity: 450, unit: "g").displayName, "Бренд")
    }

    private func product(_ name: String, brand: String = "", quantity: Decimal?, unit: String?) -> Product {
        Product(id: "p", name: name, brand: brand, packageQuantity: quantity, packageUnit: unit, category: nil, offers: [])
    }
}
