import SwiftUI

struct PolkaProfileDataView: View {
    @ObservedObject private var session: AuthenticationSession
    @StateObject private var viewModel: ProfileViewModel

    init(session: AuthenticationSession) {
        self.session = session
        _viewModel = StateObject(wrappedValue: ProfileViewModel(session: session))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Const.spacing) {
                field(Texts.Profile.Details.name, value: Texts.Profile.Details.notProvided)
                field(Texts.Authentication.email, value: session.user?.email ?? Texts.Profile.Details.notProvided)
                field(Texts.Profile.Details.phone, value: Texts.Profile.Details.notProvided)
                Text(Texts.Profile.Details.unavailableFields)
                    .appTextStyle(.caption).foregroundStyle(Color.Label.secondary)
                Button(Texts.Profile.Settings.signOut, role: .destructive) {
                    viewModel.showsSignOutConfirmation = true
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(session.isSigningOut || viewModel.isSigningOut || session.user == nil)
                .accessibilityIdentifier(AccessibilityID.Profile.signOut)
                if viewModel.isSigningOut { ProgressView() }
            }
            .padding(Const.inset)
            .frame(maxWidth: Const.maximumWidth)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Color.Label.primary)
        .background(Color.Background.primary)
        .confirmationDialog(Texts.Profile.Settings.signOutConfirmation,
                            isPresented: $viewModel.showsSignOutConfirmation, titleVisibility: .visible) {
            Button(Texts.Profile.Settings.signOut, role: .destructive) {
                Task { await viewModel.signOut() }
            }.accessibilityIdentifier(AccessibilityID.Profile.confirmSignOut)
            Button(Texts.Authentication.cancel, role: .cancel) { }
        }
        .alert(Texts.Authentication.errorTitle, isPresented: $viewModel.showsSignOutError) {
            Button(Texts.Authentication.dismissError, role: .cancel) { }
        } message: {
            Text(session.lastError?.message ?? Texts.Authentication.unavailable)
        }
    }

    private func field(_ title: String, value: String) -> some View {
        ProfileCard {
            VStack(alignment: .leading, spacing: Const.textSpacing) {
                Text(title).appTextStyle(.caption).foregroundStyle(Color.Label.secondary)
                Text(value).appTextStyle(.appText).textSelection(.enabled)
            }
        }
    }

    private enum Const {
        static let inset: CGFloat = 16
        static let spacing: CGFloat = 12
        static let textSpacing: CGFloat = 6
        static let maximumWidth: CGFloat = 680
    }
}

#Preview("Account details") {
    NavigationStack {
        PolkaProfileDataView(session: .preview()).navigationTitle(Texts.Profile.Main.personalDetails)
    }
}
