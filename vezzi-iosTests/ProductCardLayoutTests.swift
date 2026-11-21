import SwiftUI
import XCTest
@testable import vezzi_ios

@MainActor
final class ProductCardLayoutTests: XCTestCase {
    func testMissingFieldsDoNotChangeCardHeight() {
        let offer = ProductOffer(id: "offer", storeID: "store", name: "Store", price: 99)
        let full = product(brand: "Brand", offers: [offer])
        let variants = [product(brand: " ", offers: [offer]), product(brand: "Brand", quantity: nil, offers: [offer]),
                        product(brand: "Brand", offers: []), product(brand: "", quantity: nil, offers: [])]

        for size in [DynamicTypeSize.large, .accessibility1] {
            let expected = height(of: full, at: size)
            XCTAssertGreaterThan(expected, 0)
            for variant in variants {
                XCTAssertEqual(height(of: variant, at: size), expected, accuracy: 0.5)
            }
            let promotion = ProductPromotion(offer: offer, comparisonPrice: 149)
            XCTAssertEqual(height(of: full, at: size, promotion: promotion), expected, accuracy: 0.5)
        }
    }

    func testCompactTitleReservesTwoLinesAndAccessibilityTitleCanWrap() {
        let short = product(brand: "", offers: [])
        let long = product(name: String(repeating: "Wholegrain bread ", count: 6), brand: "", offers: [])
        XCTAssertEqual(height(of: short, at: .large), height(of: long, at: .large), accuracy: 0.5)
        XCTAssertGreaterThan(height(of: long, at: .accessibility1), height(of: short, at: .accessibility1))
    }

    private func product(name: String = "Bread", brand: String, quantity: Decimal? = 100, offers: [ProductOffer]) -> Product {
        Product(id: "p", name: name, brand: brand, packageQuantity: quantity, packageUnit: quantity == nil ? nil : "g",
                category: nil, offers: offers)
    }

    private func height(of product: Product, at size: DynamicTypeSize, promotion: ProductPromotion? = nil) -> CGFloat {
        let width: CGFloat = size.isAccessibilitySize ? 290 : 150
        let card = ProductCard(product: product, promotion: promotion, quantity: .constant(0), open: {})
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .dynamicTypeSize(size)
        return UIHostingController(rootView: card).sizeThatFits(in: CGSize(width: width, height: 2_000)).height
    }
}
