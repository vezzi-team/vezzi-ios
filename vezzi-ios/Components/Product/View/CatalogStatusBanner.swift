import SwiftUI

/// The same catalog state and retry action on Home and Search.
struct CatalogStatusBanner: View {
    let status: CatalogStatus
    var isCacheUnavailable = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Const.spacing) {
                Text(title)
                    .appTextStyle(size: Const.titleSize, lineHeight: Const.titleLineHeight,
                                  weight: .semibold, relativeTo: .headline)
                    .foregroundStyle(Color.Label.primary)
                Text(message)
                    .appTextStyle(size: Const.textSize, lineHeight: Const.textLineHeight, relativeTo: .footnote)
                    .foregroundStyle(Color.Label.secondary)
                if status.isSynthetic && title != Texts.Catalog.syntheticTitle {
                    Text(Texts.Catalog.syntheticMessage)
                        .font(.caption).foregroundStyle(Color.Label.secondary)
                }
                HStack(spacing: Const.actionSpacing) {
                    if status.isRefreshing { ProgressView().controlSize(.small) }
                    Text(status.isRefreshing ? Texts.Catalog.updating : actionTitle)
                    if !status.isRefreshing { Image.System.arrowRight }
                }
                .appTextStyle(size: Const.textSize, lineHeight: Const.textLineHeight, weight: .semibold, relativeTo: .footnote)
                .foregroundStyle(Color.accentColor)
            }
            .multilineTextAlignment(.leading)
            .padding(Const.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.Background.elevated, in: .rect(cornerRadius: Const.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Const.cornerRadius).strokeBorder(Color.Border.primary, lineWidth: Const.borderWidth))
        }
        .pressScaleEffect()
        .disabled(status.isRefreshing)
        .accessibilityIdentifier(AccessibilityID.Catalog.banner)
    }

    private var needsLogin: Bool { status.failure == .authenticationRequired && !status.isOffline }
    private var actionTitle: String { needsLogin ? Texts.Catalog.signIn : Texts.Catalog.refresh }

    private var title: String {
        if status.isOffline || status.failure == .offline { return Texts.Catalog.offlineTitle }
        if needsLogin { return Texts.Catalog.signInTitle }
        if status.failure != nil { return Texts.Catalog.failedTitle }
        if isCacheUnavailable { return Texts.Catalog.cacheTitle }
        return status.isSynthetic ? Texts.Catalog.syntheticTitle : Texts.Catalog.title
    }

    private var message: String {
        if status.isOffline || status.failure == .offline || status.failure == .unavailable {
            return status.hasSnapshot ? Texts.Catalog.staleMessage : Texts.Catalog.noCacheMessage
        }
        if needsLogin { return Texts.Catalog.signInMessage }
        if isCacheUnavailable { return Texts.Storage.cacheUnavailable }
        return status.isSynthetic ? Texts.Catalog.syntheticMessage : Texts.Catalog.refreshMessage
    }

    private enum Const {
        static let spacing: CGFloat = 4
        static let actionSpacing: CGFloat = 8
        static let inset: CGFloat = 16
        static let cornerRadius: CGFloat = 16
        static let borderWidth: CGFloat = 1
        static let titleSize: CGFloat = 17
        static let titleLineHeight: CGFloat = 22
        static let textSize: CGFloat = 13
        static let textLineHeight: CGFloat = 18
    }
}

#Preview("Offline catalog") {
    CatalogStatusBanner(status: CatalogStatus(hasSnapshot: true, isOffline: true), action: {})
        .padding().background(Color.Background.primary)
}
