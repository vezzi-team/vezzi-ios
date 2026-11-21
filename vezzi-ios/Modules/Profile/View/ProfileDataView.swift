import SwiftUI

struct ProfileDataView: View {
    @ObservedObject private var session: AuthenticationSession
    @StateObject private var viewModel: ProfileViewModel

    init(session: AuthenticationSession) {
        self.session = session
        _viewModel = StateObject(wrappedValue: ProfileViewModel(session: session))
    }

    var body: some View {
        ScrollView {
            if let email = session.user?.email {
                ProfileCard(minHeight: ProfileLayout.fieldHeight, verticalInset: ProfileLayout.cardSpacing) {
                    VStack(alignment: .leading, spacing: ProfileLayout.labelSpacing) {
                        Text(Texts.Profile.Main.email).font(.footnote).foregroundStyle(Color.Label.secondary)
                        Text(verbatim: email).font(.body).textSelection(.enabled)
                    }
                }
                .padding(.horizontal, ProfileLayout.inset)
                .padding(.top, Const.topInset)
            }
        }
        .foregroundStyle(Color.Label.primary)
        .background(Color.Background.iOSPrimary)
        .safeAreaInset(edge: .bottom) {
            PrimaryActionButton(title: Texts.Profile.Settings.signOut, tint: Color.Action.destructive) {
                viewModel.showsSignOutConfirmation = true
            }
            .disabled(session.isSigningOut || session.user == nil)
            .accessibilityIdentifier(AccessibilityID.Profile.signOut)
            .alert(Texts.Profile.Settings.signOutConfirmation, isPresented: $viewModel.showsSignOutConfirmation) {
                Button(Texts.Authentication.cancel, role: .cancel) {}
                Button(Texts.Profile.Settings.confirmSignOut, role: .destructive) {
                    Task { await viewModel.signOut() }
                }
            }
            .tint(Color.Label.primary)
            .tabBarActionWidth()
            .padding(.bottom, Const.bottomInset)
        }
        .alert(Texts.Authentication.errorTitle, isPresented: $viewModel.showsSignOutError) {
            Button(Texts.Authentication.dismissError, role: .cancel) { }
        } message: {
            Text(session.lastError?.message ?? Texts.Authentication.unavailable)
        }
    }

    private enum Const {
        static let topInset: CGFloat = 10
        static let bottomInset: CGFloat = 8
    }
}

#Preview {
    @Previewable @StateObject var session = AuthenticationSession.preview()
    NavigationStack { ProfileDataView(session: session).navigationTitle(Texts.Profile.Main.personalDetails) }
        .task { try? await session.signIn(email: "moti@example.com", password: "preview-only", intent: .signIn, requestID: UUID()) }
}
