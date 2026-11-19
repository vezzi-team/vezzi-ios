import SwiftUI

/// Shared content surfaces. Native toolbar buttons provide their own Liquid Glass.
struct ProfileCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Const.inset)
            .background(Color.Background.secondary, in: RoundedRectangle(cornerRadius: Const.radius))
    }

    private enum Const {
        static var inset: CGFloat { 16 }
        static var radius: CGFloat { 20 }
    }
}

struct ProfileRow: View {
    let title: String
    let image: Image
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: Const.spacing) {
            image.font(.title3).frame(width: Const.iconWidth).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Const.textSpacing) {
                Text(title).appTextStyle(.appText)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).appTextStyle(.caption).foregroundStyle(Color.Label.secondary)
                }
            }
            Spacer(minLength: Const.spacing)
            Image.System.chevronRight.font(.caption).foregroundStyle(Color.Label.tertiary)
                .accessibilityHidden(true)
        }
        .foregroundStyle(Color.Label.primary)
        .padding(.vertical, Const.verticalInset)
        .frame(minHeight: Const.minimumHeight)
        .contentShape(Rectangle())
    }

    private enum Const {
        static let spacing: CGFloat = 12
        static let textSpacing: CGFloat = 4
        static let iconWidth: CGFloat = 24
        static let verticalInset: CGFloat = 8
        static let minimumHeight: CGFloat = 44
    }
}

struct ProfileSheetToolbar: ToolbarContent {
    let onClose: () -> Void
    var onSave: (() -> Void)? = nil

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: onClose) {
                Label { Text(Texts.Profile.Controls.close) } icon: { Image.System.xmark }
            }
            .accessibilityIdentifier(AccessibilityID.Profile.close)
        }
        if let onSave {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: onSave) {
                    Label { Text(Texts.Profile.Controls.save) } icon: { Image.System.checkmark }
                }
                .tint(Color.Profile.confirmation)
                .accessibilityIdentifier(AccessibilityID.Profile.save)
            }
        }
    }
}

struct ProfileInformationView: View {
    let text: String
    var body: some View {
        ScrollView {
            ProfileCard { Text(text).appTextStyle(.appText) }
                .padding(Const.inset)
        }
        .foregroundStyle(Color.Label.primary)
        .background(Color.Background.primary)
    }
    private enum Const { static let inset: CGFloat = 16 }
}

#Preview("Profile card — dark") {
    ProfileCard {
        ProfileRow(title: Texts.Profile.Main.notifications, image: Image.System.profileSettings)
    }
    .padding()
    .preferredColorScheme(.dark)
}
