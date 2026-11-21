import SwiftUI

/// Full-width action used for authentication and account settings.
struct PrimaryActionButton: View {
    let title: String
    var tint: Color = .accentColor
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionButtonLabel(title: title, isLoading: isLoading)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(tint)
    }
}

struct ActionButtonLabel: View {
    let title: String
    var isLoading = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Measure the title once so replacing it with the spinner preserves the button's size.
        Text(title)
            .appTextStyle(.appText, weight: .semibold)
            .hidden()
            .frame(maxWidth: .infinity, minHeight: Const.minimumHeight)
            .overlay {
                ZStack {
                    if isLoading {
                        ProgressView().controlSize(.regular).tint(Color.Label.primary)
                            .transition(transition)
                    } else {
                        Text(title).appTextStyle(.appText, weight: .semibold)
                            .transition(transition)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
    }

    private var transition: AnyTransition { reduceMotion ? .identity : AnyTransition(.blurReplace) }

    private enum Const {
        static let minimumHeight: CGFloat = 24
    }
}

/// Align a bottom action with the complete tab bar, including its detached Search button.
enum TabBarActionLayout {
    static let horizontalInset: CGFloat = 20
    static let maximumWidth: CGFloat = 760
}

extension View {
    func tabBarActionWidth() -> some View {
        padding(.horizontal, TabBarActionLayout.horizontalInset)
            .frame(maxWidth: TabBarActionLayout.maximumWidth)
            .frame(maxWidth: .infinity)
    }
}
