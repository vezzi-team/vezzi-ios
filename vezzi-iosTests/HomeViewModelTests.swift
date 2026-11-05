import XCTest
@testable import vezzi_ios

@MainActor
final class HomeViewModelTests: XCTestCase {
    func testFilteringPreservesQuantitiesAndRestoresTheOriginalFeed() {
        let model = HomeViewModel()
        let originalIDs = model.filteredProducts.map(\.id)
        model.setQuantity(2, for: "milk")
        model.setQuantity(3, for: "milk-domik")

        model.selectedCategory = .produce
        XCTAssertEqual(model.filteredProducts.map(\.id), ["apples", "tomatoes"])
        model.setQuantity(1, for: "apples")

        model.selectedCategory = .dairy
        XCTAssertEqual(model.filteredProducts.map(\.id), ["milk"])
        XCTAssertEqual(model.quantity(for: "milk"), 2)
        XCTAssertEqual(model.quantity(for: "milk-domik"), 3)
        XCTAssertEqual(model.alternatives(for: "milk").map(\.id), ["milk-domik", "milk-kubanskaya"])

        model.selectedCategory = nil
        XCTAssertEqual(model.filteredProducts.map(\.id), originalIDs)
        XCTAssertEqual(model.quantity(for: "apples"), 1)
    }

    func testDinnerBannerUpdatesProductsOutsideTheSelectedCategory() {
        let model = HomeViewModel()
        model.selectedCategory = .dairy
        model.setQuantity(2, for: "pasta")
        model.addDinnerProducts()

        XCTAssertEqual(model.filteredProducts.map(\.id), ["milk"])
        XCTAssertEqual(model.quantity(for: "pasta"), 2)
        XCTAssertEqual(model.quantity(for: "tomatoes"), 1)
        XCTAssertTrue(model.hasDinnerProducts)

        model.selectedCategory = .pantry
        XCTAssertEqual(model.filteredProducts.map(\.id), ["pasta"])
        XCTAssertEqual(model.quantity(for: "pasta"), 2)
    }
}
