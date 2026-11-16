import SwiftUI
import UIKit
import UserNotifications

enum PolkaShoppingMode: String, CaseIterable, Identifiable {
    case balanced, cheapest, fastest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .balanced: return "Баланс цены и времени"
        case .cheapest: return "Выгоднее"
        case .fastest: return "Быстрее"
        }
    }
    var subtitle: String {
        switch self {
        case .balanced: return "Чуть дороже, если заметно ближе"
        case .cheapest: return "Минимальная сумма за весь список"
        case .fastest: return "Один магазин и меньше времени"
        }
    }
}

struct PolkaAddress: Identifiable, Codable {
    var id = UUID()
    var title: String
    var street: String
    var icon: String { title.lowercased() == "дом" ? "house" : "mappin.and.ellipse" }
    static let examples = [
        PolkaAddress(title: "Дом", street: "Ленинский проспект, 6"),
        PolkaAddress(title: "Работа", street: "Улица Вавилова, 19")
    ]
}
