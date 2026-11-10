//
//  ImageExtension.swift
//  vezzi-ios
//
//  Created by Roman Tverdohleb on 01.11.2026.
//

import SwiftUI
import UIKit

extension Image {
    // MARK: - SF Symbols

    enum System {
        static let person = Image(systemName: "person.crop.circle")
        static let walk = Image(systemName: "figure.walk")
        static let chevronRight = Image(systemName: "chevron.right")
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
        static let house = Image(systemName: "house")
        static let checklist = Image(systemName: "checklist")
        static let storefront = Image(systemName: "storefront")
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

    // MARK: - Branding

    enum Brand {
        static let wordmark = Image("BrandWordmark")
    }

    // MARK: - Product

    enum Product {
        static let storeAvatar = Image("HomeStoreAvatar")
        static let storeIcon = Image("HomeStoreIcon")
    }
    
    // MARK: - Placeholder Images
    
    enum Demo {
        static let main = Image("DemoMain")
    }
}

// Core Animation uses the same asset catalog as SwiftUI images.
extension UIImage {
    enum Brand {
        static let motiYarn = UIImage(named: "MotiYarn")
    }
}
