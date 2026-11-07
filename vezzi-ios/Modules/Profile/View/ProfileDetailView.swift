import SwiftUI

/// Native editors for the temporary profile preferences. Values live only in the session.
struct ProfileDetailView: View {
    let destination: ProfileDestination
    @ObservedObject var session: AuthenticationSession
    @State private var showsSignOutConfirmation = false
    @State private var showsSignOutError = false

    var body: some View {
        Form { content }
            .appTextStyle(.appText)
            .foregroundStyle(Color.Label.primary)
            .scrollContentBackground(.hidden)
            .background(Color.Background.primary)
            .confirmationDialog(Texts.Profile.Settings.signOutConfirmation,
                                isPresented: $showsSignOutConfirmation, titleVisibility: .visible) {
                Button(Texts.Profile.Settings.signOut, role: .destructive) {
                    Task {
                        do { try await session.signOut() }
                        catch { showsSignOutError = true }
                    }
                }
                    .accessibilityIdentifier(AccessibilityID.Profile.confirmSignOut)
                Button(Texts.Authentication.cancel, role: .cancel) { }
            }
            .alert(Texts.Authentication.errorTitle, isPresented: $showsSignOutError) {
                Button(Texts.Authentication.dismissError, role: .cancel) { }
            } message: {
                Text(session.lastError?.message ?? Texts.Authentication.unavailable)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .personalDetails: personalDetails
        case .address: address
        case .priority: priority
        case .notifications: notifications
        case .help: information(Texts.Profile.Information.help)
        case .about: about
        case .terms: information(Texts.Profile.Information.terms)
        }
    }

    private var personalDetails: some View {
        Group {
            Section {
                LabeledContent(Texts.Authentication.email, value: session.user?.email ?? "")
                    .textSelection(.enabled)
            }
            .listRowBackground(Color.Background.elevated)
            Section {
                Button(Texts.Profile.Settings.signOut, role: .destructive) { showsSignOutConfirmation = true }
                    .disabled(session.isSigningOut)
                    .accessibilityIdentifier(AccessibilityID.Profile.signOut)
            }
            .listRowBackground(Color.Background.elevated)
        }
    }

    private var address: some View {
        Section {
            TextField(Texts.Profile.Main.address, text: $session.preferences.address, axis: .vertical)
                .textContentType(.fullStreetAddress)
                .accessibilityIdentifier(AccessibilityID.Profile.address)
        }
        .listRowBackground(Color.Background.elevated)
    }

    private var priority: some View {
        Section {
            Picker(Texts.Profile.Main.priority, selection: $session.preferences.priority) {
                ForEach(ProfilePreferences.ShoppingPriority.allCases) { priority in
                    Text(priority.title).tag(priority)
                }
            }
            .pickerStyle(.inline)
        }
        .listRowBackground(Color.Background.elevated)
    }

    private var notifications: some View {
        Section {
            Toggle(Texts.Profile.Main.notifications, isOn: $session.preferences.notificationsEnabled)
                .accessibilityIdentifier(AccessibilityID.Profile.notifications)
        } footer: {
            Text(Texts.Profile.Information.notifications)
        }
        .listRowBackground(Color.Background.elevated)
    }

    private var about: some View {
        Section {
            Text(Texts.AppInfo.title).appTextStyle(.body, weight: .semibold)
            LabeledContent(Texts.Profile.Information.version,
                           value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            Text(Texts.Profile.Information.about)
        }
        .listRowBackground(Color.Background.elevated)
    }

    private func information(_ text: String) -> some View {
        Section { Text(text) }
            .listRowBackground(Color.Background.elevated)
    }
}

#Preview("Preferences") {
    NavigationStack {
        ProfileDetailView(destination: .priority, session: AuthenticationSession.preview())
            .navigationTitle(Texts.Profile.Main.priority)
    }
}
