import SwiftUI

struct CatalogView<Header: View>: View {
    @ObservedObject var viewModel: StorefrontViewModel
    let viewportHeight: CGFloat
    let transition: Namespace.ID
    let openCategory: (ProductCategory) -> Void
    @ViewBuilder let header: Header

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleCategory: ProductCategory?
    @State private var requestedCategory: ProductCategory?
    @State private var filterBarHeight: CGFloat = 0
    @State private var visibleEdge: VerticalEdge? = .top
    @State private var lastShelfIsTall = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Overlap the transparent padding so each lazy scroll target begins one pinned strip above its heading.
                LazyVStack(alignment: .leading, spacing: -filterBarHeight, pinnedViews: [.sectionHeaders]) {
                    VStack(spacing: 0) { header }
                        .padding(.bottom, filterBarHeight)
                    Section {
                        ForEach(viewModel.catalogSections) { section in
                            scrollTarget(for: section, using: proxy)
                                .id(Anchor.category(section.id))
                        }
                    } header: {
                        filterBar(using: proxy)
                    }
                }
                .frame(maxWidth: StorefrontScreen.maximumContentWidth)
                .frame(maxWidth: .infinity)
            }
            .coordinateSpace(name: Space.viewport)
            .onScrollGeometryChange(for: VerticalEdge?.self) { geometry in
                if geometry.contentOffset.y + geometry.contentInsets.top <= 1 { return .top }
                if geometry.visibleRect.maxY - geometry.contentInsets.bottom >= geometry.contentSize.height - 1 { return .bottom }
                return nil
            } action: { _, edge in visibleEdge = edge }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting || (phase == .idle && visibleEdge != .bottom) { requestedCategory = nil }
            }
            .pauseShimmerWhileScrolling()
        }
    }

    private func filterBar(using proxy: ScrollViewProxy) -> some View {
        let categories = viewModel.catalogSections.map(\.id)
        let visible = switch visibleEdge {
        case .top: categories.first
        case .bottom: categories.last
        case nil: visibleCategory
        }
        let current = requestedCategory ?? visible
        return CatalogCategoryFilterBar(categories: categories,
                                        selected: current.flatMap { categories.contains($0) ? $0 : nil } ?? categories.first,
                                        isFollowingFeed: requestedCategory == nil) { category in
            requestedCategory = category
            scroll(to: category, using: proxy)
        }
        .padding(.bottom, 12)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { filterBarHeight = $0 }
    }

    private func scroll(to category: ProductCategory, using proxy: ScrollViewProxy) {
        let fitsAtEnd = category == viewModel.catalogSections.last?.id && !lastShelfIsTall
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            proxy.scrollTo(Anchor.category(category), anchor: fitsAtEnd ? nil : .top)
        }
    }

    @ViewBuilder private func scrollTarget(for section: CatalogSection, using proxy: ScrollViewProxy) -> some View {
        let shelf = categorySection(section).padding(.top, filterBarHeight)
        if section.id == viewModel.catalogSections.last?.id {
            shelf.onGeometryChange(for: Bool.self) { $0.size.height > viewportHeight } action: { isTall in
                guard lastShelfIsTall != isTall else { return }
                lastShelfIsTall = isTall
                // A distant last shelf can be measured for the first time during the jump.
                if requestedCategory == section.id { scroll(to: section.id, using: proxy) }
            }
        } else {
            shelf
        }
    }

    private func categorySection(_ section: CatalogSection) -> some View {
        CatalogShelf(section: section, viewModel: viewModel, transition: transition, openCategory: openCategory)
            .onGeometryChange(for: Bool.self) { geometry in
                let frame = geometry.frame(in: .named(Space.viewport))
                let readingLine = filterBarHeight + 1
                return frame.minY <= readingLine && frame.maxY > readingLine
            } action: { isCurrent in
                if isCurrent { visibleCategory = section.id }
            }
    }

    private enum Anchor: Hashable {
        case category(ProductCategory)
    }

    private nonisolated enum Space: Hashable { case viewport }
}

private struct CatalogShelf: View {
    let section: CatalogSection
    let viewModel: StorefrontViewModel
    let transition: Namespace.ID
    let openCategory: (ProductCategory) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.id.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.Label.primary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(AccessibilityID.Catalog.heading(section.id))
                .padding(.horizontal, ProductGridLayout.contentInset)
            ProductCarousel(products: section.preview, selection: viewModel.selection) {
                viewModel.showProduct($0)
            }
            .pauseShimmerWhileScrolling()
            if section.hasMoreProducts {
                ProductSectionButton(title: Texts.Common.showMore) {
                    openCategory(section.id)
                }
                .accessibilityLabel(Texts.Catalog.showAll(in: section.id.title))
                .accessibilityIdentifier(AccessibilityID.Catalog.showMore(section.id))
                .matchedTransitionSource(id: StorefrontCollection.category(section.id), in: transition)
                .padding(.horizontal, ProductGridLayout.contentInset)
            }
        }
        .padding(.bottom, 24)
    }
}
