import Foundation

/// In-memory values only; the profile API does not expose saved addresses yet.
struct ProfileAddress: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var street: String

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !street.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var trimmed: Self {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.street = street.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }
}

enum ProfileSheet: String, Identifiable, Hashable {
    case shopping, addresses, notifications, about
    var id: Self { self }
    var isCompact: Bool { self == .shopping || self == .addresses }
}
