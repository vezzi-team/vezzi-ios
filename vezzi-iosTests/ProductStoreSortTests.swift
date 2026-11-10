import XCTest
@testable import vezzi_ios

@MainActor
final class ProductStoreSortTests: XCTestCase {
    func testPriceSortUsesExactOrdinaryPricesWithStableTies() {
        let low = Decimal(string: "99.00000000000001")!
        let high = Decimal(string: "99.00000000000002")!
        let offers = [
            ProductOffer(id: "b", storeID: "b", name: "B", price: low, inStock: false),
            ProductOffer(id: "c", storeID: "c", name: "C", price: high, cardPrice: 10),
            ProductOffer(id: "a", storeID: "a", name: "A", price: low, isFresh: false)
        ]
        let unusedDistance: (ProductOffer) -> Measurement<UnitLength> = { _ in
            XCTFail("Price sorting should not resolve distances")
            return Measurement(value: 0, unit: .meters)
        }
        XCTAssertEqual(ProductStoreSort.priceAscending.sorted(offers, distance: unusedDistance).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(ProductStoreSort.priceDescending.sorted(offers, distance: unusedDistance).map(\.id), ["c", "a", "b"])
        XCTAssertEqual(offers.map(\.id), ["b", "c", "a"], "Sorting must not mutate the catalog's order")
    }

    func testDistanceSortNormalizesUnitsAndUsesDisplayedFallbackWithStableTies() {
        let offers = [
            ProductOffer(id: "b", storeID: "b", name: "B", price: 10, distance: Measurement(value: 1, unit: UnitLength.kilometers)),
            ProductOffer(id: "c", storeID: "c", name: "C", price: 20, distance: Measurement(value: 350, unit: UnitLength.meters)),
            ProductOffer(id: "a", storeID: "a", name: "A", price: 30, distance: Measurement(value: 1_000, unit: UnitLength.meters)),
            ProductOffer(id: "fallback", storeID: "fallback", name: "Fallback", price: 40)
        ]
        let displayedDistance: (ProductOffer) -> Measurement<UnitLength> = {
            $0.distance ?? Measurement(value: 500, unit: .meters)
        }
        let nearest = ProductStoreSort.distanceAscending.sorted(offers, distance: displayedDistance)
        let farthest = ProductStoreSort.distanceDescending.sorted(offers, distance: displayedDistance)
        XCTAssertEqual(nearest.map(\.id), ["c", "fallback", "a", "b"])
        XCTAssertEqual(farthest.map(\.id), ["a", "b", "fallback", "c"])
        XCTAssertEqual(nearest.prefix(3).map(\.id), ["c", "fallback", "a"], "Limit the list after sorting all stores")
    }
}
