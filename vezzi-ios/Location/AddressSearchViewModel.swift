import Combine
import Foundation

@MainActor
final class AddressSearchViewModel: ObservableObject {
    @Published private(set) var query = ""
    @Published private(set) var requestID = UUID()
    @Published private(set) var suggestions: [AddressSuggestion] = []
    @Published private(set) var isSearching = false
    @Published private(set) var hasError = false
    @Published private(set) var selectedSuggestion: AddressSuggestion?
    private let service: any AddressSearching
    private let origin: ShoppingCoordinate
    private var searchID = UUID()
    private var resolutionID = UUID()

    init(near origin: ShoppingCoordinate, service: any AddressSearching) {
        self.origin = origin
        self.service = service
    }

    // Avoid an isolated deinit on early iOS 26 runtimes (Swift issue #88036).
    nonisolated deinit {}

    var canSearch: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).count >= Const.minimumQueryLength }

    func updateQuery(_ query: String) {
        guard self.query != query else { return }
        self.query = query
        suggestions = []
        selectedSuggestion = nil
        retry()
    }

    func retry() {
        hasError = false
        // Publish loading with the new request so the empty state cannot flash before the task starts.
        isSearching = canSearch
        requestID = UUID()
    }

    func search() async {
        guard !Task.isCancelled else { return }
        let revision = requestID
        let search = UUID()
        searchID = search
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSearch else { isSearching = false; return }
        isSearching = true
        hasError = false
        defer { if searchID == search, requestID == revision { isSearching = false } }
        do {
            try await Task.sleep(for: .milliseconds(Const.debounceMilliseconds))
            let result = try await service.suggestions(for: query, near: origin)
            try Task.checkCancellation()
            guard searchID == search, requestID == revision else { return }
            suggestions = result
        } catch {
            guard !Task.isCancelled, searchID == search, requestID == revision else { return }
            hasError = true
        }
    }

    func select(_ suggestion: AddressSuggestion) {
        guard selectedSuggestion == nil, suggestions.contains(suggestion) else { return }
        hasError = false
        selectedSuggestion = suggestion
    }

    func resolveSelection() async -> AddressSearchSelection? {
        guard !Task.isCancelled, let suggestion = selectedSuggestion else { return nil }
        let revision = requestID
        let resolution = UUID()
        resolutionID = resolution
        defer {
            if resolutionID == resolution, requestID == revision, selectedSuggestion == suggestion {
                selectedSuggestion = nil
            }
        }
        do {
            let result = try await service.resolve(suggestion, near: origin)
            try Task.checkCancellation()
            guard resolutionID == resolution, requestID == revision, selectedSuggestion == suggestion else { return nil }
            return result
        } catch {
            guard !Task.isCancelled, resolutionID == resolution, requestID == revision else { return nil }
            hasError = true
            return nil
        }
    }

    private enum Const {
        static let minimumQueryLength = 2
        static let debounceMilliseconds = 250
    }
}
