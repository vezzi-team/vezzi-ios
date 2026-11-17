import MapKit

nonisolated struct AddressSuggestion: Identifiable, Equatable {
    let title: String
    let subtitle: String
    var id: String { title + "\u{1F}" + subtitle }
}

nonisolated struct AddressSearchSelection: Equatable {
    let coordinate: ShoppingCoordinate
    let address: String
}

@MainActor
protocol AddressSearching {
    func suggestions(for query: String, near coordinate: ShoppingCoordinate) async throws -> [AddressSuggestion]
    func resolve(_ suggestion: AddressSuggestion, near coordinate: ShoppingCoordinate) async throws -> AddressSearchSelection
}

@MainActor
final class MapKitAddressSearch: AddressSearching {
    private var completions: [String: MKLocalSearchCompletion] = [:]

    func suggestions(for query: String, near coordinate: ShoppingCoordinate) async throws -> [AddressSuggestion] {
        let request = CompletionRequest(region: region(around: coordinate))
        let results = try await withTaskCancellationHandler {
            try await request.results(for: query)
        } onCancel: {
            Task { @MainActor in request.cancel() }
        }
        try Task.checkCancellation()
        completions.removeAll(keepingCapacity: true)
        var suggestions: [AddressSuggestion] = []
        for result in results {
            let suggestion = AddressSuggestion(title: result.title, subtitle: result.subtitle)
            guard completions[suggestion.id] == nil else { continue }
            completions[suggestion.id] = result
            suggestions.append(suggestion)
            if suggestions.count == Const.resultLimit { break }
        }
        return suggestions
    }

    func resolve(_ suggestion: AddressSuggestion, near coordinate: ShoppingCoordinate) async throws -> AddressSearchSelection {
        try Task.checkCancellation()
        guard let completion = completions[suggestion.id] else { throw SearchError.unavailable }
        let request = MKLocalSearch.Request(completion: completion)
        request.region = region(around: coordinate)
        request.resultTypes = .address
        let lookup = SearchRequest(request)
        return try await withTaskCancellationHandler {
            let response = try await lookup.search.start()
            try Task.checkCancellation()
            guard let item = response.mapItems.first else { throw SearchError.unavailable }
            let point = ShoppingCoordinate(latitude: item.location.coordinate.latitude,
                                           longitude: item.location.coordinate.longitude)
            guard point.isValid else { throw SearchError.unavailable }
            return AddressSearchSelection(coordinate: point,
                                          address: MapKitAddressResolver.displayAddress(for: item) ?? suggestion.title)
        } onCancel: {
            Task { @MainActor in lookup.search.cancel() }
        }
    }

    private func region(around coordinate: ShoppingCoordinate) -> MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                           latitudinalMeters: Const.regionSize, longitudinalMeters: Const.regionSize)
    }

    private enum SearchError: Error { case unavailable }
    private enum Const {
        static let resultLimit = 8
        static let regionSize: CLLocationDistance = 20_000
    }

    @MainActor private final class SearchRequest {
        let search: MKLocalSearch
        init(_ request: MKLocalSearch.Request) { search = MKLocalSearch(request: request) }
    }

    /// A delegate belongs to one query, so a cancelled query cannot publish another query's results.
    @MainActor private final class CompletionRequest: NSObject, MKLocalSearchCompleterDelegate {
        private let completer = MKLocalSearchCompleter()
        private var continuation: CheckedContinuation<[MKLocalSearchCompletion], Error>?

        init(region: MKCoordinateRegion) {
            super.init()
            completer.region = region
            completer.regionPriority = .default
            completer.resultTypes = .address
            completer.delegate = self
        }

        func results(for query: String) async throws -> [MKLocalSearchCompletion] {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation {
                continuation = $0
                completer.queryFragment = query
            }
        }

        func cancel() {
            completer.cancel()
            finish(.failure(CancellationError()))
        }

        func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) { finish(.success(completer.results)) }
        func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) { finish(.failure(error)) }

        private func finish(_ result: Result<[MKLocalSearchCompletion], Error>) {
            completer.delegate = nil
            let pending = continuation
            continuation = nil
            pending?.resume(with: result)
        }
    }
}

struct PreviewAddressSearch: AddressSearching {
    func suggestions(for query: String, near coordinate: ShoppingCoordinate) async throws -> [AddressSuggestion] {
        [AddressSuggestion(title: Texts.ShoppingList.mockAddress, subtitle: "12")]
    }
    func resolve(_ suggestion: AddressSuggestion, near coordinate: ShoppingCoordinate) async throws -> AddressSearchSelection {
        AddressSearchSelection(coordinate: coordinate, address: suggestion.title)
    }
}
