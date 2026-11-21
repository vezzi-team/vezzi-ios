import SwiftUI

struct CatalogCategoryFilterBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedFilter: CatalogFilter
    var categories: [ProductCategory] = ProductCategory.allCases

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                filters(scrollProxy: proxy)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .accessibilityIdentifier(AccessibilityID.Catalog.Filters.bar)
            .onChange(of: selectedFilter, initial: true) { _, filter in
                center(filter, using: proxy)
            }
        }
    }

    // MARK: - Filters

    private func filters(scrollProxy: ScrollViewProxy) -> some View {
        GlassEffectContainer(spacing: Const.spacing) {
            HStack(spacing: Const.spacing) {
                filterButton(for: .all, scrollProxy: scrollProxy)
                ForEach(categories) { category in
                    filterButton(for: .category(category), scrollProxy: scrollProxy)
                }
            }
            .padding(.horizontal, Const.horizontalInset)
        }
        .animation(selectionAnimation, value: selectedFilter)
    }

    private func filterButton(for filter: CatalogFilter, scrollProxy: ScrollViewProxy) -> some View {
        let isSelected = selectedFilter == filter
        return Button {
            if isSelected {
                center(filter, using: scrollProxy)
            } else {
                selectedFilter = filter
            }
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

    private func filterLabel(for filter: CatalogFilter, isSelected: Bool) -> some View {
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
        .glassEffect(isSelected ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
    }

    // MARK: - Presentation

    private func center(_ filter: CatalogFilter, using proxy: ScrollViewProxy) {
        withAnimation(selectionAnimation) {
            proxy.scrollTo(filter, anchor: .center)
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

#Preview("Filters — light") {
    @Previewable @State var selectedFilter: CatalogFilter = .all
    CatalogCategoryFilterBar(selectedFilter: $selectedFilter)
        .padding(.vertical)
        .background(Color.Background.primary)
        .preferredColorScheme(.light)
}

#Preview("Filters — dark, large text") {
    @Previewable @State var selectedFilter: CatalogFilter = .category(.produce)
    CatalogCategoryFilterBar(selectedFilter: $selectedFilter)
        .padding(.vertical)
        .background(Color.Background.primary)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
