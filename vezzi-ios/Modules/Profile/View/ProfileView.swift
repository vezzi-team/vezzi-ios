import SwiftUI

struct ProfileView: View {
    @ObservedObject var session: AuthenticationSession
    @ObservedObject var list: ShoppingListRepository
    @EnvironmentObject private var router: AppRouter
    @Environment(\.preferredShoppingMode) private var mode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(spacing: ProfileLayout.cardSpacing) {
                accountCard
                preferenceCards
                settingsCard
                contactCard
                #if DEBUG
                debugSection
                #endif
            }
            .padding(.horizontal, ProfileLayout.inset)
            .padding(.vertical, Const.verticalInset)
            .frame(maxWidth: Const.maxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color.Background.iOSPrimary)
        .foregroundStyle(Color.Label.primary)
        .accessibilityIdentifier(AccessibilityID.Profile.screen)
    }

    private var accountCard: some View {
        NavigationLink(value: AppRouter.Route.profileData) {
            ProfileCard(minHeight: Const.accountHeight, showsShadow: true) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Const.accountSpacing) {
                        HStack {
                            avatar
                            Spacer()
                            accountChevron
                        }
                        accountSummary
                    }
                } else {
                    HStack(spacing: Const.accountSpacing) {
                        avatar
                        accountSummary
                        Spacer(minLength: .zero)
                        accountChevron
                    }
                }
            }
        }
        .pressScaleEffect()
        .accessibilityIdentifier(AccessibilityID.Profile.personalDetails)
    }

    private var avatar: some View {
        Text(String((session.user?.email ?? "").prefix(1)).uppercased())
            .font(.title3.weight(.semibold))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .foregroundStyle(Color.Mascot.ink)
            .frame(width: Const.avatarSize, height: Const.avatarSize)
            .background(Color.accentColor, in: Circle())
            .accessibilityHidden(true)
    }

    private var accountSummary: some View {
        VStack(alignment: .leading, spacing: ProfileLayout.labelSpacing) {
            Text(Texts.Profile.Main.user)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(Const.minimumAccountTitleScale)
            if let email = session.user?.email {
                // Prefer breaks after email separators while VoiceOver reads the original address.
                let displayEmail = email.replacingOccurrences(of: "@", with: "@\u{200B}")
                    .replacingOccurrences(of: ".", with: ".\u{200B}")
                Text(verbatim: displayEmail)
                    .font(.footnote)
                    .foregroundStyle(Color.Label.secondary)
                    .accessibilityLabel(Text(verbatim: email))
            }
        }
    }

    private var accountChevron: some View {
        Image.System.chevronRight.font(.footnote.weight(.semibold))
            .foregroundStyle(Color.Label.tertiary).accessibilityHidden(true)
    }

    private var preferenceCards: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: ProfileLayout.cardSpacing)) : AnyLayout(HStackLayout(alignment: .top, spacing: ProfileLayout.cardSpacing))
        return layout {
            preferenceCard(Texts.Profile.Addresses.title, subtitle: list.originAddress?.addressCapitalized ?? Texts.Routes.Settings.mapTitle,
                           image: Image.Profile.pin, sheet: .address)
            preferenceCard(Texts.Profile.Shopping.title, subtitle: mode.profileTitle, image: Image.Profile.route, sheet: .shopping)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func preferenceCard(_ title: String, subtitle: String, image: Image, sheet: ProfileSheet) -> some View {
        Button { router.presentProfile(sheet) } label: {
            ProfileCard(minHeight: Const.tileHeight, verticalInset: Const.tileInset, alignment: .topLeading, showsShadow: true) {
                VStack(alignment: .leading, spacing: ProfileLayout.labelSpacing) {
                    image.resizable().scaledToFit().frame(width: Const.tileIconSize, height: Const.tileIconSize).accessibilityHidden(true)
                    Text(title).font(.headline)
                    Text(subtitle).font(.footnote).foregroundStyle(Color.Label.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .pressScaleEffect()
        .accessibilityIdentifier(AccessibilityID.Profile.destination(sheet.rawValue))
    }

    private var settingsCard: some View {
        ProfileCard(verticalInset: .zero, showsShadow: true) {
            VStack(spacing: .zero) {
                menuRow(.settings, title: Texts.Profile.Main.settings, image: Image.Profile.settings)
                Divider().padding(.leading, Const.separatorInset)
                menuRow(.about, title: Texts.Profile.Main.about, image: Image.Profile.about)
            }
        }
    }

    private func menuRow(_ sheet: ProfileSheet, title: String, image: Image) -> some View {
        Button { router.presentProfile(sheet) } label: {
            ProfileRow(title: title, image: image, minimumHeight: Const.menuRowHeight)
        }
        .pressScaleEffect()
        .accessibilityIdentifier(AccessibilityID.Profile.destination(sheet.rawValue))
    }

    private var contactCard: some View {
        ProfileCard(minHeight: Const.contactHeight, verticalInset: Const.contactInset, showsShadow: true) {
            HStack(spacing: ProfileLayout.cardSpacing) {
                VStack(alignment: .leading, spacing: ProfileLayout.labelSpacing) {
                    Text(Texts.Profile.Support.title).font(.headline)
                    Text(Texts.Profile.Support.subtitle).font(.footnote).foregroundStyle(Color.Label.secondary)
                }
                Spacer(minLength: .zero)
                if !dynamicTypeSize.isAccessibilitySize {
                    StaticMotiArtwork { Image.Brand.motiWinkingFace.resizable().scaledToFit() }
                        .frame(width: Const.mascotWidth)
                }
            }
        }
        .opacity(Const.disabledOpacity)
        .accessibilityElement(children: .combine)
        .disabled(true)
        .accessibilityIdentifier(AccessibilityID.Profile.contact)
    }

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: Const.debugSpacing) {
            Text(Texts.Profile.Main.debug).font(.footnote).foregroundStyle(Color.Label.secondary)
            NavigationLink(value: AppRouter.Route.motiDebug) {
                ProfileCard(verticalInset: ProfileLayout.labelSpacing) { ProfileRow(title: Texts.Debug.Moti.title, image: Image.System.profileDebug) }
            }
            .pressScaleEffect()
            .accessibilityIdentifier(AccessibilityID.Profile.motiDebug)
        }
    }

    private enum Const {
        static let maxWidth: CGFloat = 680
        static let verticalInset: CGFloat = 10
        static let accountSpacing: CGFloat = 14
        static let accountHeight: CGFloat = 92
        static let minimumAccountTitleScale: CGFloat = 0.75
        static let avatarSize: CGFloat = 52
        static let tileHeight: CGFloat = 116
        static let tileInset: CGFloat = 14
        static let tileIconSize: CGFloat = 22
        static let menuRowHeight: CGFloat = 66
        static let separatorInset: CGFloat = 36
        static let contactHeight: CGFloat = 100
        static let contactInset: CGFloat = 9
        static let mascotWidth: CGFloat = 116
        static let debugSpacing: CGFloat = 6
        static let disabledOpacity: Double = 0.2
    }
}

#Preview("Profile") {
    @Previewable @StateObject var session = AuthenticationSession.preview()
    NavigationStack {
        ProfileView(session: session, list: ShoppingListRepository()).environmentObject(AppRouter())
            .navigationTitle(Texts.Profile.Main.title)
    }
    .task { try? await session.signIn(email: "moti@example.com", password: "preview-only", intent: .signIn, requestID: UUID()) }
}
