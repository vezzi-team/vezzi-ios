//
//  VezziApp.swift
//  vezzi-ios
//
//  Created by Roman Tverdohleb on 12.10.2026.
//

import SwiftUI

@main
struct VezziApp: App {
    @StateObject private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            AppRootView(catalog: dependencies.catalog)
                .task { await dependencies.load() }
        }
    }
}
