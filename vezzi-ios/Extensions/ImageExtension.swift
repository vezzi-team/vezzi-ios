//
//  ImageExtension.swift
//  vezzi-ios
//
//  Created by Roman Tverdohleb on 01.11.2026.
//

import SwiftUI
import UIKit

extension Image {
    enum Survey {
        static func illustration(for question: SurveyQuestion) -> Image {
            switch question {
            case .priority: Image(.surveyPriority)
            case .distance: Image(.surveyDistance)
            case .basket: Image(.surveyBasket)
            case .household: Image(.surveyHousehold)
            case .schedule: Image(.surveySchedule)
            case .routine: Image(.surveyRoutine)
            }
        }

        static func icon(for answer: SurveyAnswer, in question: SurveyQuestion) -> Image? {
            switch answer {
            case .save: Image(.surveySave)
            case .time: Image(.surveyTime)
            case .balance: Image(.surveyBalance)
            case .situation: Image(.surveyVaries)
            case .today: Image(.surveyToday)
            case .days: Image(.surveyDays)
            case .stock: Image(.surveyStock)
            case .varies: question == .basket ? Image(.surveyShuffle) : Image(.surveyVaries)
            case .myself: Image(.surveySelf)
            case .pair: Image(.surveyPair)
            case .family: Image(.surveyFamily)
            default: nil
            }
        }

        static let happyFace = Image(.surveyHappyFace)
        static let receiptEdge = Image(.surveyReceiptEdge)
    }

    enum Glyph {
        static let home = Image(.glyphHome)
        static let list = Image(.glyphList)
        static let catalog = Image(.glyphCatalog)
        static let profile = Image(.glyphProfile)
    }

    enum Onboarding {
        static let catalog = Image("OnboardingCatalog")
        static let comparison = Image("OnboardingComparison")
        static let shopping = Image("OnboardingShopping")
        static let routes = Image("OnboardingRoutes")
    }

    enum CollectionCover {
        static func image(for collection: MotiCollection) -> Image {
            switch collection {
            case .pasta: Image(.motiCollectionPasta)
            case .movies: Image(.motiCollectionMovies)
            case .salad: Image(.motiCollectionSalad)
            }
        }
    }

    // MARK: - SF Symbols

    enum System {
        static let location = Image(systemName: "location")
        static let locationFill = Image(systemName: "location.fill")
        static let profileDebug = Image(systemName: "ladybug")
        static let repeatSurvey = Image(systemName: "arrow.triangle.2.circlepath")
        static let walk = Image(systemName: "figure.walk")
        static let chevronRight = Image(systemName: "chevron.right")
        static let chevronLeft = Image(systemName: "chevron.left")
        static let chevronDown = Image(systemName: "chevron.down")
        static let xmark = Image(systemName: "xmark")
        static let arrowRight = Image(systemName: "arrow.right")
        static let arrowUp = Image(systemName: "arrow.up")
        static let arrowUpArrowDown = Image(systemName: "arrow.up.arrow.down")
        static let priceDecrease = rotatedSymbol("line.3.horizontal.decrease")
        static let priceIncrease = Image(systemName: "line.3.horizontal.decrease")
        static let arrowsInward = Image(systemName: "arrow.down.right.and.arrow.up.left")
        static let arrowsOutward = Image(systemName: "arrow.up.left.and.arrow.down.right")
        static let checkmark = Image(systemName: "checkmark")
        static let checkmarkCircle = Image(systemName: "checkmark.circle.fill")
        static let plus = Image(systemName: "plus")
        static let minus = Image(systemName: "minus")
        static let magnifyingGlass = Image(systemName: "magnifyingglass")

        private static func rotatedSymbol(_ name: String) -> Image {
            guard let symbol = UIImage(systemName: name) else { return Image(systemName: name) }
            let image = UIGraphicsImageRenderer(size: symbol.size).image { context in
                context.cgContext.translateBy(x: symbol.size.width, y: symbol.size.height)
                context.cgContext.rotate(by: .pi)
                symbol.draw(at: .zero)
            }
            return Image(uiImage: image.withRenderingMode(.alwaysTemplate))
        }
    }

    enum Profile {
        static let pin = Image("ProfilePin")
        static let route = Image("ProfileRoute")
        static let settings = Image("ProfileSettings")
        static let about = Image("ProfileAbout")
    }

    // MARK: - Branding

    enum Brand {
        static let wordmark = Image("BrandWordmark")
        static let motiYarn = Image("MotiYarn")
        static let motiWinkingFace = Image("MotiWinkingFace")
        static let motiSmilingFace = Image("MotiSmilingFace")
        static let motiSadFace = Image("MotiSadFace")
    }

    // MARK: - Product

    enum Product {
        static let storeAvatar = Image("HomeStoreAvatar")
        static let storeIcon = Image("HomeStoreIcon")
    }

    enum Route {
        static let legStops = Image("ShoppingLegStops")
    }
    
    // MARK: - Placeholder Images
    
    enum Demo {
        static let main = Image("DemoMain")
    }
}

// Core Animation uses the same asset catalog as SwiftUI images.
extension UIImage {
    enum System {
        static var startPin: UIImage? {
            UIImage(systemName: "mappin")
        }
        static var roundTripPin: UIImage? {
            UIImage(systemName: "mappin.and.ellipse")
        }
    }
    enum Brand {
        static let motiYarn = UIImage(named: "MotiYarn")
    }
}
