import Combine
import Foundation
import SwiftUI

nonisolated enum ShoppingMode: String, CaseIterable, Identifiable {
    case cheaper, faster
    var id: Self { self }
}

extension EnvironmentValues {
    @Entry var preferredShoppingMode: ShoppingMode = .cheaper
}

/// The shopping default belongs to the account and survives a new sign-in on this device.
@MainActor
final class ShoppingPreferences: ObservableObject {
    @Published private(set) var mode: ShoppingMode = .cheaper
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
        guard let accountID, self.accountID == accountID else { return }
        defaults.set(mode.rawValue, forKey: key(for: accountID))
        if self.mode != mode { self.mode = mode }
    }

    private func restore(for id: UUID?) {
        accountID = id
        let saved = id.flatMap { defaults.string(forKey: key(for: $0)) }.flatMap(ShoppingMode.init(rawValue:))
        mode = saved ?? .cheaper
    }

    private func key(for id: UUID) -> String { "shopping.defaultMode.\(id.uuidString)" }
}
