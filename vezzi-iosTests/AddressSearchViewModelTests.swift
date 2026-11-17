import XCTest
@testable import vezzi_ios

@MainActor
final class AddressSearchViewModelTests: XCTestCase {
    func testCancelledSearchCannotEndReplacementLoadingForTheSameQuery() async {
        let service = AddressSearchStub()
        let model = AddressSearchViewModel(near: .previewOrigin, service: service)
        model.updateQuery("Street")
        let first = Task { await model.search() }
        await service.waitForQuery("Street")
        first.cancel()
        let replacement = Task { await model.search() }
        await service.waitForQuery("Street", count: 2)
        service.finishQuery("Street", result: .failure(CancellationError()))
        await first.value
        XCTAssertTrue(model.isSearching)
        XCTAssertFalse(model.hasError)
        service.finishQuery("Street", result: .success([.new]))
        await replacement.value
        XCTAssertEqual(model.suggestions, [.new])
        XCTAssertFalse(model.isSearching)
    }

    func testSupersededSameQuerySearchCannotPublishResultsOrErrors() async {
        let obsoleteReplies: [Result<[AddressSuggestion], Error>] = [
            .success([.old]), .failure(URLError(.notConnectedToInternet))
        ]
        for reply in obsoleteReplies {
            let service = AddressSearchStub()
            let model = AddressSearchViewModel(near: .previewOrigin, service: service)
            model.updateQuery("Street")
            let first = Task { await model.search() }
            await service.waitForQuery("Street")
            let replacement = Task { await model.search() }
            await service.waitForQuery("Street", count: 2)
            service.finishQuery("Street", result: reply)
            await first.value
            XCTAssertTrue(model.suggestions.isEmpty)
            XCTAssertTrue(model.isSearching)
            XCTAssertFalse(model.hasError)
            service.finishQuery("Street", result: .success([.new]))
            await replacement.value
            XCTAssertEqual(model.suggestions, [.new])
            XCTAssertFalse(model.isSearching)
        }
    }

    func testQueryAndRetryPublishLoadingBeforeTheTaskStarts() async {
        let service = AddressSearchStub()
        let model = AddressSearchViewModel(near: .previewOrigin, service: service)
        model.updateQuery("Street")
        XCTAssertTrue(model.isSearching, "Do not briefly show no results before the search task runs")
        let request = Task { await model.search() }
        await service.waitForQuery("Street")
        service.finishQuery("Street", result: .failure(URLError(.notConnectedToInternet)))
        await request.value
        XCTAssertTrue(model.hasError)
        XCTAssertFalse(model.isSearching)
        model.retry()
        XCTAssertFalse(model.hasError)
        XCTAssertTrue(model.isSearching)
        model.updateQuery(" ")
        XCTAssertFalse(model.isSearching, "Clearing the query immediately restores the hint")
    }

    func testOlderQueryCannotReplaceResultsOrEndNewLoading() async {
        let service = AddressSearchStub()
        let model = AddressSearchViewModel(near: .previewOrigin, service: service)
        model.updateQuery("Old")
        let first = Task { await model.search() }
        await service.waitForQuery("Old")
        model.updateQuery("New")
        let second = Task { await model.search() }
        await service.waitForQuery("New")
        service.finishQuery("Old", result: .success([.old]))
        await first.value
        XCTAssertTrue(model.suggestions.isEmpty)
        XCTAssertTrue(model.isSearching)
        service.finishQuery("New", result: .success([.new]))
        await second.value
        XCTAssertEqual(model.suggestions, [.new])
        XCTAssertFalse(model.isSearching)
        XCTAssertEqual(service.lastOrigin, .previewOrigin)
    }

    func testClearingQueryRejectsLateFailure() async {
        let service = AddressSearchStub()
        let model = AddressSearchViewModel(near: .previewOrigin, service: service)
        model.updateQuery("Street")
        let pending = Task { await model.search() }
        await service.waitForQuery("Street")
        model.updateQuery("")
        await model.search()
        service.finishQuery("Street", result: .failure(URLError(.notConnectedToInternet)))
        await pending.value
        XCTAssertFalse(model.hasError)
        XCTAssertFalse(model.isSearching)
        XCTAssertTrue(model.suggestions.isEmpty)
    }

    func testCancelledSelectionNeverReturnsAPoint() async {
        let (model, service) = await populatedModel()
        model.select(.new)
        let pending = Task { await model.resolveSelection() }
        await service.waitForSelection()
        pending.cancel()
        service.finishSelection(.success(.fixture))
        let result = await pending.value
        XCTAssertNil(result)
        XCTAssertNil(model.selectedSuggestion)
        XCTAssertFalse(model.hasError)
    }

