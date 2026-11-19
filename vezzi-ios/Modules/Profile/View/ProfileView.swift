import SwiftUI

struct ProfileView: View {
    @ObservedObject var session: AuthenticationSession
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(spacing: Const.spacing) {
                accountCard
                preferenceCards
                settingsCard
                contactCard
                debugSection
            }
            .padding(Const.inset)
            .frame(maxWidth: Const.maximumWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color.Background.primary)
        .foregroundStyle(Color.Label.primary)
        .accessibilityIdentifier(AccessibilityID.Profile.screen)
    }

    // MARK: - Account

    private var accountCard: some View {
        Button { router.push(.profileDetails(.personalDetails), in: .home) } label: {
            ProfileCard {
                HStack(spacing: Const.spacing) {
                    Text(initial)
                        .appTextStyle(.body, weight: .semibold)
                        .foregroundStyle(Color.Label.white)
                        .frame(width: Const.avatarSize, height: Const.avatarSize)
                        .background(Color.accentColor, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Const.textSpacing) {
                        Text(Texts.Profile.Main.yourProfile).appTextStyle(.body, weight: .semibold)
                        Text(session.user?.email ?? Texts.Profile.Details.notProvided)
                            .appTextStyle(.caption).foregroundStyle(Color.Label.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Const.textSpacing)
                    Image.System.chevronRight.accessibilityHidden(true)
                }
            }
        }
        .pressScaleEffect()
        .accessibilityIdentifier(AccessibilityID.Profile.personalDetails)
    }

    private var initial: String { String((session.user?.email ?? "").prefix(1)).uppercased() }

    // MARK: - Preferences

    private var preferenceCards: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Const.spacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Const.spacing))
        return layout {
            preferenceCard(title: Texts.Profile.Addresses.title,
                           subtitle: session.preferences.address.isEmpty
                            ? Texts.Profile.Addresses.add : session.preferences.address,
                           image: Image.System.profileLocation, sheet: .addresses)
            preferenceCard(title: Texts.Profile.Shopping.title,
                           subtitle: session.preferences.priority.title,
                           image: Image.System.profileRoute, sheet: .shopping)
        }
    }

    private func preferenceCard(title: String, subtitle: String, image: Image, sheet: ProfileSheet) -> some View {
        Button { router.presentProfile(sheet) } label: {
            ProfileCard {
                VStack(alignment: .leading, spacing: Const.textSpacing) {
                    image.font(.title3).accessibilityHidden(true)
                    Text(title).appTextStyle(.appText, weight: .semibold)
                    Text(subtitle).appTextStyle(.caption).foregroundStyle(Color.Label.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: Const.tileHeight, alignment: .topLeading)
            }
        }
        .pressScaleEffect()
        .accessibilityIdentifier(AccessibilityID.Profile.destination(sheet.rawValue))
    }

    private var settingsCard: some View {
        ProfileCard {
            VStack(spacing: .zero) {
                Button { router.presentProfile(.notifications) } label: {
                    ProfileRow(title: Texts.Profile.Main.notifications, image: Image.System.profileSettings)
                }.pressScaleEffect()
                Divider()
                Button { router.presentProfile(.about) } label: {
                    ProfileRow(title: Texts.Profile.Main.about, image: Image.System.person)
                }.pressScaleEffect()
            }
        }
    }

    private var contactCard: some View {
        Button { router.push(.profileDetails(.help), in: .home) } label: {
            ProfileCard {
                HStack(spacing: Const.spacing) {
                    VStack(alignment: .leading, spacing: Const.textSpacing) {
                        Text(Texts.Profile.Support.title).appTextStyle(.appText, weight: .semibold)
                        Text(Texts.Profile.Support.subtitle).appTextStyle(.caption)
                            .foregroundStyle(Color.Label.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !dynamicTypeSize.isAccessibilitySize {
                        MotiMascotView(state: .idle, isMotionEnabled: false)
                            .frame(width: Const.mascotWidth, height: Const.mascotHeight)
                    }
                }
            }
        }
        .pressScaleEffect()
        .accessibilityIdentifier(AccessibilityID.Profile.contact)
    }

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: Const.textSpacing) {
            Text(Texts.Profile.Main.debug).appTextStyle(.caption).foregroundStyle(Color.Label.secondary)
            Button { router.push(.motiDebug, in: .home) } label: {
                ProfileCard { ProfileRow(title: Texts.Debug.Moti.title, image: Image.System.profileDebug) }
            }
            .pressScaleEffect()
            .accessibilityIdentifier(AccessibilityID.Profile.motiDebug)
        }
    }

    private enum Const {
        static let inset: CGFloat = 16
        static let spacing: CGFloat = 12
        static let textSpacing: CGFloat = 6
        static let avatarSize: CGFloat = 52
        static let tileHeight: CGFloat = 92
        static let mascotWidth: CGFloat = 100
        static let mascotHeight: CGFloat = 76
        static let maximumWidth: CGFloat = 680
    }
}

#Preview("Profile — light") {
    NavigationStack {
        ProfileView(session: .preview()).environmentObject(AppRouter())
            .navigationTitle(Texts.Profile.Main.title)
    }
    .preferredColorScheme(.light)
}

#Preview("Profile — dark, large text") {
    NavigationStack {
        ProfileView(session: .preview()).environmentObject(AppRouter())
            .navigationTitle(Texts.Profile.Main.title)
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
}
