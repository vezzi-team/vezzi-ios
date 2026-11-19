import SwiftUI
import UIKit
import UserNotifications

struct NotificationsView: View {
    @ObservedObject private var session: AuthenticationSession
    @StateObject private var viewModel: ProfileNotificationsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(session: AuthenticationSession, previewStatus: UNAuthorizationStatus? = nil) {
        self.session = session
        _viewModel = StateObject(wrappedValue: ProfileNotificationsViewModel(previewStatus: previewStatus))
    }

    var body: some View {
        Group {
            if let status = viewModel.status {
                switch status {
                case .authorized, .provisional, .ephemeral: preferences
                case .notDetermined: permissionContent(denied: false)
                case .denied: permissionContent(denied: true)
                @unknown default: permissionContent(denied: true)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(Color.Label.primary)
        .background(Color.Background.primary)
        .navigationTitle(Texts.Profile.Main.notifications)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ProfileSheetToolbar(onClose: { dismiss() }) }
        .task { await viewModel.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.refresh() } }
        }
        .alert(Texts.Authentication.errorTitle, isPresented: $viewModel.showsError) {
            Button(Texts.Authentication.dismissError, role: .cancel) { }
        } message: { Text(Texts.Profile.Notifications.requestError) }
    }

    private var preferences: some View {
        ScrollView {
            VStack(spacing: Const.spacing) {
                ProfileCard {
                    VStack(spacing: Const.spacing) {
                        preference(Texts.Profile.Notifications.prices,
                                   subtitle: Texts.Profile.Notifications.pricesDescription,
                                   value: $session.preferences.notificationsEnabled,
                                   id: AccessibilityID.Profile.priceAlerts)
                        Divider()
                        preference(Texts.Profile.Notifications.nearby,
                                   subtitle: Texts.Profile.Notifications.nearbyDescription,
                                   value: $session.preferences.nearbyOffersEnabled,
                                   id: AccessibilityID.Profile.nearbyAlerts)
                        Divider()
                        preference(Texts.Profile.Notifications.reminders,
                                   subtitle: Texts.Profile.Notifications.remindersDescription,
                                   value: $session.preferences.listRemindersEnabled,
                                   id: AccessibilityID.Profile.reminders)
                    }
                }
                Text(Texts.Profile.Notifications.localOnly)
                    .appTextStyle(.caption).foregroundStyle(Color.Label.secondary)
            }.padding(Const.inset)
        }
    }

    private func preference(_ title: String, subtitle: String, value: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: Const.textSpacing) {
                Text(title).appTextStyle(.appText, weight: .semibold)
                Text(subtitle).appTextStyle(.caption).foregroundStyle(Color.Label.secondary)
            }
        }
        .tint(.accentColor)
        .padding(.vertical, Const.toggleInset)
        .accessibilityIdentifier(id)
    }

    private func permissionContent(denied: Bool) -> some View {
        ScrollView {
            VStack(spacing: Const.spacing) {
                MotiMascotView(state: .idle, isMotionEnabled: false)
                    .frame(height: Const.mascotHeight)
                Text(denied ? Texts.Profile.Notifications.off : Texts.Profile.Notifications.enable)
                    .appTextStyle(.body, weight: .semibold)
                Text(denied ? Texts.Profile.Notifications.offDescription : Texts.Profile.Notifications.enableDescription)
                    .appTextStyle(.appText).foregroundStyle(Color.Label.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(Const.inset)
            .padding(.top, Const.topInset)
            .frame(maxWidth: Const.maximumWidth)
            .frame(maxWidth: .infinity)
        }
        .safeAreaBar(edge: .bottom) {
            Button {
                if denied {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url) { accepted in
                            if !accepted { viewModel.showsError = true }
                        }
                    }
                } else { Task { await viewModel.requestPermission() } }
            } label: {
                Text(denied ? Texts.Profile.Notifications.openSettings : Texts.Profile.Notifications.allow)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(.accentColor)
            .disabled(viewModel.isRequesting)
            .accessibilityIdentifier(AccessibilityID.Profile.notificationPermission)
            .padding(Const.inset)
        }
    }

    private enum Const {
        static let spacing: CGFloat = 20
        static let textSpacing: CGFloat = 6
        static let inset: CGFloat = 20
        static let toggleInset: CGFloat = 8
        static let topInset: CGFloat = 48
        static let mascotHeight: CGFloat = 140
        static let maximumWidth: CGFloat = 560
    }
}

#Preview("Notifications — allowed") {
    NavigationStack { NotificationsView(session: .preview(), previewStatus: .authorized) }
}

#Preview("Notifications — denied, dark") {
    NavigationStack { NotificationsView(session: .preview(), previewStatus: .denied) }
        .preferredColorScheme(.dark)
}

#Preview("Notifications — first request, large text") {
    NavigationStack { NotificationsView(session: .preview(), previewStatus: .notDetermined) }
        .dynamicTypeSize(.accessibility3)
}
