import MapKit

@MainActor
protocol AddressResolving {
    func address(for coordinate: ShoppingCoordinate) async throws -> String?
}

/// Address lookup is independent of the OpenStreetMap renderer and device-location permission.
struct MapKitAddressResolver: AddressResolving {
    func address(for coordinate: ShoppingCoordinate) async throws -> String? {
        try Task.checkCancellation()
        guard coordinate.isValid,
              let request = MKReverseGeocodingRequest(location: CLLocation(latitude: coordinate.latitude,
                                                                           longitude: coordinate.longitude)) else { return nil }
        request.preferredLocale = .current
        let lookup = Lookup(request)
        return try await withTaskCancellationHandler {
            let items = try await lookup.request.mapItems
            try Task.checkCancellation()
            guard let item = items.first else { return nil }
            return Self.displayAddress(for: item)
        } onCancel: {
            Task { @MainActor in lookup.request.cancel() }
        }
    }

    static func displayAddress(for item: MKMapItem) -> String? {
        let candidates = [item.address?.shortAddress,
                          item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true),
                          item.address?.fullAddress]
        return candidates.compactMap { address in
            address.flatMap { streetAddress($0, city: item.addressRepresentations?.cityName) }
        }.first
    }

    /// Remove only complete address components matching the resolved city, never street substrings.
    static func streetAddress(_ address: String, city: String?) -> String? {
        let city = city?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cityNames = city.map { [$0, "г. \($0)", "г \($0)"] } ?? []
        let parts = address.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { part in
                !part.isEmpty && !cityNames.contains { part.caseInsensitiveCompare($0) == .orderedSame }
            }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Keep the framework request on the main actor, including cancellation from another executor.
    @MainActor private final class Lookup {
        let request: MKReverseGeocodingRequest
        init(_ request: MKReverseGeocodingRequest) { self.request = request }
    }
}

struct PreviewAddressResolver: AddressResolving {
    func address(for coordinate: ShoppingCoordinate) async throws -> String? { Texts.ShoppingList.mockAddress }
}
