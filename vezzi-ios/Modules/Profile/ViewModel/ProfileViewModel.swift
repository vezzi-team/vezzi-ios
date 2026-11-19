import Combine
import Foundation

/// Owns edit drafts and account actions; AuthenticationSession remains the source of truth.
@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var priority: ProfilePreferences.ShoppingPriority
    @Published private(set) var addresses: [ProfileAddress]
    @Published var editingAddress: ProfileAddress?
    @Published var showsSignOutConfirmation = false
    @Published var showsSignOutError = false
    @Published private(set) var isSigningOut = false

    private let session: AuthenticationSession
    private let sessionID: UUID?

    init(session: AuthenticationSession) {
        self.session = session
        sessionID = session.identity?.sessionID
        priority = session.preferences.priority
        addresses = session.preferences.addresses
    }

    nonisolated deinit {}

    @discardableResult
    func savePriority() -> Bool {
        guard session.identity?.sessionID == sessionID else { return false }
        session.preferences.priority = priority
        return true
    }

    @discardableResult
    func saveAddresses() -> Bool {
        guard session.identity?.sessionID == sessionID, addresses.allSatisfy(\.isValid) else { return false }
        session.preferences.addresses = addresses.map(\.trimmed)
        return true
    }

    func addAddress() {
        editingAddress = ProfileAddress(title: "", street: "")
    }

    func updateAddress(_ address: ProfileAddress) {
        guard address.isValid else { return }
        if let index = addresses.firstIndex(where: { $0.id == address.id }) {
            addresses[index] = address.trimmed
        } else {
            addresses.append(address.trimmed)
        }
        editingAddress = nil
    }

    func signOut() async {
        guard !isSigningOut, session.identity?.sessionID == sessionID else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        do { try await session.signOut() }
        catch { showsSignOutError = true }
    }
}
