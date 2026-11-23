import SwiftUI

struct OnboardingView: View {
    @ObservedObject var authentication: AuthenticationSession
    let finish: () -> Void

    @State private var page = Page.catalog
    @State private var showsLogin = false
    @State private var nextButtonFeedback = false
    @AccessibilityFocusState private var focusedTitle: Page?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isFinalPage: Bool { page == Page.allCases.last }
    private var offersSignIn: Bool { isFinalPage && authentication.user == nil }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if textSize.isAccessibilitySize || geometry.size.height < Const.compactHeight {
                    scrollableLayout
                } else {
                    tour(size: geometry.size)
                }
            }
            .padding(.bottom)
            .background(Color.Background.defaultColor.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { navigationControls }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: nextButtonFeedback)
        .onChange(of: page) { focusedTitle = page }
        .sheet(isPresented: $showsLogin, onDismiss: {
            if authentication.user != nil { finish() }
        }) {
            LoginView(session: authentication)
        }
    }

    private func tour(size: CGSize) -> some View {
        let width = horizontalSizeClass == .regular
            ? size.width * (size.height > size.width ? Const.portraitControlsWidth : Const.landscapeControlsWidth)
            : nil
        return ZStack(alignment: .bottom) {
            phone
                .compositingGroup()
                .scaleEffect(page.zoom, anchor: page.anchor)
                .padding(.top, Const.phoneTop)
                .padding(.horizontal, Const.phoneSides)
                .padding(.bottom, Const.phoneBottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(pageSwipe)
                .accessibilityHidden(true)

            VStack(spacing: Const.spacing) {
                pagedCaption
                progress
                actions
            }
            .frame(maxWidth: width)
            .frame(maxWidth: .infinity)
            .padding(.top, Const.footerTop)
            .padding(.horizontal, Const.footerSides)
            .background { glassBackdrop }
        }
    }

    private var scrollableLayout: some View {
        ScrollView {
            VStack(spacing: Const.spacing) {
                phone
                    .padding(Const.footerTop)
                    .frame(height: Const.compactArtworkHeight)
                    .contentShape(.rect)
                    .simultaneousGesture(pageSwipe)
                    .accessibilityHidden(true)
                caption(for: page)
                progress
                actions
            }
            .padding(.horizontal, Const.footerSides)
            .padding(.bottom)
        }
    }

    private var phone: some View {
        GeometryReader { geometry in
            let height = min(geometry.size.height, geometry.size.width / Const.captureAspect)
            let width = height * Const.captureAspect
            let shape = ConcentricRectangle(corners: .concentric, isUniform: true)
            ZStack {
                page.screenshot.resizable()
                    .id(page)
                    .transition(.opacity)
            }
            .frame(width: width, height: height)
            .overlay(alignment: .top) {
                Capsule().fill(Color.Onboarding.bezel)
                    .frame(width: width * Const.islandWidth, height: height * Const.islandHeight)
                    .padding(.top, height * Const.islandTop)
            }
            .clipShape(shape)
            .overlay {
                ZStack {
                    shape.stroke(Color.Label.white, lineWidth: Const.outerStroke)
                    shape.stroke(Color.Onboarding.bezel, lineWidth: Const.rimStroke)
                    shape.stroke(Color.Onboarding.bezel, lineWidth: Const.outerStroke)
                        .padding(Const.rimStroke)
                }
                .padding(-Const.outerStroke)
            }
            .containerShape(.rect(cornerRadius: height * Const.cornerFraction))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var glassBackdrop: some View {
        Rectangle()
            .fill(Color.Background.defaultColor.opacity(Const.backdropOpacity))
            .glassEffect(.clear, in: .rect)
            .blur(radius: Const.blur)
            .padding([.horizontal, .bottom], -Const.blur * 2)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    @ToolbarContentBuilder private var navigationControls: some ToolbarContent {
        if page != .catalog {
            ToolbarItem(placement: .cancellationAction) {
                Button { move(by: -1) } label: {
                    Label { Text(Texts.Routes.back) } icon: { Image.System.chevronLeft }
                }
                .tint(Color.Label.primary)
                .accessibilityIdentifier(AccessibilityID.Onboarding.back)
            }
        }
        if let lastPage = Page.allCases.last, page != lastPage {
            ToolbarItem(placement: .topBarTrailing) {
                Button(Texts.Onboarding.skip) { move(to: lastPage) }
                    .tint(Color.Label.primary)
                    .accessibilityIdentifier(AccessibilityID.Onboarding.skip)
            }
        }
    }

    private var pagedCaption: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Page.allCases, id: \.self) { item in
                    caption(for: item)
                        .containerRelativeFrame(.horizontal)
                        .compositingGroup()
                        .blur(radius: item == page || reduceMotion ? 0 : Const.captionBlur)
                        .opacity(item == page ? 1 : 0)
                        .accessibilityHidden(item != page)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(true)
        .scrollClipDisabled()
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: Binding(get: { page }, set: { _ in }))
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: Const.minimumCaptionHeight, alignment: .top)
    }

    private func caption(for item: Page) -> some View {
        VStack(spacing: Const.copySpacing) {
            Text(item.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.Label.primary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusedTitle, equals: item)
                .accessibilityIdentifier(AccessibilityID.Onboarding.title)
            Text(item.detail)
                .font(.callout)
                .foregroundStyle(Color.Label.primary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.center)
    }

    private var progress: some View {
        HStack(spacing: Const.copySpacing) {
            ForEach(Page.allCases, id: \.self) { item in
                let diameter = item == page ? Const.activeDot : Const.dot
                Circle()
                    .fill(Color.Label.primary.opacity(item == page ? 1 : Const.inactiveOpacity))
                    .frame(width: diameter, height: diameter)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Texts.Onboarding.progress(page.rawValue + 1, Page.allCases.count))
    }

    @ViewBuilder private var actions: some View {
        if offersSignIn {
            Button(action: finish) {
                Text(Texts.Onboarding.guest)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.Label.primary)
                    .padding(.vertical, Const.actionPadding)
            }
            .buttonStyle(.glass)
            .buttonSizing(.flexible)
            .padding(.horizontal)
            .accessibilityIdentifier(AccessibilityID.Onboarding.finish)

            primaryAction({ showsLogin = true }) {
                Text(Texts.Authentication.signIn)
            }
            .padding(.top, Const.copySpacing)
            .disabled(authentication.isRestoring || authentication.isSigningOut)
            .accessibilityIdentifier(AccessibilityID.Onboarding.signIn)
        } else {
            primaryAction({
                if isFinalPage {
                    finish()
                } else {
                    nextButtonFeedback.toggle()
                    move(by: 1)
                }
            }) {
                Text(isFinalPage ? Texts.Onboarding.start : Texts.Onboarding.next)
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }
            .accessibilityIdentifier(isFinalPage ? AccessibilityID.Onboarding.finish : AccessibilityID.Onboarding.next)
        }
    }

    private func primaryAction<Title: View>(_ action: @escaping () -> Void, @ViewBuilder label: () -> Title) -> some View {
        Button(action: action) {
            label()
                .fontWeight(.medium)
                .foregroundStyle(Color.Label.white)
                .padding(.vertical, Const.actionPadding)
        }
        .tint(.accentColor)
        .buttonStyle(.glassProminent)
        .buttonSizing(.flexible)
        .padding(.horizontal)
    }

    private var pageSwipe: some Gesture {
        DragGesture(minimumDistance: Const.swipeDistance).onEnded { value in
            let delta = value.translation
            guard abs(delta.width) > abs(delta.height), abs(delta.width) >= Const.swipeDistance else { return }
            move(by: delta.width < 0 ? 1 : -1)
        }
    }

    private func move(by offset: Int) {
        guard let destination = Page(rawValue: page.rawValue + offset) else { return }
        move(to: destination)
    }

    private func move(to destination: Page) {
        withAnimation(reduceMotion ? nil : .interpolatingSpring(duration: Const.duration, bounce: 0)) {
            page = destination
        }
    }

    private enum Page: Int, CaseIterable {
        case catalog, comparison, routes, shopping

        var screenshot: Image {
            switch self {
            case .catalog: Image.Onboarding.catalog
            case .comparison: Image.Onboarding.comparison
            case .shopping: Image.Onboarding.shopping
            case .routes: Image.Onboarding.routes
            }
        }

        var zoom: CGFloat {
            switch self {
            case .catalog: 2
            case .comparison, .shopping: 1.3
            case .routes: 1.1
            }
        }

        var anchor: UnitPoint {
            switch self {
            case .catalog: UnitPoint(x: 0, y: -0.2)
            case .comparison: UnitPoint(x: 0.5, y: -0.5)
            case .routes, .shopping: .top
            }
        }

        var title: String {
            switch self {
            case .catalog: Texts.Onboarding.catalogTitle
            case .comparison: Texts.Onboarding.comparisonTitle
            case .shopping: Texts.Onboarding.shoppingTitle
            case .routes: Texts.Onboarding.routesTitle
            }
        }

        var detail: String {
            switch self {
            case .catalog: Texts.Onboarding.catalogDescription
            case .comparison: Texts.Onboarding.comparisonDescription
            case .shopping: Texts.Onboarding.shoppingDescription
            case .routes: Texts.Onboarding.routesDescription
            }
        }
    }

    private enum Const {
        static let spacing: CGFloat = 10
        static let copySpacing: CGFloat = 6
        static let phoneTop: CGFloat = 35
        static let phoneSides: CGFloat = 30
        static let phoneBottom: CGFloat = 220
        static let minimumCaptionHeight: CGFloat = 108
        static let footerTop: CGFloat = 20
        static let footerSides: CGFloat = 15
        static let actionPadding: CGFloat = 8
        static let dot: CGFloat = 8
        static let activeDot: CGFloat = 12
        static let inactiveOpacity = 0.4
        static let blur: CGFloat = 15
        static let captionBlur: CGFloat = 30
        static let backdropOpacity = 0.75
        static let captureAspect: CGFloat = 1206.0 / 2622
        static let cornerFraction: CGFloat = 190.0 / 2556
        static let outerStroke: CGFloat = 6
        static let rimStroke: CGFloat = 4
        static let islandWidth: CGFloat = 0.32
        static let islandHeight: CGFloat = 0.044
        static let islandTop: CGFloat = 0.013
        static let portraitControlsWidth: CGFloat = 0.7
        static let landscapeControlsWidth: CGFloat = 0.5
        static let compactHeight: CGFloat = 530
        static let compactArtworkHeight: CGFloat = 210
        static let swipeDistance: CGFloat = 30
        static let duration: TimeInterval = 0.4
    }
}

#Preview {
    OnboardingView(authentication: .preview(), finish: {})
}
