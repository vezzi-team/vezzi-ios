//
//  ViewExtension.swift
//  vezzi-ios
//
//  Created by Roman Tverdohleb on 01.11.2026.
//

import SwiftUI

extension View {
    
    /// Checks if the device has a notch by evaluating the top safe area inset.
    /// - Returns: A Boolean value indicating whether the device has a notch.
    internal func hasNotch() -> Bool {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let keyWindow = windowScene.windows.first(where: \.isKeyWindow) else {
            return false
        }
        return keyWindow.safeAreaInsets.top > 20
    }
    
    internal func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Crossfades the displayed screen state while updates within that state keep their identity.
    func screenStateFade<State: Hashable>(for state: State) -> some View {
        modifier(ScreenStateFade(state: state))
    }
}

extension Animation {
    static let screenStateFade = Animation.easeInOut(duration: 0.18)
}

private struct ScreenStateFade<State: Hashable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: State

    func body(content: Content) -> some View {
        ZStack(alignment: .topLeading) {
            content
                .id(state)
                .transition(reduceMotion ? .identity : .opacity)
        }
        .animation(reduceMotion ? nil : .screenStateFade, value: state)
    }
}
