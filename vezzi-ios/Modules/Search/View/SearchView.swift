import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(repository: any CatalogRepository) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(repository: repository))
    }

    var body: some View {
        Group {
            if viewModel.canRefresh {
                results.refreshable { await viewModel.refresh() }
            } else {
                results
            }
        }
        .searchable(text: $viewModel.query, prompt: Texts.Search.prompt)
        .background(Color.Background.primary)
        .safeAreaInset(edge: .bottom) {
            if !dynamicTypeSize.isAccessibilitySize, let message = statusMessage {
                statusView(message)
            }
        }
    }

    private var results: some View {
        List {
            if dynamicTypeSize.isAccessibilitySize, let message = statusMessage {
                statusView(message)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.Background.secondary)
            }
            ForEach(viewModel.items) { item in
                DisclosureGroup {
                    if item.offers.isEmpty {
                        Text(Texts.Search.noOffers)
                            .foregroundStyle(Color.Label.secondary)
                    }
                    ForEach(item.offers) { cached in
                        VStack(alignment: .leading, spacing: Const.rowSpacing) {
                            Text(cached.store.name)
                            Text(cached.offer.price, format: .currency(code: cached.offer.currency))
                                .font(.headline)
                            if let available = cached.offer.inStock {
                                Text(available ? Texts.Search.inStock : Texts.Search.outOfStock)
                                    .foregroundStyle(Color.Label.secondary)
                            }
                            if let date = cached.offer.sourceUpdatedAt {
                                Text(date, format: .dateTime.day().month().year().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(Color.Label.secondary)
                            } else {
                                Text(Texts.Search.unknownPriceDate)
                                    .font(.caption)
                                    .foregroundStyle(Color.Label.secondary)
                            }
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: Const.rowSpacing) {
                        Text(item.product.name)
                            .font(.headline)
                        if let brand = item.product.brand {
                            Text(brand)
                                .foregroundStyle(Color.Label.secondary)
                        }
                        if let quantity = item.product.packageQuantity, let unit = item.product.packageUnit {
                            Text(quantity.formatted() + " " + unit)
                                .foregroundStyle(Color.Label.secondary)
                        }
                    }
                }
            }
            if viewModel.isResultLimitReached {
                Text(Texts.Search.resultLimit)
                    .font(.footnote)
                    .foregroundStyle(Color.Label.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if viewModel.items.isEmpty && viewModel.refreshErrorMessage == nil
                && !(dynamicTypeSize.isAccessibilitySize && statusMessage != nil) {
                ContentUnavailableView(
                    viewModel.query.isEmpty ? Texts.Search.emptyTitle : Texts.Search.noResultsTitle,
                    systemImage: "magnifyingglass",
                    description: Text(viewModel.query.isEmpty ? Texts.Search.emptyDescription : Texts.Search.noResultsDescription)
                )
            }
        }
    }

    private var statusMessage: String? {
        viewModel.refreshErrorMessage ?? (viewModel.isCacheUnavailable ? Texts.Storage.cacheUnavailable : nil)
    }

    private func statusView(_ message: String) -> some View {
        VStack(spacing: Const.messageSpacing) {
            Text(message)
            Button(Texts.Storage.retry) {
                Task { await viewModel.retry() }
            }
        }
        .font(.callout)
        .multilineTextAlignment(.center)
        .padding(Const.messagePadding)
        .frame(maxWidth: .infinity)
        .background(Color.Background.secondary)
    }

    private enum Const {
        static let rowSpacing: CGFloat = 4
        static let messageSpacing: CGFloat = 8
        static let messagePadding: CGFloat = 16
    }
}

#Preview("Empty") {
    NavigationStack {
        SearchView(repository: PreviewCatalogRepository())
            .navigationTitle(Texts.Tabbar.search)
    }
}

#Preview("Catalog — light") {
    NavigationStack {
        SearchView(repository: PreviewCatalogRepository.sample)
            .navigationTitle(Texts.Tabbar.search)
    }
    .preferredColorScheme(.light)
}

#Preview("Catalog — dark, large text") {
    NavigationStack {
        SearchView(repository: PreviewCatalogRepository.sample)
            .navigationTitle(Texts.Tabbar.search)
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
}