    func testChangedQueryRejectsUncancelledSelectionReply() async {
        let (model, service) = await populatedModel()
        model.select(.new)
        let pending = Task { await model.resolveSelection() }
        await service.waitForSelection()
        model.updateQuery("Another street")
        service.finishSelection(.success(.fixture))
        let result = await pending.value
        XCTAssertNil(result)
        XCTAssertNil(model.selectedSuggestion)
        XCTAssertTrue(model.suggestions.isEmpty)
    }

    func testFailedSelectionCanBeRetriedWithoutLosingResults() async {
        let (model, service) = await populatedModel()
        model.select(.new)
        let first = Task { await model.resolveSelection() }
        await service.waitForSelection()
        service.finishSelection(.failure(URLError(.notConnectedToInternet)))
        _ = await first.value
        XCTAssertTrue(model.hasError)
        XCTAssertEqual(model.suggestions, [.new])
        model.select(.new)
        let retry = Task { await model.resolveSelection() }
        await service.waitForSelection()
        service.finishSelection(.success(.fixture))
        let result = await retry.value
        XCTAssertEqual(result, .fixture)
        XCTAssertFalse(model.hasError)
        XCTAssertNil(model.selectedSuggestion)
    }

    func testCancelledResolutionCannotClearAReplacementForTheSameAddress() async {
        let (model, service) = await populatedModel()
        model.select(.new)
        let first = Task { await model.resolveSelection() }
        await service.waitForSelection()
        first.cancel()
        let replacement = Task { await model.resolveSelection() }
        await service.waitForSelection(count: 2)
        service.finishSelection(.success(.fixture))
        let obsoleteResult = await first.value
        XCTAssertNil(obsoleteResult)
        XCTAssertEqual(model.selectedSuggestion, .new)
        service.finishSelection(.success(.fixture))
        let result = await replacement.value
        XCTAssertEqual(result, .fixture)
        XCTAssertNil(model.selectedSuggestion)
    }

    private func populatedModel() async -> (AddressSearchViewModel, AddressSearchStub) {
        let service = AddressSearchStub()
        let model = AddressSearchViewModel(near: .previewOrigin, service: service)
        model.updateQuery("New")
        let request = Task { await model.search() }
        await service.waitForQuery("New")
        service.finishQuery("New", result: .success([.new]))
        await request.value
        return (model, service)
    }
}

private extension AddressSuggestion {
    static let old = Self(title: "Old street", subtitle: "1")
    static let new = Self(title: "New street", subtitle: "2")
}

private extension AddressSearchSelection {
    static let fixture = Self(coordinate: ShoppingCoordinate(latitude: 60.01, longitude: 30.3), address: "New street, 2")
}

@MainActor
private final class AddressSearchStub: AddressSearching {
    private var queries: [String: [CheckedContinuation<[AddressSuggestion], Error>]] = [:]
    private var queryWaiter: (query: String, count: Int, continuation: CheckedContinuation<Void, Never>)?
    private var selections: [CheckedContinuation<AddressSearchSelection, Error>] = []
    private var selectionWaiter: (Int, CheckedContinuation<Void, Never>)?
    private(set) var lastOrigin: ShoppingCoordinate?

    func suggestions(for query: String, near coordinate: ShoppingCoordinate) async throws -> [AddressSuggestion] {
        lastOrigin = coordinate
        return try await withCheckedThrowingContinuation {
            queries[query, default: []].append($0)
            if let waiter = queryWaiter, waiter.query == query, queries[query, default: []].count >= waiter.count {
                queryWaiter = nil
                waiter.continuation.resume()
            }
        }
    }

    func resolve(_ suggestion: AddressSuggestion, near coordinate: ShoppingCoordinate) async throws -> AddressSearchSelection {
        lastOrigin = coordinate
        return try await withCheckedThrowingContinuation {
            selections.append($0)
            if let waiter = selectionWaiter, selections.count >= waiter.0 {
                waiter.1.resume()
                selectionWaiter = nil
            }
        }
    }

    func waitForQuery(_ query: String, count: Int = 1) async {
        if queries[query, default: []].count >= count { return }
        await withCheckedContinuation { queryWaiter = (query, count, $0) }
    }

    func waitForSelection(count: Int = 1) async {
        if selections.count >= count { return }
        await withCheckedContinuation { selectionWaiter = (count, $0) }
    }

    func finishQuery(_ query: String, result: Result<[AddressSuggestion], Error>) {
        queries[query]?.removeFirst().resume(with: result)
    }

    func finishSelection(_ result: Result<AddressSearchSelection, Error>) {
        selections.removeFirst().resume(with: result)
    }
}
