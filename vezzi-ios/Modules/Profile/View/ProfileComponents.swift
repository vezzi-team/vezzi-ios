import SwiftUI

enum ProfileLayout {
    static let inset: CGFloat = 16
    static let cornerRadius: CGFloat = 16
    static let cardSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 24
    static let shadowOpacity: Double = 0.08
    static let shadowRadius: CGFloat = 12
    static let shadowOffset: CGFloat = 12
    static let labelSpacing: CGFloat = 4
    static let fieldHeight: CGFloat = 68
}

struct ProfileCard<Content: View>: View {
    var minHeight: CGFloat = .zero
    var verticalInset: CGFloat = ProfileLayout.inset
    var alignment: Alignment = .leading
    var showsShadow = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, ProfileLayout.inset)
            .padding(.vertical, verticalInset)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: alignment)
            .background {
                RoundedRectangle(cornerRadius: ProfileLayout.cornerRadius)
                    .fill(Color.Background.secondary)
                    .shadow(color: showsShadow ? Color.Label.black.opacity(ProfileLayout.shadowOpacity) : .clear,
                            radius: ProfileLayout.shadowRadius, y: ProfileLayout.shadowOffset)
            }
            .contentShape(.rect(cornerRadius: ProfileLayout.cornerRadius))
    }
}

struct ProfileRow: View {
    let title: String
    let image: Image
    var minimumHeight: CGFloat = Const.rowHeight

    var body: some View {
        HStack(alignment: .center, spacing: ProfileLayout.inset) {
            image.resizable().scaledToFit().frame(width: Const.icon, height: Const.icon).accessibilityHidden(true)
            Text(title).font(.body)
            Spacer(minLength: Const.trailingSpacing)
            Image.System.chevronRight.font(.footnote.weight(.semibold))
                .foregroundStyle(Color.Label.tertiary).accessibilityHidden(true)
        }
        .frame(minHeight: minimumHeight, alignment: .center)
        .contentShape(Rectangle())
    }

    private enum Const {
        static let icon: CGFloat = 20
        static let rowHeight: CGFloat = 56
        static let trailingSpacing: CGFloat = 8
    }
}

/// Keeps the sheet fitted to its rows and allows scrolling when large text exceeds the screen.
struct ProfileCompactSheetContent<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var height: CGFloat = .zero

    var body: some View {
        ScrollView { content }
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                ceil(geometry.contentSize.height + geometry.contentInsets.top)
            } action: { _, height in
                self.height = height
            }
            .presentationDetents([height > .zero ? .height(height) : .medium])
    }
}

struct ProfileSheetToolbar: ToolbarContent {
    let onClose: () -> Void
    var onSave: (() -> Void)? = nil

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .close, action: onClose)
                .tint(Color.Label.primary)
                .accessibilityIdentifier(AccessibilityID.Profile.close)
        }
        if let onSave {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: onSave) {
                    Label { Text(Texts.Profile.Controls.save) } icon: { Image.System.checkmark }
                }
                .buttonStyle(.glassProminent)
                .tint(Color.accentColor)
                .accessibilityIdentifier(AccessibilityID.Profile.save)
            }
        }
    }
}
