import Combine
import XCTest
@testable import vezzi_ios

@MainActor
final class SearchViewModelTests: XCTestCase {
    func testRefreshErrorSurvivesSearchAndClearsOnlyAfterSuccessfulRefresh() async throws {
        let source = ControlledCatalogSource()
        let repository = DefaultCatalogRepository(source: source)
        try await repository.importCatalog(CatalogFixtures.catalog())
        let viewModel = SearchViewModel(repository: repository)
        await viewModel.refresh()
        XCTAssertNotNil(viewModel.refreshErrorMessage)
        viewModel.query = "missing"
        _ = await publishedItems(viewModel.$items.dropFirst().eraseToAnyPublisher(), where: { $0.isEmpty })
        XCTAssertNotNil(viewModel.refreshErrorMessage)
        viewModel.query = "молоко"
        let items = await publishedItems(viewModel.$items.eraseToAnyPublisher(), where: { !$0.isEmpty })
        XCTAssertEqual(items.map(\.id), ["p1"])
        XCTAssertNotNil(viewModel.refreshErrorMessage)
        await source.succeed(with: CatalogFixtures.catalog(price: 120))
        await viewModel.refresh()
        XCTAssertNil(viewModel.refreshErrorMessage)
        let updated = await publishedItems(viewModel.$items.eraseToAnyPublisher(), where: { $0.first?.offers.first?.offer.price == 120 })
        XCTAssertEqual(updated.first?.offers.first?.offer.price, 120)
    }

    func testCacheFailureAndSourceFailureAreIndependentAndRetryable() async throws {
        let cache = ControlledCatalogCache()
        cache.loadError = URLError(.cannotOpenFile)
        let source = ControlledCatalogSource()
        let repository = DefaultCatalogRepository(cache: cache, source: source)
        let viewModel = SearchViewModel(repository: repository)
        await repository.prepareCache()
        await viewModel.refresh()
        XCTAssertTrue(viewModel.isCacheUnavailable)
        XCTAssertNotNil(viewModel.refreshErrorMessage)
        await source.succeed(with: CatalogFixtures.catalog())
        await viewModel.refresh()
        XCTAssertTrue(viewModel.isCacheUnavailable)
        XCTAssertNil(viewModel.refreshErrorMessage)
        cache.loadError = nil
        await viewModel.retry()
        XCTAssertFalse(viewModel.isCacheUnavailable)
        XCTAssertNil(viewModel.refreshErrorMessage)
        let items = await publishedItems(viewModel.$items.eraseToAnyPublisher(), where: { !$0.isEmpty })
        XCTAssertEqual(items.map(\.id), ["p1"])
    }

    func testFailedCacheWriteKeepsSourceResultsAndShowsOnlyCacheFailure() async throws {
        let cache = ControlledCatalogCache()
        cache.writeError = URLError(.cannotWriteToFile)
        let repository = DefaultCatalogRepository(cache: cache, source: FixedCatalogSource(batch: CatalogFixtures.catalog()))
        let viewModel = SearchViewModel(repository: repository)
        await repository.prepareCache()
        let failed = expectation(description: "Cache write failure is shown")
        let observation = viewModel.$isCacheUnavailable.filter { $0 }.prefix(1).sink { _ in failed.fulfill() }
        defer { observation.cancel() }
        await viewModel.refresh()
        await fulfillment(of: [failed], timeout: 5)
        let items = await publishedItems(viewModel.$items.eraseToAnyPublisher(), where: { !$0.isEmpty })
        XCTAssertEqual(items.first?.offers.first?.offer.price, Decimal(string: "99.90"))
        XCTAssertNil(viewModel.refreshErrorMessage)
        XCTAssertTrue(cache.snapshot.products.isEmpty)
    }
}
