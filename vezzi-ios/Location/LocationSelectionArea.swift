import Foundation

/// The supported origin area is independent of the store-search radius.
nonisolated struct LocationSelectionArea: Equatable, Sendable {
    let center: ShoppingCoordinate
    let radiusMeters: Double

    // Centered between the catalog's extreme stores; all 20 stores checked on 2026-11-17 fit within 941 m.
    static let supported = Self(center: ShoppingCoordinate(latitude: 60.014550, longitude: 30.256348),
                                radiusMeters: 1_000)

    func contains(_ coordinate: ShoppingCoordinate) -> Bool {
        guard coordinate.isValid else { return false }
        let latitude = radians(center.latitude)
        let otherLatitude = radians(coordinate.latitude)
        let a = pow(sin((otherLatitude - latitude) / 2), 2)
            + cos(latitude) * cos(otherLatitude) * pow(sin(radians(coordinate.longitude - center.longitude) / 2), 2)
        let distance = Const.earthRadius * 2 * asin(sqrt(min(1, max(0, a))))
        return distance <= radiusMeters + Const.boundaryTolerance
    }

    /// Use the same spherical geometry for the visible boundary and the selection check.
    func boundary(vertexCount: Int) -> [ShoppingCoordinate] {
        let latitude = radians(center.latitude)
        let longitude = radians(center.longitude)
        let distance = radiusMeters / Const.earthRadius
        return (0...vertexCount).map { index in
            let bearing = Double(index) / Double(vertexCount) * 2 * .pi
            let pointLatitude = asin(sin(latitude) * cos(distance) + cos(latitude) * sin(distance) * cos(bearing))
            let pointLongitude = longitude + atan2(sin(bearing) * sin(distance) * cos(latitude),
                                                   cos(distance) - sin(latitude) * sin(pointLatitude))
            return ShoppingCoordinate(latitude: pointLatitude * 180 / .pi, longitude: pointLongitude * 180 / .pi)
        }
    }

    private func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private enum Const {
        static let earthRadius = 6_371_008.8
        static let boundaryTolerance = 0.01
    }
}
