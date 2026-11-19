import Combine
import Foundation
import UserNotifications

/// Owns system permission state; preferences themselves remain in the account session.
@MainActor
final class ProfileNotificationsViewModel: ObservableObject {
    @Published private(set) var status: UNAuthorizationStatus?
    @Published private(set) var isRequesting = false
    @Published var showsError = false
    private let previewStatus: UNAuthorizationStatus?
    private var refreshRevision = 0

    init(previewStatus: UNAuthorizationStatus? = nil) {
        self.previewStatus = previewStatus
        status = previewStatus
    }

    nonisolated deinit {}

    func refresh() async {
        guard previewStatus == nil else { return }
        refreshRevision += 1
        let revision = refreshRevision
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard !Task.isCancelled, revision == refreshRevision else { return }
        status = settings.authorizationStatus
    }

    func requestPermission() async {
        guard previewStatus == nil, !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        do {
            _ = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            await refresh()
        } catch {
            if !Task.isCancelled { showsError = true }
        }
    }
}
