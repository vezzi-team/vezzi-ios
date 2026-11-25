import SwiftUI

struct ProfileSettingsView: View {
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.catalogImageCache) private var imageCache
    @State private var confirmsLanguageChange = false
    @State private var confirmsCacheClear = false
    @State private var cacheState = CacheState.idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ProfileLayout.sectionSpacing) {
                languageRow
                themeSection
                imageCacheRow
            }
            .buttonStyle(.plain)
            .padding(ProfileLayout.inset)
        }
        .background(Color.Background.iOSPrimary)
        .navigationTitle(Texts.Profile.Main.settings)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ProfileSheetToolbar(onClose: { dismiss() }) }
        .alert(Texts.Profile.Settings.language, isPresented: $confirmsLanguageChange) {
            Button(Texts.Authentication.cancel, role: .cancel) {}
            Button(Texts.Profile.Settings.openSettings) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        } message: { Text(Texts.Profile.Settings.languagePrompt) }
    }

    private var languageRow: some View {
        ProfileCard(verticalInset: ProfileLayout.labelSpacing) {
            Button { confirmsLanguageChange = true } label: {
                languageLabel
                    .frame(maxWidth: .infinity, minHeight: Const.rowHeight, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier(AccessibilityID.Profile.language)
        }
    }

    private var languageLabel: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ProfileLayout.labelSpacing))
            : AnyLayout(HStackLayout())
        return layout {
            Text(Texts.Profile.Settings.language)
            HStack {
                if !stacked { Spacer() }
                Text(languageName).foregroundStyle(Color.Label.secondary)
                if stacked { Spacer() }
                Image.System.chevronRight.font(.footnote).accessibilityHidden(true)
            }
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: Const.headingGap) {
            Text(Texts.Profile.Settings.appearance).font(.headline).accessibilityAddTraits(.isHeader)
            ProfileCard(verticalInset: ProfileLayout.labelSpacing) {
                VStack(spacing: .zero) {
                    ForEach(AppAppearance.allCases, id: \.self) { option in
                        if option != .system { Divider() }
                        themeButton(option)
                    }
                }
            }
        }
    }

    private var imageCacheRow: some View {
        ProfileCard(verticalInset: ProfileLayout.labelSpacing) {
            VStack(alignment: .leading, spacing: ProfileLayout.labelSpacing) {
                Button { confirmsCacheClear = true } label: {
                    HStack {
                        Text(Texts.Profile.Settings.clearImageCache)
                        Spacer()
                        switch cacheState {
                        case .idle, .failed: EmptyView()
                        case .clearing: ProgressView().controlSize(.small)
                        case .cleared: Image.System.checkmark.foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(minHeight: Const.rowHeight)
                    .contentShape(Rectangle())
                }
                .disabled(cacheState == .clearing)
                .accessibilityLabel(Texts.Profile.Settings.clearImageCache)
                .accessibilityValue(cacheState == .cleared ? Texts.Profile.Settings.cacheCleared : "")
                .accessibilityIdentifier(AccessibilityID.Profile.clearImageCache)
                if cacheState == .failed {
                    Text(Texts.Profile.Settings.cacheClearFailed)
                        .font(.footnote)
                        .foregroundStyle(Color.Label.secondary)
                }
            }
        }
        .alert(Texts.Profile.Settings.clearImageCacheQuestion, isPresented: $confirmsCacheClear) {
            Button(Texts.Authentication.cancel, role: .cancel) {}
            Button(Texts.Profile.Settings.clearCacheAction, role: .destructive, action: clearImageCache)
        }
    }

    private func clearImageCache() {
        guard cacheState != .clearing else { return }
        cacheState = .clearing
        Task {
            do {
                try await CatalogImageCache.clear(imageCache)
                cacheState = .cleared
            } catch {
                cacheState = .failed
            }
        }
    }

    private enum CacheState { case idle, clearing, cleared, failed }

    private var languageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? locale.identifier
        return (locale.localizedString(forIdentifier: code) ?? code).capitalized(with: locale)
    }

    private func themeButton(_ option: AppAppearance) -> some View {
        Button { appearance = option } label: {
            HStack {
                Text(option.title)
                Spacer()
                if appearance == option {
                    Image.System.checkmark.font(.body.weight(.semibold)).foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: Const.rowHeight)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(appearance == option ? .isSelected : [])
        .accessibilityIdentifier(AccessibilityID.Profile.theme(option.rawValue))
    }

    private enum Const {
        static let rowHeight: CGFloat = 52
        static let headingGap: CGFloat = 8
    }
}

private extension AppAppearance {
    var title: String {
        switch self {
        case .system: Texts.Profile.Settings.system
        case .light: Texts.Profile.Settings.light
        case .dark: Texts.Profile.Settings.dark
        }
    }
}

#Preview {
    NavigationStack { ProfileSettingsView() }
}
