import XCTest
@testable import vezzi_ios

@MainActor
final class ShoppingSurveyTests: XCTestCase {
    func testRecommendationsUsePriorityThenDistanceThenExistingMode() async throws {
        try await withAccountPreferences { preferences, accountID in
            for (priority, distance, expected): (SurveyAnswer, SurveyAnswer, ShoppingMode) in [
                (.save, .shortest, .cheaper), (.time, .gladly, .faster),
                (.balance, .worthwhile, .cheaper), (.situation, .onTheWay, .faster),
                (.balance, .weather, .faster)
            ] {
                let model = ShoppingSurveyViewModel()
                for choice in [priority, distance, .days] {
                    XCTAssertTrue(model.select(choice, for: model.question))
                    model.advance(preferences: preferences, accountID: accountID)
                }
                for _ in 0..<3 { model.advance(skipping: true, preferences: preferences, accountID: accountID) }
                XCTAssertEqual(model.result, expected)
                XCTAssertEqual(preferences.mode, expected)
            }
        }
    }

    func testBackReselectSkipAndAccountGuard() async throws {
        try await withAccountPreferences { preferences, accountID in
            let model = ShoppingSurveyViewModel()
            model.advance(preferences: preferences, accountID: accountID)
            model.advance(skipping: true, preferences: preferences, accountID: accountID)
            XCTAssertEqual(model.question, .priority)
            XCTAssertFalse(model.select(.study, for: .priority))
            XCTAssertTrue(model.select(.time, for: .priority))
            XCTAssertFalse(model.select(.time, for: .priority))
            model.advance(preferences: preferences, accountID: accountID)
            XCTAssertFalse(model.select(.save, for: .priority))
            model.back()
            XCTAssertEqual(model.answers[.priority], .time)
            for answer: SurveyAnswer in [.save, .shortest, .today, .pair] {
                model.select(answer, for: model.question)
                model.advance(preferences: preferences, accountID: accountID)
            }
            model.back()
            model.advance(skipping: true, preferences: preferences, accountID: accountID)
            XCTAssertNil(model.answers[.household])
            model.advance(skipping: true, preferences: preferences, accountID: accountID)
            model.advance(skipping: true, preferences: preferences, accountID: UUID())
            XCTAssertNil(model.result)
            XCTAssertFalse(preferences.hasCompletedSurvey)
            XCTAssertEqual(preferences.mode, .faster)
            model.advance(skipping: true, preferences: preferences, accountID: accountID)
            XCTAssertEqual(model.result, .cheaper)
            XCTAssertTrue(preferences.hasCompletedSurvey)
        }
    }

    func testProfileRetakeKeepsItsOriginAndDoesNotDuplicateTheProfile() {
        let router = AppRouter(selectedTab: .catalog)
        router.push(.profile, in: .catalog)
        router.presentedCover = .survey(accountID: UUID())
        router.openProfileFromSurvey()
        XCTAssertNil(router.presentedCover)
        XCTAssertEqual(router.selectedTab, .catalog)
        XCTAssertEqual(router.path(in: .catalog), [.profile])
        router.presentedCover = .survey(accountID: UUID())
        router.returnHomeFromSurvey()
        XCTAssertEqual(router.selectedTab, .home)
        XCTAssertTrue(router.path(in: .home).isEmpty)
    }

    func testOpeningProfileFromCompletedSurveyReturnsToProfile() {
        let router = AppRouter()
        router.presentedCover = .survey(accountID: UUID())
        router.openProfileFromSurvey()
        XCTAssertNil(router.presentedCover)
        XCTAssertNil(router.presentedSheet)
        XCTAssertEqual(router.path(in: .home), [.profile])
    }

    private func withAccountPreferences(_ run: (ShoppingPreferences, UUID) -> Void) async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = AuthenticationSession(service: ProfileAccountFixture())
        await session.restore()
        let accountID = try XCTUnwrap(session.user?.id)
        let preferences = ShoppingPreferences(authentication: session, defaults: defaults)
        preferences.save(.faster, for: accountID)
        run(preferences, accountID)
        let restored = ShoppingPreferences(authentication: session, defaults: defaults)
        XCTAssertEqual(restored.mode, preferences.mode)
        XCTAssertEqual(restored.hasCompletedSurvey, preferences.hasCompletedSurvey)
    }
}
