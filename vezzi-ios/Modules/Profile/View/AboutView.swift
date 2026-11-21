import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: ProfileLayout.inset) {
                StaticMotiArtwork { Image.Brand.motiSmilingFace.resizable().scaledToFit() }
                    .frame(maxWidth: Const.mascotWidth)
                Text(Texts.AppInfo.title).font(.title.bold())
                Text(Texts.Profile.About.tagline).font(.headline)
                Text(Texts.Profile.About.description).font(.body).foregroundStyle(Color.Label.secondary)
                if let version {
                    Text(Texts.Profile.About.version(version)).font(.footnote).foregroundStyle(Color.Label.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: Const.textWidth)
            .padding(.horizontal, ProfileLayout.sectionSpacing)
            .padding(.top, Const.illustrationTopInset)
            .padding(.bottom, ProfileLayout.sectionSpacing)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Color.Label.primary)
        .background(Color.Background.secondary)
        .navigationTitle(Texts.Profile.Main.about)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ProfileSheetToolbar(onClose: { dismiss() }) }
    }

    private var version: String? {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else { return nil }
        return "\(version) (\(build))"
    }

    private enum Const {
        static let mascotWidth: CGFloat = 278
        static let textWidth: CGFloat = 354
        static let illustrationTopInset: CGFloat = 100
    }
}

#Preview("About") { NavigationStack { AboutView() } }
