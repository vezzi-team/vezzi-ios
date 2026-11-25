import Combine
import Foundation
import SwiftUI

nonisolated enum ShoppingMode: String, CaseIterable, Identifiable {
    case cheaper, faster
    var id: Self { self }
}

extension EnvironmentValues {
    @Entry var preferredShoppingMode: ShoppingMode = .cheaper
    @Entry var hasCompletedShoppingSurvey = false
}

/// Each account and the guest have independent shopping defaults on this device.
@MainActor
final class ShoppingPreferences: ObservableObject {
    @Published private(set) var mode: ShoppingMode = .cheaper
    @Published private(set) var hasCompletedSurvey = false
    private let defaults: UserDefaults
    private(set) var accountID: UUID?
    private var accountChanges: AnyCancellable?

    init(authentication: AuthenticationSession, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        accountChanges = authentication.$identity.map { $0?.user.id }.removeDuplicates()
            .sink { [weak self] id in self?.restore(for: id) }
    }

    nonisolated deinit {}

    func save(_ mode: ShoppingMode, for accountID: UUID?) {
        guard self.accountID == accountID else { return }
        defaults.set(mode.rawValue, forKey: key(for: accountID))
        if self.mode != mode { self.mode = mode }
    }

    func completeSurvey(with mode: ShoppingMode, for accountID: UUID) {
        guard self.accountID == accountID else { return }
        save(mode, for: accountID)
        if !hasCompletedSurvey {
            defaults.set(true, forKey: completionKey(for: accountID))
            hasCompletedSurvey = true
        }
    }

    private func restore(for id: UUID?) {
        accountID = id
        let saved = defaults.string(forKey: key(for: id)).flatMap(ShoppingMode.init(rawValue:))
        mode = saved ?? .cheaper
        hasCompletedSurvey = id.map { defaults.bool(forKey: completionKey(for: $0)) } ?? false
    }

    private func key(for id: UUID?) -> String { "shopping.defaultMode.\(id?.uuidString ?? "guest")" }
    private func completionKey(for id: UUID) -> String { "shopping.survey.completed.\(id.uuidString)" }
}
