import SwiftUI
import UIKit
import UserNotifications

enum ProfileSheet: String, Identifiable {
    case shopping, addresses, notifications, about
    var id: String { rawValue }
    var isCompact: Bool { self == .shopping || self == .addresses }
}

struct ProfileView: View {
    var name = "onton"
    var email = "test@test.test"
    var phone = "+7 123 (456) 78 91"
    var onBack: (() -> Void)? = nil
    var onTab: ((String) -> Void)? = nil
    var onContact: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var sheet: ProfileSheet?
    @State private var showDetails = false
    @State private var demoMessage: String?
    @AppStorage("polka.shoppingMode") private var mode: PolkaShoppingMode = .balanced
    @AppStorage("polka.addresses") private var addressesData = Data()

    private var addresses: [PolkaAddress] {
        (try? JSONDecoder().decode([PolkaAddress].self, from: addressesData))
            ?? PolkaAddress.examples
    }

    var body: some View {
        Group {
            VStack(spacing: 0) {
                PolkaScreenHeader(title: "Профиль") {
                    if let onBack { onBack() } else { dismiss() }
                }
                ScrollView {
                    VStack(spacing: 12) {
                        Button { showDetails = true } label: {
                            HStack(spacing: 14) {
                                Text(String(name.prefix(1)).uppercased())
                                    .font(.title3.weight(.semibold))
                                    .frame(width: 52, height: 52)
                                    .background(PolkaPalette.orange, in: Circle())
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(name).font(.title3.weight(.semibold))
                                    Text(email).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                            }
                            .padding(16).frame(maxWidth: .infinity, minHeight: 92)
                            .polkaCard()
                        }.buttonStyle(.plain)
                        HStack(alignment: .top, spacing: 12) {
                            PolkaInfoTile(icon: "mappin.and.ellipse", title: "Мои адреса",
                                     subtitle: addresses.first?.street ?? "Добавьте адрес") {
                                sheet = .addresses
                            }
                            PolkaInfoTile(icon: "point.3.connected.trianglepath.dotted",
                                     title: "Как покупать", subtitle: mode.title) {
                                sheet = .shopping
                            }
                        }
                        VStack(spacing: 0) {
                            PolkaMenuRow(icon: "gearshape", title: "Уведомления") { sheet = .notifications }
                            Divider().padding(.leading, 54)
                            PolkaMenuRow(icon: "person", title: "О Полке") { sheet = .about }
                        }
                        .padding(.horizontal, 16).polkaCard().padding(.top, 12)

                        Button {
                            if let onContact {
                                onContact()
                            } else {
                                demoMessage = "Контакт поддержки пока не подключён."
                            }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Связаться с нами")
                                        .font(.headline)
                                        .foregroundStyle(PolkaPalette.ink)

                                    Text("Поможем разобраться\nс ценами и покупками")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                MotiMascotView(
                                    state: .idle,
                                    isMotionEnabled: false
                                )
                                .frame(width: 100, height: 76)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .polkaCard()
                            .contentShape(RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                        .accessibilityLabel("Связаться с нами")
                        .accessibilityHint("Обратиться в поддержку")
                    }
                    .padding(16)
                }
            }
            .background(PolkaPalette.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showDetails) {
                PolkaProfileDataView(
                    name: name,
                    email: email,
                    phone: phone,
                    onTab: handleTab
                )
            }
            .sheet(item: $sheet) { item in
                Group {
                    switch item {
                    case .shopping:
                        ShoppingModeView(selection: $mode)
                    case .addresses:
                        AddressesView(addresses: addresses) { updated in
                            if let data = try? JSONEncoder().encode(updated) { addressesData = data }
                        }
                    case .notifications:
                        NotificationsView()
                    case .about:
                        AboutView()
                    }
                }
                .presentationDetents(item.isCompact ? [.height(430), .large] : [.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(36)
                .presentationBackground(item.isCompact ? .ultraThinMaterial : .regularMaterial)
            }
            .alert("Демо", isPresented: Binding(
                get: { demoMessage != nil }, set: { if !$0 { demoMessage = nil } }
            )) {
                Button("Понятно", role: .cancel) { demoMessage = nil }
            } message: { Text(demoMessage ?? "") }
        }
        .tint(PolkaPalette.orange)
        .foregroundStyle(PolkaPalette.ink)
        .preferredColorScheme(.light)
    }

    private var bottomBar: some View { PolkaBottomBar(onSelect: handleTab) }
    private func handleTab(_ title: String) {
        if let onTab { onTab(title) }
        else { demoMessage = "Подключите экран «\(title)» в замыкании onTab." }
    }
}

#Preview("Профиль") { ProfileView() }
