import SwiftUI

enum CatalogBannerContent: Equatable {
    case survey, catalog, offline, signIn, failed, cacheUnavailable

    init(isHome: Bool, status: CatalogStatus, isCacheUnavailable: Bool, requiresAuthentication: Bool) {
        if status.isOffline || status.failure == .offline { self = .offline }
        else if requiresAuthentication { self = .signIn }
        else if status.failure != nil { self = .failed }
        else if isCacheUnavailable { self = .cacheUnavailable }
        else { self = isHome ? .survey : .catalog }
    }

    var offersRefresh: Bool {
        self == .offline || self == .failed || self == .cacheUnavailable
    }

    var title: String {
        switch self {
        case .survey: Texts.Home.Discovery.surveyTitle
        case .catalog: Texts.Catalog.title
        case .offline: Texts.Catalog.offlineTitle
        case .signIn: Texts.Catalog.signInRequired
        case .failed: Texts.Catalog.failedTitle
        case .cacheUnavailable: Texts.Catalog.cacheTitle
        }
    }

    func message(hasSnapshot: Bool) -> String {
        switch self {
        case .survey: Texts.Home.Discovery.surveySubtitle
        case .catalog: Texts.Catalog.description
        case .offline, .failed: hasSnapshot ? Texts.Catalog.staleMessage : Texts.Catalog.noCacheMessage
        case .signIn: Texts.ShoppingList.signInDescription
        case .cacheUnavailable: Texts.Storage.cacheUnavailable
        }
    }
}

struct CatalogStatusBanner: View {
    let content: CatalogBannerContent
    let status: CatalogStatus
    let action: () -> Void

    var body: some View {
        Group {
            switch content {
            case .survey, .catalog:
                card.accessibilityElement(children: .combine)
            case .offline, .failed, .cacheUnavailable, .signIn:
                Button(action: action) { card }
                    .pressScaleEffect()
                    .disabled(isUpdating)
            }
        }
        .accessibilityIdentifier(AccessibilityID.Catalog.banner)
    }

    private var isUpdating: Bool { status.isRefreshing && content.offersRefresh }

    private var card: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.title)
                .appTextStyle(size: 17, lineHeight: 22, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(Color.Label.primary)
            Text(content.message(hasSnapshot: status.hasSnapshot))
                .appTextStyle(size: 13, lineHeight: 18, relativeTo: .footnote)
                .foregroundStyle(Color.Label.secondary)
            if status.isSynthetic && content.offersRefresh {
                Text(Texts.Catalog.syntheticMessage)
                    .font(.caption).foregroundStyle(Color.Label.secondary)
            }
            if let caption {
                HStack(spacing: 8) {
                    if isUpdating { ProgressView().controlSize(.small) }
                    Text(caption)
                    if !isUpdating { Image.System.arrowRight.accessibilityHidden(true) }
                }
                .appTextStyle(size: 13, lineHeight: 18, weight: .semibold, relativeTo: .footnote)
                .foregroundStyle(Color.accentColor)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Background.elevated, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.Border.primary))
    }

    private var caption: String? {
        switch content {
        case .catalog: nil
        case .survey: Texts.Home.Discovery.surveyStart
        case .signIn: Texts.Authentication.signIn
        case .offline, .failed, .cacheUnavailable: isUpdating ? Texts.Catalog.updating : Texts.Catalog.refresh
        }
    }
}

#Preview("Offline catalog") {
    CatalogStatusBanner(content: .offline, status: CatalogStatus(hasSnapshot: true, isOffline: true), action: {})
        .padding().background(Color.Background.primary)
}
