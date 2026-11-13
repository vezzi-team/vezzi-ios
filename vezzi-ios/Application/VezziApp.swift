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
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppLaunchView(catalog: dependencies.catalog, authentication: dependencies.authentication, shoppingList: dependencies.shoppingList)
                .task { await dependencies.load() }
                .onChange(of: dependencies.authentication.user?.id) { _, _ in
                    Task { await dependencies.accountChanged() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await dependencies.becameActive() }
                    }
                }
        }
    }
}
