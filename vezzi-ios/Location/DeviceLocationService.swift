import CoreLocation
import Foundation

@MainActor
protocol DeviceLocating: AnyObject {
    func currentCoordinate() async throws -> ShoppingCoordinate
}

nonisolated enum DeviceLocationError: Error {
    case denied, unavailable
}

/// A single, cancellable foreground fix. Never starts continuous or background tracking.
@MainActor
final class DeviceLocationService: NSObject, DeviceLocating, @preconcurrency CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var requestID: UUID?
    private var continuation: CheckedContinuation<ShoppingCoordinate, Error>?
    private var timeout: Task<Void, Never>?

    func currentCoordinate() async throws -> ShoppingCoordinate {
        finish(.failure(CancellationError()))
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let manager = CLLocationManager()
                self.manager = manager
                self.requestID = id
                self.continuation = continuation
                manager.delegate = self
                manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                switch manager.authorizationStatus {
                case .notDetermined: manager.requestWhenInUseAuthorization()
                case .authorizedAlways, .authorizedWhenInUse: requestFix(manager)
                case .denied, .restricted: finish(.failure(DeviceLocationError.denied))
                @unknown default: finish(.failure(DeviceLocationError.unavailable))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.requestID == id else { return }
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === self.manager else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: requestFix(manager)
        case .denied, .restricted: finish(.failure(DeviceLocationError.denied))
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manager === self.manager,
              let location = locations.last(where: { $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 60 }) else { return }
        let coordinate = ShoppingCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        guard coordinate.isValid else { return }
        finish(.success(coordinate))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        guard manager === self.manager else { return }
        finish(.failure((error as? CLError)?.code == .denied ? DeviceLocationError.denied : .unavailable))
    }

    private func requestFix(_ manager: CLLocationManager) {
        guard timeout == nil else { return }
        manager.requestLocation()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            self?.finish(.failure(DeviceLocationError.unavailable))
        }
    }

    private func finish(_ result: Result<ShoppingCoordinate, Error>) {
        timeout?.cancel()
        timeout = nil
        manager?.stopUpdatingLocation()
        manager?.delegate = nil
        manager = nil
        requestID = nil
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }
}
