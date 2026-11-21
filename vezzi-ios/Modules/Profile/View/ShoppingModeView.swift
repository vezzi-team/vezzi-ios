import SwiftUI

extension ShoppingMode {
    var profileTitle: String {
        self == .cheaper ? Texts.Profile.Shopping.economical : Texts.Search.faster
    }
}

struct ShoppingModeView: View {
    let preferences: ShoppingPreferences
    @State private var draft: Draft
    @Environment(\.dismiss) private var dismiss

    private struct Draft {
        let accountID: UUID?
        var mode: ShoppingMode
    }

    init(preferences: ShoppingPreferences) {
        self.preferences = preferences
        _draft = State(initialValue: Draft(accountID: preferences.accountID, mode: preferences.mode))
    }

    var body: some View {
        ProfileCompactSheetContent {
            VStack(spacing: ProfileLayout.cardSpacing) {
                ForEach(ShoppingMode.allCases) { mode in option(mode) }
            }
            .padding(ProfileLayout.inset)
        }
        .navigationTitle(Texts.Profile.Shopping.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ProfileSheetToolbar(onClose: { dismiss() }, onSave: {
                preferences.save(draft.mode, for: draft.accountID)
                dismiss()
            })
        }
    }

    private func option(_ mode: ShoppingMode) -> some View {
        Button { draft.mode = mode } label: {
            ProfileCard(minHeight: Const.optionHeight) {
                VStack(alignment: .leading, spacing: ProfileLayout.labelSpacing) {
                    Text(mode.profileTitle).font(.body)
                    Text(mode == .cheaper ? Texts.Profile.Shopping.priceDescription : Texts.Profile.Shopping.timeDescription)
                        .font(.footnote).foregroundStyle(Color.Label.secondary)
                }
            }
            .overlay {
                if draft.mode == mode {
                    RoundedRectangle(cornerRadius: ProfileLayout.cornerRadius).strokeBorder(Color.accentColor, lineWidth: Const.selectionWidth)
                }
            }
        }
        .pressScaleEffect()
        .accessibilityAddTraits(draft.mode == mode ? .isSelected : [])
        .accessibilityIdentifier(AccessibilityID.Profile.priority(mode.rawValue))
    }

    private enum Const {
        static let optionHeight: CGFloat = 84
        static let selectionWidth: CGFloat = 1.5
    }
}

#Preview {
    NavigationStack { ShoppingModeView(preferences: ShoppingPreferences(authentication: .preview())) }
}
