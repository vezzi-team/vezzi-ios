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
        static let chevronDown = Image(systemName: "chevron.down")
        static let xmark = Image(systemName: "xmark")
        static let arrowRight = Image(systemName: "arrow.right")
        static let checkmark = Image(systemName: "checkmark")
        static let checkmarkCircle = Image(systemName: "checkmark.circle.fill")
        static let plus = Image(systemName: "plus")
        static let minus = Image(systemName: "minus")
        static let house = Image(systemName: "house")
        static let checklist = Image(systemName: "checklist")
        static let storefront = Image(systemName: "storefront")
        static let magnifyingGlass = Image(systemName: "magnifyingglass")
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
