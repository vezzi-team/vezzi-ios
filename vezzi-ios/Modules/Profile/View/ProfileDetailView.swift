import SwiftUI

/// Keeps existing typed routes compatible with the redesigned screens.
struct ProfileDetailView: View {
    let destination: ProfileDestination
    @ObservedObject var session: AuthenticationSession

    var body: some View {
        Group {
            switch destination {
            case .personalDetails: PolkaProfileDataView(session: session)
            case .address: AddressesView(session: session)
            case .priority: ShoppingModeView(session: session)
            case .notifications: NotificationsView(session: session)
            case .help: ProfileInformationView(text: Texts.Profile.Support.unavailable)
            case .about: AboutView()
            case .terms: ProfileInformationView(text: Texts.Profile.Information.terms)
            }
        }
    }
}

#Preview("Profile detail route") {
    NavigationStack {
        ProfileDetailView(destination: .personalDetails, session: .preview())
    }
}
