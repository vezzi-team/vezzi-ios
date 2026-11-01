//
//  Labels.swift
//  vezzi-ios
//
//  Created by Roman Tverdohleb on 01.11.2026.
//

import Foundation

final class Texts {
    
    // MARK: - App Info
    
    enum AppInfo {
        static let title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Planzo"
    }
    
    // MARK: - Demo Module
    
    enum Demo {
        static let title = NSLocalizedString("DemoTitle", comment: "Welcome")
        static let subtitle = NSLocalizedString("DemoSubtitle", comment: "This is demo subtitle")
        static let showSubtitle = NSLocalizedString("DemoShowSubtitle", comment: "Show subtitle")
    }
}
