import SwiftUI

struct ProfileView: View {
    @ObservedObject var session: AuthenticationSession

    var body: some View {
        List {
            if let error = session.lastError { sessionStatus(error) }
            Section {
                personalDetails
            } header: {
                Text(Texts.Profile.Main.subtitle)
                    .appTextStyle(.caption)
                    .foregroundStyle(Color.Label.secondary)
                    .textCase(nil)
            }
            shoppingSection
            settingsSection
            debugSection
            terms
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Const.sectionSpacing)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(Color.Background.primary)
        .navigationBarTitleDisplayMode(.large)
        .appTextStyle(.appText)
        .foregroundStyle(Color.Label.primary)
        .accessibilityIdentifier(AccessibilityID.Profile.screen)
    }

    private var personalDetails: some View {
        NavigationLink(value: AppRouter.Route.profileDetails(.personalDetails)) {
            HStack(spacing: Const.rowSpacing) {
                Circle()
                    .fill(Color.Background.placeholder)
                    .frame(width: Const.avatarSize, height: Const.avatarSize)
                    .shimmer()
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Const.captionSpacing) {
                    Text(Texts.Profile.Main.yourProfile)
                        .appTextStyle(.body, weight: .semibold)
                    Text(Texts.Profile.Main.personalDetails)
                        .appTextStyle(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, Const.profileInset)
        }
        .listRowBackground(Color.Background.elevated)
        .accessibilityIdentifier(AccessibilityID.Profile.personalDetails)
    }

    private func sessionStatus(_ error: AuthenticationFailure) -> some View {
        Section {
            Text(error.message)
                .foregroundStyle(Color.Label.secondary)
            Button(Texts.Authentication.retry) {
                Task { await session.restore(force: true) }
            }
            .disabled(session.isVerifying || session.isSigningOut)
        }
        .listRowBackground(Color.Background.elevated)
    }

    private var shoppingSection: some View {
        Section {
            row(.address, subtitle: session.preferences.address)
            row(.priority, subtitle: session.preferences.priority.title)
        } header: {
            sectionTitle(Texts.Profile.Main.shopping)
        }
        .listRowBackground(Color.Background.elevated)
    }

    private var settingsSection: some View {
        Section {
            NavigationLink(value: AppRouter.Route.profileDetails(.notifications)) {
                LabeledContent(Texts.Profile.Main.notifications,
                               value: session.preferences.notificationsEnabled
                               ? Texts.Profile.Settings.enabled : Texts.Profile.Settings.disabled)
            }
            .accessibilityIdentifier(AccessibilityID.Profile.destination(ProfileDestination.notifications.rawValue))
            row(.help)
            row(.about)
        } header: {
            sectionTitle(Texts.Profile.Main.settings)
        }
        .listRowBackground(Color.Background.elevated)
    }

    private var debugSection: some View {
        Section {
            NavigationLink(value: AppRouter.Route.motiDebug) {
                Text(Texts.Debug.Moti.title)
            }
            .accessibilityIdentifier(AccessibilityID.Profile.motiDebug)
        } header: {
            sectionTitle(Texts.Profile.Main.debug)
        }
        .listRowBackground(Color.Background.elevated)
    }

    private var terms: some View {
        Section {
            NavigationLink(value: AppRouter.Route.profileDetails(.terms)) {
                Text(Texts.Profile.Main.terms)
                    .appTextStyle(.caption)
                    .foregroundStyle(Color.accentColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
            .accessibilityIdentifier(AccessibilityID.Profile.destination(ProfileDestination.terms.rawValue))
        }
    }

    private func row(_ destination: ProfileDestination, subtitle: String? = nil) -> some View {
        NavigationLink(value: AppRouter.Route.profileDetails(destination)) {
            VStack(alignment: .leading, spacing: Const.captionSpacing) {
                Text(destination.title)
                if let subtitle {
                    Text(subtitle)
                        .appTextStyle(.caption)
                        .foregroundStyle(Color.Label.secondary)
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.Profile.destination(destination.rawValue))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .appTextStyle(.body, weight: .semibold)
            .foregroundStyle(Color.Label.primary)
            .textCase(nil)
    }

    private enum Const {
        static let sectionSpacing: CGFloat = 24
        static let rowSpacing: CGFloat = 16
        static let captionSpacing: CGFloat = 4
        static let avatarSize: CGFloat = 52
        static let profileInset: CGFloat = 6
    }
}

#Preview("Profile") {
    NavigationStack {
        ProfileView(session: AuthenticationSession.preview())
            .navigationTitle(Texts.Profile.Main.title)
    }
}

#Preview("Profile — dark") {
    NavigationStack {
        ProfileView(session: AuthenticationSession.preview())
            .navigationTitle(Texts.Profile.Main.title)
    }
    .preferredColorScheme(.dark)
}
