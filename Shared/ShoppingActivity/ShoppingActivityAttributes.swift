import ActivityKit
import Foundation

nonisolated struct ShoppingActivityAttributes: ActivityAttributes {
    let sessionID: UUID
    let planID: UUID

    private static let progressBaseURL = URL(string: "polka://shopping-progress")!

    var progressURL: URL { Self.progressBaseURL.appending(path: planID.uuidString) }

    static func planID(from url: URL) -> UUID? {
        guard url.scheme == progressBaseURL.scheme, url.host() == progressBaseURL.host() else { return nil }
        return UUID(uuidString: String(url.path().dropFirst()))
    }

    enum Stage: String, Codable, Hashable {
        case walking, shopping, returning, summary, finishing
    }

    struct ContentState: Codable, Hashable {
        let stage: Stage
        let storeID: String?
        let storeName: String?
        var storeLogo: Data?
        let bought: Int
        let total: Int
        let spent: Decimal
    }
}
