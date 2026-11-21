import SwiftUI

struct CatalogCategoryFilterBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fullyVisibleCategories: [ProductCategory] = []
    @State private var isAutoScrolling = false
    @State private var needsRecentering = false
    let categories: [ProductCategory]
    let selected: ProductCategory?
    var isFollowingFeed = true
    let select: (ProductCategory) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                filters(using: proxy)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .accessibilityIdentifier(AccessibilityID.Catalog.Filters.bar)
            .onScrollTargetVisibilityChange(idType: ProductCategory.self, threshold: 1) {
                fullyVisibleCategories = $0
            }
            .onScrollPhaseChange { _, phase in
                isAutoScrolling = phase == .animating
                if phase == .idle, needsRecentering {
                    needsRecentering = false
                    if let selected { center(selected, using: proxy) }
                } else if phase == .tracking || phase == .interacting {
                    needsRecentering = false
                }
            }
            .onChange(of: selected) { _, category in
                guard isFollowingFeed, let category else { return }
                center(category, using: proxy, onlyIfNeeded: true)
            }
        }
    }

    // MARK: - Filters

    private func filters(using proxy: ScrollViewProxy) -> some View {
        GlassEffectContainer(spacing: Const.spacing) {
            LazyHStack(spacing: Const.spacing) {
                ForEach(categories) { category in
                    filterButton(for: category, using: proxy)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Const.horizontalInset)
        }
    }

    private func filterButton(for filter: ProductCategory, using proxy: ScrollViewProxy) -> some View {
        let isSelected = selected == filter
        return Button {
            select(filter)
            center(filter, using: proxy)
        } label: {
            filterLabel(for: filter, isSelected: isSelected)
                .frame(minHeight: Const.minimumHitHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(AccessibilityID.Catalog.Filters.button(filter))
        .id(filter)
    }

    private func filterLabel(for filter: ProductCategory, isSelected: Bool) -> some View {
        ZStack {
            Text(filter.title)
                .appTextStyle(size: Const.fontSize, lineHeight: Const.lineHeight,
                               weight: .semibold, relativeTo: .caption)
                .foregroundStyle(isSelected ? Color.Label.white : Color.Label.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .id(isSelected)
                .transition(reduceMotion ? .identity : .opacity)
        }
        .padding(.horizontal, Const.chipHorizontalInset)
        .padding(.vertical, Const.chipVerticalInset)
        .background {
            Capsule().fill(Color.accentColor)
                .opacity(isSelected ? 1 : 0)
        }
        .animation(selectionAnimation, value: isSelected)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    // MARK: - Presentation

    private func center(_ category: ProductCategory, using proxy: ScrollViewProxy, onlyIfNeeded: Bool = false) {
        if isAutoScrolling {
            // An earlier animation can win on iOS 27. Reconcile the final selection when it settles.
            needsRecentering = true
        }
        if !onlyIfNeeded || !fullyVisibleCategories.contains(category) {
            withAnimation(selectionAnimation) { proxy.scrollTo(category, anchor: .center) }
        }
    }

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: Const.animationDuration)
    }

    private enum Const {
        static let fontSize: CGFloat = 12
        static let lineHeight: CGFloat = 16
        static let chipHorizontalInset: CGFloat = 12
        static let chipVerticalInset: CGFloat = 7
        static let minimumHitHeight: CGFloat = 44
        static let horizontalInset: CGFloat = 16
        static let spacing: CGFloat = 8
        static let animationDuration: TimeInterval = 0.3
    }
}

#Preview("Category navigation") {
    @Previewable @State var selected: ProductCategory? = .dairy
    CatalogCategoryFilterBar(categories: ProductCategory.allCases, selected: selected) { selected = $0 }
        .padding(.vertical)
        .background(Color.Background.primary)
}
