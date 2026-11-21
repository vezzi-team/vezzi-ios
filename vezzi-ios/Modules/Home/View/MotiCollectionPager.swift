import SwiftUI

struct MotiCollectionPager: View {
    let transition: Namespace.ID
    let open: (MotiCollection) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragFeedback = false
    @State private var selection = Const.initialPage
    @State private var progress = CGFloat(Const.initialPage)
    @State private var scrollPosition = ScrollPosition(idType: Int.self)

    private static let collections = MotiCollection.allCases
    // One extra scroll target at either end connects the last and first cards.
    private static let pages = -1...collections.count

    var body: some View {
        VStack(spacing: Const.indicatorInset) {
            pager
            indicators
        }
        .frame(maxWidth: Const.width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Texts.Home.Discovery.moti)
        .accessibilityValue(Self.collections[selection].title)
        .accessibilityIdentifier(AccessibilityID.Home.motiCollections)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            open(Self.collections[selection])
        }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(selection + 1)
            case .decrement: select(selection - 1)
            @unknown default: break
            }
        }
        .sensoryFeedback(.selection, trigger: dragFeedback)
        .frame(maxWidth: .infinity)
    }

    // Native paging handles gesture arbitration with Home's vertical scroll view.
    // One stationary deck draws the artwork for all pages, including the exposed edges.
    private var pager: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Self.pages, id: \.self) { page in
                        Color.clear
                            .frame(width: width, height: geometry.size.height)
                            .contentShape(.rect)
                            .onTapGesture { point in handleTap(at: point.x, width: width, page: page) }
                            .id(page)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .defaultScrollAnchor(.center, for: .initialOffset)
            .scrollPosition($scrollPosition, anchor: .center)
            .onScrollGeometryChange(for: CGFloat.self, of: pageProgress) { _, newValue in
                progress = newValue
            }
            .onScrollPhaseChange { _, phase, context in
                if phase == .interacting {
                    dragFeedback.toggle()
                } else if phase == .idle {
                    settle(at: Int(pageProgress(context.geometry).rounded()))
                }
            }
            .overlay {
                ZStack {
                    ForEach(Self.collections.indices, id: \.self) { index in card(index, width: width) }
                }
                .allowsHitTesting(false)
            }
        }
        .aspectRatio(Const.width / Const.height, contentMode: .fit)
    }

    private var visualPage: CGFloat { reduceMotion ? CGFloat(selection) : progress }

    private func card(_ index: Int, width: CGFloat) -> some View {
        let angle = (CGFloat(index) - visualPage) * (2 * .pi / CGFloat(Self.collections.count))
        let depth = cos(angle)
        let side = sin(angle) / sin(2 * .pi / CGFloat(Self.collections.count))
        // Separate the passing edges at mid-swipe, before the two cards exchange depth.
        let turn = pow(sin(.pi * visualPage), 2)
        let size = width / Const.width
        return RoundedRectangle(cornerRadius: Const.cornerRadius)
            .fill(Color.Background.placeholder)
            .shimmer()
            .overlay(RoundedRectangle(cornerRadius: Const.cornerRadius).strokeBorder(Color.Border.primary))
            .shadow(color: Color.Shadow.primary.opacity(Const.shadowOpacity), radius: Const.shadowRadius, y: Const.shadowOffset)
            .frame(width: Const.cardWidth * size, height: Const.cardHeight * size)
            .matchedTransitionSource(id: StorefrontCollection.moti(Self.collections[index]), in: transition) { source in
                source.clipShape(.rect(cornerRadius: Const.cornerRadius))
            }
            .scaleEffect(1 - Const.depthScale * (1 - depth))
            .rotationEffect(.degrees(Const.fanAngle * side))
            .rotation3DEffect(.degrees(-Const.turnAngle * side * turn), axis: (x: 0, y: 1, z: 0), perspective: 0)
            .offset(x: size * side * (Const.peekOffset + Const.passingOffset * turn))
            .zIndex(depth)
    }

    private var indicators: some View {
        HStack(spacing: Const.dotSize) {
            ForEach(Self.collections.indices, id: \.self) { index in
                let distance = abs(CGFloat(index) - visualPage)
                let emphasis = max(0, 1 - min(distance, CGFloat(Self.collections.count) - distance))
                Capsule()
                    .fill(Color.Label.tertiary)
                    .overlay { Capsule().fill(Color.Label.secondary).opacity(emphasis) }
                    .frame(width: Const.dotSize + Const.dotExtension * emphasis, height: Const.dotSize)
            }
        }
    }

    private func pageProgress(_ geometry: ScrollGeometry) -> CGFloat {
        guard geometry.containerSize.width > 0 else { return CGFloat(selection) }
        let first = CGFloat(Self.pages.lowerBound)
        let page = first + (geometry.contentOffset.x + geometry.contentInsets.leading) / geometry.containerSize.width
        return min(max(first, page), CGFloat(Self.pages.upperBound))
    }

    private func handleTap(at x: CGFloat, width: CGFloat, page: Int) {
        let margin = width * (1 - Const.cardWidth / Const.width) / 2
        let index = collectionIndex(for: page)
        if x < margin {
            select(index - 1)
        } else if x > width - margin {
            select(index + 1)
        } else if index == selection {
            open(Self.collections[index])
        }
    }

    private func select(_ page: Int) {
        if reduceMotion {
            let index = collectionIndex(for: page)
            scrollPosition.scrollTo(id: index, anchor: .center)
            selection = index
        } else {
            withAnimation(.easeInOut(duration: Const.selectionDuration)) {
                scrollPosition.scrollTo(id: page, anchor: .center)
            }
        }
    }

    private func settle(at page: Int) {
        let index = collectionIndex(for: page)
        selection = index
        guard page != index else { return }
        // The two targets have identical artwork and indicators, so recenter in place.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { scrollPosition.scrollTo(id: index, anchor: .center) }
    }

    private func collectionIndex(for page: Int) -> Int {
        (page + Self.collections.count) % Self.collections.count
    }

    private enum Const {
        static let initialPage = 1
        static let width: CGFloat = 322
        static let height: CGFloat = 178
        static let cardWidth: CGFloat = 250
        static let cardHeight: CGFloat = 170
        static let peekOffset: CGFloat = 45
        static let passingOffset: CGFloat = 71
        static let depthScale: CGFloat = 0.08
        static let fanAngle = 5.0
        static let turnAngle = 25.0
        static let selectionDuration = 0.32
        static let cornerRadius: CGFloat = 14
        static let shadowOpacity = 0.08
        static let shadowRadius: CGFloat = 3
        static let shadowOffset: CGFloat = 2
        static let indicatorInset: CGFloat = 6
        static let dotSize: CGFloat = 4
        static let dotExtension: CGFloat = 10
    }
}
