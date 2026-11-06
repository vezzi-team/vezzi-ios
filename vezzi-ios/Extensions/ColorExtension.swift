//
//  ColorExtension.swift
//  vezzi-ios
//
//  Created by Roman Tverdohleb on 01.11.2026.
//

import SwiftUI

extension Color {
    
    enum Mascot {
        static let ink = Color("MotiInk")
        static let cheek = Color("MotiCheek")
        static let highlight = Color("MotiHighlight")
    }

    // MARK: - Back Colors
    
    enum Background {
        static let elevated = Color("BackgroundElevated")
        static let iOSPrimary = Color("BackgroundiOSPrimary")
        static let primary = Color("BackgroundPrimary")
        static let secondary = Color("BackgroundSecondary")
        static let defaultColor = Color("BackgroundDefault")
        static let sheet = Color("BackgroundSheet")
        static let placeholder = Color("BackgroundPlaceholder")
        static let placeholderLighter = Color("BackgroundPlaceholderLighter")
    }
    
    // MARK: - Label Colors
    
    enum Label {
        static let error = Color("LabelError")
        static let disable = Color("LabelDisable")
        static let details = Color("LabelDetails")
        static let primary = Color("LabelPrimary")
        static let secondary = Color("LabelSecondary")
        static let tertiary = Color("LabelTertiary")
        static let black = Color("LabelBlack")
        static let white = Color("LabelWhite")
        static let greyLight = Color("LabelGreyLight")
        static let greyDark = Color("LabelGreyDark")
        static let placeholder = Color("LabelPlaceholder")
    }

    // MARK: - Border Colors

    enum Border {
        static let primary = Color("BorderPrimary")
    }

    // MARK: - Shadow Colors

    enum Shadow {
        static let primary = Color("ShadowPrimary")
    }
}
