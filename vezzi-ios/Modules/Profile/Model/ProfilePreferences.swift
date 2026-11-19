import Foundation

struct ProfilePreferences {
    var addresses: [ProfileAddress] = []
    // Compatibility for existing native editors; the first address is the summary.
    var address: String {
        get { addresses.first?.street ?? "" }
        set {
            if addresses.isEmpty {
                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    addresses.append(ProfileAddress(title: Texts.Profile.Addresses.home, street: newValue))
                }
            } else {
                addresses[0].street = newValue
            }
        }
    }
    var priority: ShoppingPriority = .balanced
    var notificationsEnabled = true
    var nearbyOffersEnabled = true
    var listRemindersEnabled = false

    enum ShoppingPriority: String, CaseIterable, Identifiable {
        case balanced
        case price
        case time

        var id: Self { self }

        var title: String {
            switch self {
            case .balanced: return Texts.Profile.Settings.balanced
            case .price: return Texts.Profile.Settings.lowestPrice
            case .time: return Texts.Profile.Settings.fastest
            }
        }
    }
}

enum ProfileDestination: String, Hashable {
    case personalDetails
    case address
    case priority
    case notifications
    case help
    case about
    case terms

    var title: String {
        switch self {
        case .personalDetails: return Texts.Profile.Main.personalDetails
        case .address: return Texts.Profile.Main.address
        case .priority: return Texts.Profile.Main.priority
        case .notifications: return Texts.Profile.Main.notifications
        case .help: return Texts.Profile.Main.help
        case .about: return Texts.Profile.Main.about
        case .terms: return Texts.Profile.Main.terms
        }
    }
}
