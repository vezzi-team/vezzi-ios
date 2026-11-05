import SwiftUI

struct HomeCategoryFilterBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedCategory: HomeProductCategory?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                filters(scrollProxy: proxy)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .accessibilityIdentifier(AccessibilityID.Home.Filters.bar)
            .onChange(of: selectedCategory, initial: true) { _, category in
                center(category, using: proxy)
            }
        }
    }

    // MARK: - Filters

    private func filters(scrollProxy: ScrollViewProxy) -> some View {
        GlassEffectContainer(spacing: Const.spacing) {
            HStack(spacing: Const.spacing) {
                filterButton(for: nil, scrollProxy: scrollProxy)
                ForEach(HomeProductCategory.allCases) { category in
                    filterButton(for: category, scrollProxy: scrollProxy)
                }
            }
            .padding(.horizontal, Const.horizontalInset)
        }
        .animation(selectionAnimation, value: selectedCategory)
    }

    private func filterButton(for category: HomeProductCategory?, scrollProxy: ScrollViewProxy) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            if isSelected {
                center(category, using: scrollProxy)
            } else {
                selectedCategory = category
            }
        } label: {
            filterLabel(for: category, isSelected: isSelected)
                .frame(minHeight: Const.minimumHitHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title(for: category))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(AccessibilityID.Home.Filters.category(filterID(category)))
        .id(filterID(category))
    }

    private func filterLabel(for category: HomeProductCategory?, isSelected: Bool) -> some View {
        ZStack {
            Text(title(for: category))
                .onestTextStyle(size: Const.fontSize, lineHeight: Const.lineHeight,
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

    private func center(_ category: HomeProductCategory?, using proxy: ScrollViewProxy) {
        withAnimation(selectionAnimation) {
            proxy.scrollTo(filterID(category), anchor: .center)
        }
    }

    private func title(for category: HomeProductCategory?) -> String {
        switch category {
        case nil: Texts.Home.Main.forYou
        case .dairy: Texts.Home.Filters.dairy
        case .produce: Texts.Home.Filters.produce
        case .bakery: Texts.Home.Filters.bakery
        case .pantry: Texts.Home.Filters.pantry
        case .eggs: Texts.Home.Filters.eggs
        }
    }

    private func filterID(_ category: HomeProductCategory?) -> String {
        category?.rawValue ?? Const.allID
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
        static let allID = "for-you"
    }
}

#Preview("Filters — light") {
    @Previewable @State var selectedCategory: HomeProductCategory?
    HomeCategoryFilterBar(selectedCategory: $selectedCategory)
        .padding(.vertical)
        .background(Color.Background.primary)
        .preferredColorScheme(.light)
}

#Preview("Filters — dark, large text") {
    @Previewable @State var selectedCategory: HomeProductCategory? = .produce
    HomeCategoryFilterBar(selectedCategory: $selectedCategory)
        .padding(.vertical)
        .background(Color.Background.primary)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
