import Combine
import Foundation

@MainActor
final class ShoppingRouteViewModel: ObservableObject {
    @Published private(set) var snapshot: ShoppingRoutesSnapshot
    @Published var selectedID: UUID
    @Published private(set) var isRecalculating = false
    @Published private(set) var isLocating = false
    @Published private(set) var deviceCoordinate: ShoppingCoordinate?
    @Published private(set) var locationError: DeviceLocationError?
    private let list: ShoppingListRepository
    private let location: any DeviceLocating
    private var subscriptions = Set<AnyCancellable>()

    init(snapshot: ShoppingRoutesSnapshot, list: ShoppingListRepository, location: any DeviceLocating) {
        self.snapshot = snapshot
        self.selectedID = snapshot.selectedID
        self.list = list
        self.location = location
        list.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        list.$planResult.sink { [weak self] result in
            self?.acceptRecalculation(result)
        }.store(in: &subscriptions)
    }

    nonisolated deinit {}

    var availablePlans: [ShoppingPlan] { isRecalculating ? [] : snapshot.plans }
    var selectedPlan: ShoppingPlan? { availablePlans.first { $0.id == selectedID } }
    var origin: ShoppingCoordinate { isRecalculating ? list.origin : snapshot.origin }
    var originAddress: String? {
        let savedAddress = origin == snapshot.origin ? snapshot.originAddress : nil
        return origin == list.origin ? list.originAddress ?? savedAddress : savedAddress
    }
    var routeOptions: ShoppingRouteOptions { isRecalculating ? list.routeOptions : snapshot.routeOptions }
    var isBusy: Bool { isRecalculating && list.isBusy }
    var canRetry: Bool { isRecalculating && !list.isBusy }

    var statusMessage: String? {
        guard isRecalculating else { return nil }
        let problem = Texts.ShoppingList.planningProblem(for: list.planResult)
        guard !list.isBusy else { return problem }
        switch list.failure {
        case nil: return problem ?? Texts.ShoppingList.noPlans
        case .offline: return [problem, Texts.Routes.offline].compactMap { $0 }.joined(separator: "\n")
        case .authenticationRequired: return Texts.ShoppingList.signInDescription
        default: return Texts.ShoppingList.loadError
        }
    }

    func changeRoute(_ coordinate: ShoppingCoordinate, options: ShoppingRouteOptions, address: String? = nil) {
        guard coordinate.isValid, options.isValid else { return }
        guard coordinate != origin || options != routeOptions || coordinate != list.origin || options != list.routeOptions else {
            list.setRoute(origin: coordinate, options: options, address: address)
            return
        }
        isRecalculating = true
        list.setRoute(origin: coordinate, options: options, address: address)
        // The repository may already have this calculation while the screen retains an older snapshot.
        acceptRecalculation(list.planResult)
        list.setPresented(true)
    }

    private func acceptRecalculation(_ result: ShoppingPlanResult?) {
        guard isRecalculating, let result,
              let updated = ShoppingRoutesSnapshot(plans: snapshot.mode.plans(in: result), mode: snapshot.mode,
                                                   origin: list.origin, isSaved: list.isPlanCached,
                                                   routeOptions: list.routeOptions, originAddress: list.originAddress) else { return }
        snapshot = updated
        selectedID = updated.selectedID
        isRecalculating = false
    }

    func retry() async { await list.refresh() }

    /// Locate the device for the camera only. Route origin changes require the address picker.
    func locate() async -> ShoppingCoordinate? {
        guard !isLocating else { return nil }
        isLocating = true
        locationError = nil
        defer { isLocating = false }
        do {
            let coordinate = try await location.currentCoordinate()
            try Task.checkCancellation()
            guard coordinate.isValid else { throw DeviceLocationError.unavailable }
            deviceCoordinate = coordinate
            return coordinate
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return nil }
            locationError = error as? DeviceLocationError ?? .unavailable
        }
        return nil
    }

    func clearLocationError() { locationError = nil }
}
