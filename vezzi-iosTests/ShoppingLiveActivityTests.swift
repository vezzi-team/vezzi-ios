import UIKit
import XCTest
@testable import vezzi_ios

final class ShoppingLiveActivityTests: XCTestCase {
    private typealias State = ShoppingActivityAttributes.ContentState

    func testProgressLinkTargetsOnlyItsPlanAndCanBeCancelledByTabSelection() throws {
        let attributes = ShoppingActivityAttributes(sessionID: UUID(), planID: UUID())
        let url = attributes.progressURL
        XCTAssertEqual(ShoppingActivityAttributes.planID(from: url), attributes.planID)
        for invalid in ["https://shopping-progress/", "polka://other/", "polka://shopping-progress/extra/"] {
            let other = try XCTUnwrap(URL(string: invalid + attributes.planID.uuidString))
            XCTAssertNil(ShoppingActivityAttributes.planID(from: other))
        }
        let router = AppRouter(selectedTab: .catalog)
        router.openShoppingProgress(for: attributes.planID)
        XCTAssertEqual(router.selectedTab, .shoppingList)
        XCTAssertEqual(router.pendingShoppingPlanID, attributes.planID)
        router.selectTab(.home)
        XCTAssertNil(router.pendingShoppingPlanID)
    }

    func testStageTracksEachStepAndPendingCompletion() {
        var trip = makeTrip()
        let stages: [(ShoppingTrip.Page, ShoppingActivityAttributes.Stage, String?)] = [
            (.route("s"), .walking, "Store"), (.store("s"), .shopping, "Store"),
            (.returnHome, .returning, nil), (.summary, .summary, nil), (.editStore("s"), .shopping, "Store")
        ]
        for (page, stage, store) in stages {
            trip.page = page
            XCTAssertEqual(State(trip: trip).stage, stage)
            XCTAssertEqual(State(trip: trip).storeName, store)
        }
        trip.pendingFinish = .keep
        XCTAssertEqual(State(trip: trip).stage, .finishing)
    }

    func testOfflineMarksAndRelaunchUseAgreedPrices() throws {
        var trip = makeTrip()
        XCTAssertTrue(trip.togglePurchase(itemID: 17))
        let data = try PropertyListEncoder().encode(trip)
        trip = try PropertyListDecoder().decode(ShoppingTrip.self, from: data)
        XCTAssertEqual(State(trip: trip).bought, 1)
        XCTAssertEqual(State(trip: trip).total, 1)
        XCTAssertEqual(State(trip: trip).spent, Decimal(string: "29.97"))
        XCTAssertTrue(trip.togglePurchase(itemID: 17))
        XCTAssertEqual(State(trip: trip).bought, 0)
        XCTAssertEqual(State(trip: trip).spent, 0)
    }

    func testIslandLogoFitsActivityPayloadAndTracksCurrentStore() throws {
        var trip = makeTrip(chainName: String(repeating: "🧶", count: 500))
        let original = try XCTUnwrap(UIImage(named: "MotiYarn"))
        let thumbnail = try XCTUnwrap(ShoppingLiveActivity.thumbnail(original))
        let image = try XCTUnwrap(UIImage(data: thumbnail))
        XCTAssertLessThanOrEqual(image.size.width, 48)
        XCTAssertLessThanOrEqual(image.size.height, 48)
        var state = State(trip: trip)
        state.storeLogo = thumbnail
        let encoder = JSONEncoder()
        let attributes = ShoppingActivityAttributes(sessionID: UUID(), planID: trip.plan.id)
        XCTAssertLessThan(try encoder.encode(state).count + encoder.encode(attributes).count, 4096)
        XCTAssertEqual(state.storeID, "s")
        XCTAssertEqual(State(trip: makeTrip(chainName: " ")).storeName, "Branch")
        trip.page = .returnHome
        XCTAssertNil(State(trip: trip).storeID)
        XCTAssertNil(State(trip: trip).storeName)
    }

    private func makeTrip(chainName: String = "Store") -> ShoppingTrip {
        let item = ShoppingPlanItem(product: CatalogProduct(id: "p", name: "Milk"), quantity: 3,
                                    unitPrice: Decimal(string: "9.99")!, cardPrice: nil, priceConditions: nil, itemID: 17)
        let stop = ShoppingPlanStop(position: 1, store: CatalogStore(id: "s", name: "Branch", chainName: chainName),
                                    items: [item], subtotal: Decimal(string: "29.97")!)
        let plan = ShoppingPlan(id: UUID(), total: stop.subtotal, savings: nil, totalSeconds: 600, walkingMeters: 100,
                                stops: [stop], points: [], usesRoadNetwork: true, isSynthetic: false)
        return ShoppingTrip(cartID: UUID(), plan: plan, origin: .defaultOrigin, originAddress: nil, page: .route("s"))
    }
}
