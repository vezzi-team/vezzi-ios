import SwiftUI
import UIKit
import UserNotifications

enum PolkaPalette {
    static let background = Color(red: 0.95, green: 0.95, blue: 0.97)
    static let ink = Color(red: 0.16, green: 0.18, blue: 0.15)
    static let orange = Color(red: 1, green: 0.43, blue: 0.07)
}

struct PolkaMascot: View {
    let asset: String
    var body: some View {
        Group {
            if let picture = UIImage(named: asset) {
                Image(uiImage: picture).resizable().scaledToFit()
            } else {
                // Замени на PNG из Figma в Assets, см. README.
                Text("🧶").font(.system(size: 90)).minimumScaleFactor(0.4)
            }
        }.accessibilityHidden(true)
    }
}

struct PolkaScreenHeader: View {
    let title: String
    let back: () -> Void
    var body: some View {
        ZStack {
            Text(title).font(.title3.weight(.semibold))
            HStack {
                PolkaCircleButton(icon: "chevron.left", label: "Назад", action: back)
                Spacer()
            }
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 0)
    }
}

struct PolkaSheetHeader: View {
    let title: String
    let onClose: () -> Void
    var onSave: (() -> Void)? = nil
    var body: some View {
        ZStack {
            Text(title).font(.headline).padding(.horizontal, 60)
            HStack {
                PolkaCircleButton(icon: "xmark", label: "Закрыть", action: onClose)
                Spacer()
                if let onSave {
                    PolkaCircleButton(icon: "checkmark", label: "Сохранить", blue: true, action: onSave)
                }
            }
        }.padding(.horizontal, 16).padding(.bottom, 8)
    }
}

struct PolkaCircleButton: View {
    let icon: String
    let label: String
    var blue = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if #available(iOS 26.0, *) {
                symbol
                    .glassEffect(
                        .regular
                            .tint(
                                blue
                                    ? Color.blue.opacity(0.28)
                                    : Color.gray.opacity(0.18)
                            )
                            .interactive(),
                        in: Circle()
                    )
            } else {
                symbol
                    .background(.regularMaterial, in: Circle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var symbol: some View {
        Image(systemName: icon)
            .font(.system(size: 23, weight: .medium))
            .foregroundStyle(
                blue
                    ? Color.blue
                    : Color(red: 0.12, green: 0.14, blue: 0.12)
            )
            .frame(width: 46, height: 46)
            .contentShape(Circle())
    }
}

struct PolkaInfoTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.headline)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .padding(16).polkaCard()
        }.buttonStyle(.plain)
    }
}

struct PolkaMenuRow: View {
    let icon: String
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon).font(.title3).frame(width: 20)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
            }.padding(.vertical, 20).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct PolkaOrangeButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                button
                    .buttonStyle(.glassProminent)
            } else {
                button
                    .buttonStyle(.borderedProminent)
            }
        }
        .tint(PolkaPalette.orange)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    private var button: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
    }
}

struct PolkaBottomBar: View {
    let onSelect: (String) -> Void
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                tab("Главная", icon: "diamond.fill", active: true)
                tab("Список", icon: "circle.fill")
                tab("Магазины", icon: "triangle.fill")
            }
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white, lineWidth: 1))
            Button { onSelect("Поиск") } label: {
                Image(systemName: "magnifyingglass").font(.title2)
                    .frame(width: 60, height: 60)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 1))
            }.accessibilityLabel("Поиск")
        }
        .buttonStyle(.plain).foregroundStyle(Color.primary)
        .padding(.horizontal, 20).padding(.bottom, 8).padding(.top, 8)
    }
    private func tab(_ title: String, icon: String, active: Bool = false) -> some View {
        Button { onSelect(title) } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 23))
                Text(title).font(.caption2).foregroundStyle(active ? Color.primary : .secondary)
            }.frame(maxWidth: .infinity)
        }
    }
}

extension View {
    func polkaCard() -> some View {
        self.background(.white, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 10)
    }
}
