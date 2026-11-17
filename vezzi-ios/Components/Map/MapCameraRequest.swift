import Foundation

/// A single user action. A new ID allows the same control to be used repeatedly.
nonisolated struct MapCameraRequest {
    enum Action: Equatable {
        case zoomIn, zoomOut
        case center(ShoppingCoordinate)
    }

    let id = UUID()
    let action: Action
}
