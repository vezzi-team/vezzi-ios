import Foundation

struct HomeProduct: Identifiable {
    let id: String
    let name: String
    let brand: String
    let package: String
    let category: HomeProductCategory
    let offers: [HomeStoreOffer]

    var lowestPrice: Decimal? { offers.map(\.price).min() }
}

enum HomeProductCategory: String, CaseIterable, Identifiable {
    case dairy
    case produce
    case bakery
    case pantry
    case eggs

    var id: Self { self }
}

struct HomeStoreOffer: Identifiable {
    let id: String
    let name: String
    let price: Decimal
    let distance: Measurement<UnitLength>
}

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
