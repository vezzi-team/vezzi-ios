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
    
    // MARK: - Tab Bar

    enum Tabbar {
        static let home = NSLocalizedString("TabHome", comment: "Home")
        static let shoppingList = NSLocalizedString("TabShoppingList", comment: "List")
        static let stores = NSLocalizedString("TabStores", comment: "Stores")
        static let search = NSLocalizedString("TabSearch", comment: "Search")
    }

    // MARK: - Demo Module
    
    enum Demo {
        static let title = NSLocalizedString("DemoTitle", comment: "Welcome")
        static let subtitle = NSLocalizedString("DemoSubtitle", comment: "This is demo subtitle")
        static let showSubtitle = NSLocalizedString("DemoShowSubtitle", comment: "Show subtitle")
    }
}
