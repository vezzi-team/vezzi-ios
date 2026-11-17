import Combine
import Foundation

@MainActor
final class LocationPickerViewModel: ObservableObject {
    @Published private(set) var coordinate: ShoppingCoordinate
    @Published private(set) var isLocating = false
    @Published private(set) var error: DeviceLocationError?
    @Published var options: ShoppingRouteOptions
    @Published private(set) var isMoving = false
    @Published private(set) var address: String?
    @Published private(set) var isResolvingAddress = false
    @Published private(set) var isOutsideSelectionArea: Bool
    let selectionArea = LocationSelectionArea.supported
    static let radiusChoices = [500, 750]
    private let service: any DeviceLocating
    private let addressResolver: any AddressResolving
    private var addressRevision = UUID()
    private var locationRevision = UUID()

    init(coordinate: ShoppingCoordinate, options: ShoppingRouteOptions = .init(), service: any DeviceLocating,
         addressResolver: (any AddressResolving)? = nil, address: String? = nil) {
        self.coordinate = coordinate
        self.address = address
        var draftOptions = options
        if let radius = options.radiusMeters, !Self.radiusChoices.contains(radius) {
            draftOptions.radiusMeters = Self.radiusChoices.min { abs($0 - radius) < abs($1 - radius) }
        }
        self.options = draftOptions
        isOutsideSelectionArea = !LocationSelectionArea.supported.contains(coordinate)
        self.service = service
        self.addressResolver = addressResolver ?? MapKitAddressResolver()
    }

    nonisolated deinit {}

    func choose(_ coordinate: ShoppingCoordinate) {
        guard coordinate.isValid else { return }
        locationRevision = UUID()
        if self.coordinate != coordinate {
            self.coordinate = coordinate
            address = nil
            isResolvingAddress = false
            addressRevision = UUID()
        }
        error = nil
        isOutsideSelectionArea = !selectionArea.contains(coordinate)
        if isMoving { isMoving = false }
    }

    func choose(_ selection: AddressSearchSelection) {
        guard selection.coordinate.isValid else { return }
        choose(selection.coordinate)
        addressRevision = UUID()
        address = selection.address
        isResolvingAddress = false
    }

    func beginMoving() {
        locationRevision = UUID()
        isMoving = true
        address = nil
        isResolvingAddress = false
        addressRevision = UUID()
    }

    var canConfirm: Bool { !isMoving && !isLocating && !isOutsideSelectionArea }

    /// Only the boundary crossing is published while panning; coordinates settle after the gesture.
    func updateSelectionAvailability(_ isAvailable: Bool) {
        guard isMoving, isOutsideSelectionArea == isAvailable else { return }
        isOutsideSelectionArea = !isAvailable
    }

    func returnToSelectionArea() { choose(selectionArea.center) }

    /// The view owns cancellation when the point changes, the map moves, or the screen closes.
    func resolveAddress() async {
        guard !isMoving, address == nil else { return }
        let point = coordinate
        let revision = UUID()
        addressRevision = revision
        isResolvingAddress = true
        defer { if addressRevision == revision { isResolvingAddress = false } }
        do {
            try await Task.sleep(for: .milliseconds(350))
            let result = try await addressResolver.address(for: point)
            try Task.checkCancellation()
            guard addressRevision == revision, coordinate == point, !isMoving else { return }
            address = result
        } catch {
            // A missing address never prevents confirming the selected coordinates.
        }
    }

    func locate() async {
        guard !isLocating else { return }
        isLocating = true
        error = nil
        let revision = locationRevision
        defer { isLocating = false }
        do {
            let coordinate = try await service.currentCoordinate()
            try Task.checkCancellation()
            guard locationRevision == revision else { return }
            choose(coordinate)
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, locationRevision == revision else { return }
            self.error = error as? DeviceLocationError ?? .unavailable
        }
    }
}
