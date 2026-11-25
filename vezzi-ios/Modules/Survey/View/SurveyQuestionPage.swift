import SwiftUI

struct SurveyQuestionPage: View {
    let question: SurveyQuestion
    let selected: SurveyAnswer?
    let select: (SurveyAnswer, SurveyQuestion) -> Void
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var titleFocused: Bool

    private var usesTiles: Bool {
        !textSize.isAccessibilitySize && [.priority, .basket, .household].contains(question)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: question == .routine ? Const.compactGap : Const.questionGap) {
                header
                if usesTiles {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Const.columnSpacing), GridItem(.flexible())], spacing: Const.tileSpacing) {
                        ForEach(question.answers, id: \.self) { option($0) }
                    }
                } else {
                    VStack(spacing: question == .routine ? Const.compactSpacing : Const.rowSpacing) {
                        ForEach(question.answers, id: \.self) { option($0) }
                    }
                }
            }
            .padding(.horizontal, Const.inset)
            .padding(.top, Const.tileSpacing).padding(.bottom, Const.contentGap)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { titleFocused = true }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Const.contentGap) {
            VStack(alignment: .leading, spacing: Const.titleSpacing) {
                if question.isOptional {
                    Text(Texts.Survey.optional).font(.footnote.weight(.medium))
                        .foregroundStyle(Color.Label.secondary)
                }
                Text(Texts.Survey.title(for: question))
                    .appTextStyle(size: question == .routine ? Const.compactTitleSize : Const.titleSize, lineHeight: question == .routine ? Const.compactTitleLine : Const.titleLine,
                                  weight: .bold, relativeTo: .largeTitle)
                    .tracking(Const.titleTracking)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($titleFocused)
            if !textSize.isAccessibilitySize {
                Image.Survey.illustration(for: question).resizable().scaledToFit()
                    .frame(width: question == .routine ? Const.compactArtWidth : Const.artWidth)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Const.smallInset)
    }

    private func option(_ answer: SurveyAnswer) -> some View {
        let isSelected = selected == answer
        let shape = RoundedRectangle(cornerRadius: usesTiles ? Const.tileRadius : Const.rowRadius)
        return Button { select(answer, question) } label: {
            Group {
                if usesTiles {
                    VStack(alignment: .leading, spacing: Const.tileSpacing) {
                        HStack {
                            Image.Survey.icon(for: answer, in: question)
                            Spacer()
                            indicator(isSelected)
                        }
                        Text(Texts.Survey.title(for: answer))
                            .padding(.horizontal, Const.titleSpacing)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, Const.tileTop).padding(.leading, Const.titleSpacing).padding(.trailing, Const.tileSpacing).padding(.bottom, Const.contentGap)
                    .frame(maxWidth: .infinity, minHeight: Const.tileHeight, alignment: .topLeading)
                } else {
                    HStack(spacing: Const.contentGap) {
                        Text(Texts.Survey.title(for: answer)).frame(maxWidth: .infinity, alignment: .leading)
                        indicator(isSelected)
                    }
                    .padding(.vertical, Const.compactSpacing).padding(.leading, Const.rowLeading).padding(.trailing, Const.tileSpacing)
                    .frame(minHeight: question == .routine ? Const.compactRowHeight : Const.rowHeight)
                }
            }
            .appTextStyle(size: Const.answerFont, lineHeight: usesTiles ? Const.tileLine : Const.rowLine, weight: .medium, relativeTo: .body)
            .multilineTextAlignment(.leading)
            .foregroundStyle(isSelected ? Color.Label.white : Color.Label.primary)
            .contentShape(shape)
            .glassEffect(.regular.tint(isSelected ? .accentColor : nil), in: shape)
            .overlay { shape.strokeBorder(Color.Border.primary, lineWidth: isSelected ? 0 : Const.borderWidth) }
            .animation(reduceMotion ? nil : .easeOut(duration: Const.selectionDuration), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Texts.Survey.title(for: answer))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(AccessibilityID.Survey.answer(answer))
    }

    private func indicator(_ isSelected: Bool) -> some View {
        Circle()
            .strokeBorder(isSelected ? Color.Label.white : Color.Label.tertiary, lineWidth: isSelected ? Const.selectedStroke : Const.stroke)
            .frame(width: Const.ringSize, height: Const.ringSize)
            .accessibilityHidden(true)
    }
    private enum Const {
        static let selectionDuration: TimeInterval = 0.1
        static let borderWidth: CGFloat = 0.75
        static let compactGap: CGFloat = 26
        static let questionGap: CGFloat = 38
        static let columnSpacing: CGFloat = 18
        static let tileSpacing: CGFloat = 12
        static let compactSpacing: CGFloat = 6
        static let rowSpacing: CGFloat = 8
        static let inset: CGFloat = 16
        static let smallInset: CGFloat = 4
        static let titleSpacing: CGFloat = 5
        static let contentGap: CGFloat = 10
        static let titleSize: CGFloat = 34
        static let compactTitleSize: CGFloat = 30
        static let titleLine: CGFloat = 36
        static let compactTitleLine: CGFloat = 33
        static let titleTracking: CGFloat = -1.2
        static let artWidth: CGFloat = 100
        static let compactArtWidth: CGFloat = 82
        static let tileRadius: CGFloat = 20
        static let rowRadius: CGFloat = 16
        static let tileTop: CGFloat = 9
        static let tileHeight: CGFloat = 130
        static let rowHeight: CGFloat = 55
        static let compactRowHeight: CGFloat = 48
        static let rowLeading: CGFloat = 14
        static let answerFont: CGFloat = 17
        static let tileLine: CGFloat = 18
        static let rowLine: CGFloat = 21
        static let ringSize: CGFloat = 21
        static let selectedStroke: CGFloat = 5
        static let stroke: CGFloat = 1.5
    }
}

#Preview("Optional question — large text") {
    SurveyQuestionPage(question: .household, selected: .family) { _, _ in }
        .dynamicTypeSize(.accessibility2)
        .background(Color.Background.iOSPrimary)
}
