import Foundation

enum HomeAddress: String, CaseIterable, Identifiable {
    case home
    case work

    var id: Self { self }

    var title: String {
        switch self {
        case .home: return Texts.Home.Mock.homeAddress
        case .work: return Texts.Home.Mock.workAddress
        }
    }
}
