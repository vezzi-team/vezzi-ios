import SwiftUI
import UIKit
import UserNotifications

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    var body: some View {
        VStack(spacing: 0) {
            PolkaSheetHeader(title: "О полке", onClose: { dismiss() })
            ScrollView {
                VStack(spacing: 20) {
                    MotiMascotView(
                        state: .idle,
                        isMotionEnabled: false
                    )
                    .frame(height: 160).padding(.bottom, 12)
                    Text("Полка").font(.largeTitle.bold())
                    Text("Ваш список. Лучший вариант.").font(.headline)
                    Text("Сравнивайте стоимость продуктов в ближайших магазинах и выбирайте удобный маршрут за покупками.")
                        .foregroundStyle(.secondary)
                    Text("Версия \(version)").font(.footnote).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center).padding(.horizontal, 32).padding(.top, 110)
            }
        }.padding(.top, 16).background(.white)
    }
}
