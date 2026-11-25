import SwiftUI

struct ShoppingSurveyView: View {
    @ObservedObject var preferences: ShoppingPreferences
    let accountID: UUID
    @StateObject private var model = ShoppingSurveyViewModel()
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isGoingBack = false
    @State private var selectionFeedback = false

    var body: some View {
        VStack(spacing: 0) {
            if let mode = model.result {
                resultContent(mode)
            } else {
                progress
                ZStack {
                    SurveyQuestionPage(question: model.question, selected: model.answers[model.question]) { answer, question in
                        if model.select(answer, for: question) { selectionFeedback.toggle() }
                    }
                    .id(model.question)
                    .transition(reduceMotion ? .opacity : .push(from: isGoingBack ? .leading : .trailing))
                }
                .clipped()
            }
            footer
        }
        .frame(maxWidth: TabBarActionLayout.maximumWidth)
        .frame(maxWidth: .infinity)
        .background(Color.Background.iOSPrimary.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .tabBar)
        .toolbar(model.result == nil ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: back) { model.index == 0 ? Image.System.chevronDown : Image.System.chevronLeft }
                    .tint(Color.Label.primary)
                    .accessibilityLabel(model.index == 0 ? Texts.Product.close : Texts.Routes.back)
                    .accessibilityIdentifier(AccessibilityID.Survey.back)
            }
        }
        .onChange(of: preferences.accountID, initial: true) {
            if accountID != preferences.accountID { router.presentedCover = nil }
        }
    }

    private var progress: some View {
        HStack(spacing: Const.progressSpacing) {
            HStack(spacing: Const.smallSpacing) {
                ForEach(SurveyQuestion.allCases.indices, id: \.self) { index in
                    Capsule()
                        .fill(Color.Border.primary)
                        .overlay {
                            Capsule().fill(Color.accentColor)
                                .scaleEffect(x: index <= model.index ? 1 : 0, anchor: .leading)
                        }
                        .frame(height: Const.segmentHeight)
                        .animation(reduceMotion ? nil : .easeInOut(duration: Const.slideDuration), value: index <= model.index)
                }
            }
            .accessibilityHidden(true)
            Text(Texts.Survey.progress(model.index + 1, SurveyQuestion.allCases.count))
                .font(.subheadline.weight(.medium)).monospacedDigit()
                .padding(.horizontal, Const.counterInset).padding(.vertical, Const.smallSpacing)
                .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal, Const.progressInset)
        .padding(.top, Const.smallSpacing)
    }

    private var footer: some View {
        VStack(spacing: Const.smallSpacing) {
            primaryAction

            if model.result != nil {
                Button(Texts.Survey.profile, action: router.openProfileFromSurvey)
                .accessibilityIdentifier(AccessibilityID.Survey.profile)
                .frame(minHeight: Const.secondaryButtonHeight)
            } else if model.question.isOptional {
                Button(Texts.Onboarding.skip) { advance(skipping: true) }
                    .accessibilityIdentifier(AccessibilityID.Survey.skip)
                    .frame(minHeight: Const.secondaryButtonHeight)
            }
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(Color.Label.primary)
        .padding(.horizontal, Const.inset)
        .padding(.vertical, Const.footerInset)
    }

    private var primaryAction: some View {
        let isResult = model.result != nil
        let isEnabled = isResult || model.canAdvance
        return Button {
            if isResult { router.returnHomeFromSurvey() }
            else { advance() }
        } label: {
            ActionButtonLabel(title: isResult ? Texts.Survey.home : Texts.Survey.next)
                .padding(.vertical, Const.actionVerticalInset)
                .foregroundStyle(isEnabled ? Color.Label.white : Color.Label.secondary)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .background {
            Capsule().fill(Color.Background.secondary)
                .overlay { Capsule().fill(Color.accentColor).opacity(isEnabled ? 1 : 0) }
                .glassEffect(.clear.interactive(), in: .capsule)
        }
        .animation(.easeInOut(duration: Const.actionFadeDuration), value: isEnabled)
        .accessibilityIdentifier(isResult ? AccessibilityID.Survey.home : AccessibilityID.Survey.next)
    }

    private func resultContent(_ mode: ShoppingMode) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: Const.resultSpacing) {
                    StaticMotiArtwork { Image.Survey.happyFace.resizable().scaledToFit() }
                        .frame(width: Const.artworkWidth)
                    Text(Texts.Survey.ready)
                        .appTextStyle(size: Const.resultTitleSize, lineHeight: Const.resultTitleLineHeight, weight: .bold, relativeTo: .largeTitle)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: Const.receiptSpacing) {
                        Text(Texts.Survey.mainPriority).font(.footnote).foregroundStyle(Color.Label.secondary)
                        Text(mode.profileTitle).font(.headline)
                            .accessibilityIdentifier(AccessibilityID.Survey.result)
                    }
                    .padding(.vertical, Const.inset).padding(.horizontal, Const.receiptHorizontalInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.Background.sheet, in: UnevenRoundedRectangle(topLeadingRadius: Const.receiptRadius, topTrailingRadius: Const.receiptRadius))
                    .overlay(alignment: .bottom) {
                        Image.Survey.receiptEdge.resizable().foregroundStyle(Color.Background.sheet)
                            .frame(height: Const.receiptEdgeHeight).offset(y: Const.receiptEdgeHeight - 1).accessibilityHidden(true)
                    }
                    Text(Texts.Survey.hint).font(.subheadline).foregroundStyle(Color.Label.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(Const.resultInset)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
    }

    private func back() {
        guard model.index > 0 else {
            router.presentedCover = nil
            return
        }
        isGoingBack = true
        withAnimation(pageAnimation) { model.back() }
    }

    private func advance(skipping: Bool = false) {
        isGoingBack = false
        withAnimation(pageAnimation) {
            model.advance(skipping: skipping, preferences: preferences, accountID: accountID)
        }
    }

    private var pageAnimation: Animation { .easeInOut(duration: reduceMotion ? Const.fadeDuration : Const.slideDuration) }
    private enum Const {
        static let inset: CGFloat = 16
        static let progressInset: CGFloat = 20
        static let progressSpacing: CGFloat = 12
        static let smallSpacing: CGFloat = 4
        static let segmentHeight: CGFloat = 5
        static let counterInset: CGFloat = 11
        static let footerInset: CGFloat = 6
        static let actionVerticalInset: CGFloat = 14
        static let actionFadeDuration: TimeInterval = 0.2
        static let secondaryButtonHeight: CGFloat = 44
        static let resultSpacing: CGFloat = 15
        static let artworkWidth: CGFloat = 196
        static let resultTitleSize: CGFloat = 36
        static let resultTitleLineHeight: CGFloat = 40
        static let receiptSpacing: CGFloat = 3
        static let receiptHorizontalInset: CGFloat = 20
        static let receiptRadius: CGFloat = 16
        static let receiptEdgeHeight: CGFloat = 8
        static let resultInset: CGFloat = 24
        static let slideDuration: TimeInterval = 0.28
        static let fadeDuration: TimeInterval = 0.15
    }
}

#Preview("Shopping survey") {
    @Previewable @StateObject var session = AuthenticationSession.preview()
    NavigationStack {
        if let accountID = session.user?.id {
            ShoppingSurveyView(preferences: ShoppingPreferences(authentication: session), accountID: accountID)
                .navigationTitle(Texts.Survey.title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
    .environmentObject(AppRouter())
    .task { try? await session.signIn(email: "moti@example.com", password: "preview-only", intent: .signIn, requestID: UUID()) }
}
