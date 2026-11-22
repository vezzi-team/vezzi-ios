import SwiftUI

/// Only the middle of the sheet resizes. The action keeps its position during a drag.
struct ShoppingRoutePanel<Header: View, Details: View, Footer: View>: View {
    let isCollapsed: Bool
    @Binding var headerHeight: CGFloat
    @Binding var footerHeight: CGFloat
    @ViewBuilder var header: Header
    @ViewBuilder var details: Details
    @ViewBuilder var footer: Footer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { headerHeight = $0 }
            if isCollapsed {
                Spacer(minLength: 0)
            } else {
                ScrollView { details }
                    .scrollIndicators(.hidden)
                    .transition(.opacity)
            }
            footer
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { height in
                    // Keep the last measurement while recalculation temporarily removes the action.
                    if height > 0 { footerHeight = height }
                }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: isCollapsed)
    }
}

struct ShoppingRouteButton<Label: View>: View {
    enum Placement { case footer, bottomBar }

    let placement: Placement
    let action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        let button = Button(action: action) { label.frame(maxWidth: .infinity) }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        switch placement {
        case .footer:
            button
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .frame(maxWidth: 600)
        case .bottomBar:
            button
                .font(.headline)
                .tabBarActionWidth()
                .padding(.vertical, 8)
        }
    }
}
