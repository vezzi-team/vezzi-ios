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
            guard let self, self.isRecalculating, let result,
                  let first = result.plans.first,
                  let updated = ShoppingRoutesSnapshot(plans: result.plans, selectedID: first.id,
                                                       origin: list.origin, isSaved: false) else { return }
            self.snapshot = updated
            self.selectedID = updated.selectedID
            self.isRecalculating = false
        }.store(in: &subscriptions)
    }

    nonisolated deinit {}

    var selectedPlan: ShoppingPlan? { isRecalculating ? nil : snapshot.plans.first { $0.id == selectedID } }
    var origin: ShoppingCoordinate { isRecalculating ? list.origin : snapshot.origin }
    var isBusy: Bool { isRecalculating && list.isBusy }
    var failure: String? {
        guard isRecalculating, !list.isBusy else { return nil }
        if list.failure == .offline { return Texts.Routes.offline }
        if list.failure == .authenticationRequired { return Texts.ShoppingList.signInDescription }
        if list.failure != nil { return Texts.ShoppingList.loadError }
        return Texts.ShoppingList.planningProblem(list.planResult?.problem)
    }

    func changeOrigin(_ coordinate: ShoppingCoordinate) {
        guard coordinate.isValid, coordinate != origin else { return }
        isRecalculating = true
        list.setOrigin(coordinate)
        list.setPresented(true)
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
