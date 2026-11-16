import SwiftUI
import UIKit
import UserNotifications

struct NotificationsView: View {
    var previewStatus: UNAuthorizationStatus? = nil
    @State private var status: UNAuthorizationStatus?
    @State private var requesting = false
    @State private var errorMessage: String?
    @AppStorage("polka.priceAlerts") private var priceAlerts = true
    @AppStorage("polka.nearbyOffers") private var nearbyOffers = true
    @AppStorage("polka.listReminders") private var listReminders = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            PolkaSheetHeader(title: "Уведомления", onClose: { dismiss() })
            if let current = previewStatus ?? status {
                switch current {
                case .authorized, .provisional, .ephemeral:
                    ScrollView {
                        VStack(spacing: 0) {
                            notificationToggle("Цены снизились", subtitle: "На товары из вашего списка", value: $priceAlerts)
                            Divider()
                            notificationToggle("Акции поблизости", subtitle: "В магазинах рядом с выбранным адресом", value: $nearbyOffers)
                            Divider()
                            notificationToggle("Напоминания о списке", subtitle: "Поможем не забыть запланированные покупки", value: $listReminders)
                        }.padding(.horizontal, 16)
                    }
                case .notDetermined:
                    permissionContent(denied: false)
                case .denied:
                    permissionContent(denied: true)
                @unknown default:
                    permissionContent(denied: true)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, 16).background(.white)
        .task { await refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshStatus() } }
        }
        .alert("Не удалось запросить разрешение", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("ОК", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func notificationToggle(_ title: String, subtitle: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }.padding(.trailing, 12)
        }
        .tint(.green).padding(.horizontal, 16).padding(.vertical, 24)
    }

    private func permissionContent(denied: Bool) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    PolkaMascot(asset: "polkaSleeping").frame(height: 120)
                    Text(denied ? "Уведомления выключены" : "Включите уведомления")
                        .font(.title3.weight(.semibold))
                    Text(denied
                         ? "Разрешите их в настройках iPhone, чтобы узнавать о снижении цен на товары из списка."
                         : "Разрешите уведомления, чтобы узнавать о снижении цен на товары из списка.")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center).padding(.horizontal, 32).padding(.top, 110)
            }
            PolkaOrangeButton(title: denied ? "Открыть настройки" : "Разрешить уведомления") {
                if denied {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } else { Task { await requestPermission() } }
            }
            .disabled(requesting).padding(16)
        }
    }

    @MainActor private func refreshStatus() async {
        guard previewStatus == nil else { return }
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @MainActor private func requestPermission() async {
        requesting = true
        defer { requesting = false }
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshStatus()
        } catch { errorMessage = error.localizedDescription }
    }
}

#Preview("Включены") { NotificationsView(previewStatus: .authorized) }
#Preview("Выключены") { NotificationsView(previewStatus: .denied) }
