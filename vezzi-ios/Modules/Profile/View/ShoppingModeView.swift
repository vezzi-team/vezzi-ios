import SwiftUI

struct ShoppingModeView: View {
    @StateObject private var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss

    init(session: AuthenticationSession) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(session: session))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Const.spacing) {
                ForEach(ProfilePreferences.ShoppingPriority.allCases) { priority in
                    Button { viewModel.priority = priority } label: {
                        ProfileCard {
                            HStack(spacing: Const.spacing) {
                                VStack(alignment: .leading, spacing: Const.textSpacing) {
                                    Text(priority.title).appTextStyle(.appText)
                                    Text(subtitle(for: priority)).appTextStyle(.caption)
                                        .foregroundStyle(Color.Label.secondary)
                                }
                                Spacer(minLength: .zero)
                                if viewModel.priority == priority {
                                    Image.System.checkmark.foregroundStyle(Color.accentColor)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: Const.radius)
                                .stroke(viewModel.priority == priority ? Color.accentColor : Color.clear,
                                        lineWidth: Const.borderWidth)
                        }
                    }
                    .pressScaleEffect()
                    .accessibilityAddTraits(viewModel.priority == priority ? [.isSelected] : [])
                    .accessibilityIdentifier(AccessibilityID.Profile.priority(priority.rawValue))
                }
                Text(Texts.Profile.Controls.temporary)
                    .appTextStyle(.caption).foregroundStyle(Color.Label.secondary)
            }
            .padding(Const.inset)
        }
        .foregroundStyle(Color.Label.primary)
        .background(Color.Background.primary)
        .navigationTitle(Texts.Profile.Shopping.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ProfileSheetToolbar(onClose: { dismiss() }, onSave: {
                if viewModel.savePriority() { dismiss() }
            })
        }
    }

    private func subtitle(for priority: ProfilePreferences.ShoppingPriority) -> String {
        switch priority {
        case .balanced: return Texts.Profile.Shopping.balancedDescription
        case .price: return Texts.Profile.Shopping.priceDescription
        case .time: return Texts.Profile.Shopping.timeDescription
        }
    }

    private enum Const {
        static let spacing: CGFloat = 12
        static let textSpacing: CGFloat = 4
        static let radius: CGFloat = 20
        static let borderWidth: CGFloat = 1
        static let inset: CGFloat = 16
    }
}

#Preview("Shopping preference") {
    NavigationStack { ShoppingModeView(session: .preview()) }
}
