import Combine
import Foundation

@MainActor
final class LocationPickerViewModel: ObservableObject {
    @Published private(set) var coordinate: ShoppingCoordinate
    @Published private(set) var isLocating = false
    @Published private(set) var error: DeviceLocationError?
    private let service: any DeviceLocating

    init(coordinate: ShoppingCoordinate, service: any DeviceLocating) {
        self.coordinate = coordinate
        self.service = service
    }

    func choose(_ coordinate: ShoppingCoordinate) {
        guard coordinate.isValid else { return }
        self.coordinate = coordinate
        error = nil
    }

    func locate() async {
        guard !isLocating else { return }
        isLocating = true
        error = nil
        defer { isLocating = false }
        do {
            let coordinate = try await service.currentCoordinate()
            try Task.checkCancellation()
            choose(coordinate)
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error as? DeviceLocationError ?? .unavailable
        }
    }
}
