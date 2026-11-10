import Foundation
import Network

/// Reachability supplements request errors; a satisfied path does not prove a successful refresh.
@MainActor
final class NetworkMonitor {
    private let monitor = NWPathMonitor()

    init(onChange: @escaping @MainActor @Sendable (Bool) -> Void) {
        monitor.pathUpdateHandler = { path in
            let connected = path.status == .satisfied
            Task { @MainActor in onChange(connected) }
        }
        monitor.start(queue: DispatchQueue(label: "Polka.Connectivity", qos: .utility))
    }

    nonisolated deinit { monitor.cancel() }
}
