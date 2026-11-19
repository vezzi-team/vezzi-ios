import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: Const.spacing) {
                MotiMascotView(state: .idle, isMotionEnabled: false)
                    .frame(height: Const.mascotHeight)
                Text(Texts.AppInfo.title).appTextStyle(.subtitle, weight: .bold)
                Text(Texts.Profile.About.tagline).appTextStyle(.appText, weight: .semibold)
                Text(Texts.Profile.About.description).appTextStyle(.appText)
                    .foregroundStyle(Color.Label.secondary)
                Text(Texts.Profile.About.version(version)).appTextStyle(.caption)
                    .foregroundStyle(Color.Label.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(Const.inset)
            .padding(.top, Const.topInset)
            .frame(maxWidth: Const.maximumWidth)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Color.Label.primary)
        .background(Color.Background.primary)
        .navigationTitle(Texts.Profile.Main.about)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ProfileSheetToolbar(onClose: { dismiss() }) }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private enum Const {
        static let spacing: CGFloat = 20
        static let inset: CGFloat = 24
        static let topInset: CGFloat = 64
        static let mascotHeight: CGFloat = 160
        static let maximumWidth: CGFloat = 560
    }
}

#Preview("About — light") { NavigationStack { AboutView() }.preferredColorScheme(.light) }
#Preview("About — dark") { NavigationStack { AboutView() }.preferredColorScheme(.dark) }
