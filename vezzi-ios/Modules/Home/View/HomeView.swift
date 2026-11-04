import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var selectedProduct: HomeProduct?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView { content }
        .safeAreaBar(edge: .top, spacing: .zero) {
            if !dynamicTypeSize.isAccessibilitySize { header }
        }
        .background(Color.Background.primary.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedProduct) { product in
            HomeProductDetailView(product: product, quantity: quantityBinding(for: product.id))
        }
        .sensoryFeedback(.selection, trigger: viewModel.quantities)
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: .zero) {
            // Let a large accessibility header scroll so the catalog remains reachable.
            if dynamicTypeSize.isAccessibilitySize { header }
            recommendations
                .padding(.horizontal, Const.contentInset)
                .padding(.bottom, Const.contentInset)
                .frame(maxWidth: Const.maximumWidth)
                .frame(maxWidth: .infinity)
        }
        .environment(\.isShimmerEnabled, selectedProduct == nil)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Const.headerSpacing) {
            addressPicker
            dinnerCard
        }
        .padding(.horizontal, Const.contentInset)
        .padding(.top, Const.headerTopInset)
        .padding(.bottom, Const.sectionSpacing)
        .frame(maxWidth: Const.maximumWidth)
        .frame(maxWidth: .infinity)
    }

    private var recommendations: some View {
        VStack(alignment: .leading, spacing: Const.gridHeaderSpacing) {
            categoryLabel
            productGrid
        }
    }

    private var categoryLabel: some View {
        Text(Texts.Home.Main.forYou)
            .onestTextStyle(size: Const.chipFontSize, lineHeight: Const.chipLineHeight,
                           weight: .semibold, relativeTo: .caption)
            .foregroundStyle(Color.Label.white)
            .padding(.horizontal, Const.chipHorizontalInset)
            .padding(.vertical, Const.chipVerticalInset)
            .background(Color.accentColor, in: .capsule)
            .accessibilityAddTraits(.isHeader)
    }

    private var productGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Const.gridSpacing) {
            ForEach(viewModel.products) { product in
                HomeProductCard(product: product, quantity: quantityBinding(for: product.id)) {
                    selectedProduct = product
                }
            }
        }
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: Const.minimumCardWidth), spacing: Const.gridSpacing, alignment: .top)]
    }

    // MARK: - Header

    private var addressPicker: some View {
        Menu {
            Picker(Texts.Home.Main.address, selection: $viewModel.selectedAddress) {
                ForEach(HomeAddress.allCases) { address in
                    Text(address.title).tag(address)
                }
            }
        } label: {
            addressLabel
        }
        .foregroundStyle(Color.Label.primary)
        .accessibilityIdentifier(AccessibilityID.Home.address)
    }

    private var addressLabel: some View {
        VStack(alignment: .leading, spacing: .zero) {
            HStack(alignment: .firstTextBaseline, spacing: Const.chevronSpacing) {
                Text(viewModel.selectedAddress.title)
                    .onestTextStyle(size: Const.headingFontSize, lineHeight: Const.headingLineHeight,
                                   weight: .semibold, relativeTo: .headline)
                Image.System.chevronDown
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.Label.tertiary)
            }
            Text(Texts.Home.Main.nearbyStores)
                .onestTextStyle(size: Const.captionFontSize, lineHeight: Const.captionLineHeight, relativeTo: .footnote)
                .foregroundStyle(Color.Label.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .contentShape(.rect)
    }

    private var dinnerCard: some View {
        Button(action: viewModel.addDinnerProducts) {
            dinnerContent
                .padding(.horizontal, Const.dinnerHorizontalInset)
                .padding(.vertical, Const.dinnerVerticalInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.Background.elevated, in: .rect(cornerRadius: Const.dinnerCornerRadius))
                .overlay(RoundedRectangle(cornerRadius: Const.dinnerCornerRadius)
                    .strokeBorder(Color.Border.primary, lineWidth: Const.borderWidth))
                .shadow(color: Color.Shadow.primary.opacity(Const.shadowOpacity), radius: Const.shadowRadius, y: Const.shadowOffset)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.hasDinnerProducts)
        .accessibilityIdentifier(AccessibilityID.Home.addDinner)
    }

    private var dinnerContent: some View {
        VStack(alignment: .leading, spacing: Const.dinnerSpacing) {
            Text(Texts.Home.Main.dinnerTitle)
                .onestTextStyle(size: Const.headingFontSize, lineHeight: Const.headingLineHeight,
                               weight: .semibold, relativeTo: .headline)
                .foregroundStyle(Color.Label.primary)
            Text(Texts.Home.Main.dinnerSubtitle)
                .onestTextStyle(size: Const.captionFontSize, lineHeight: Const.captionLineHeight, relativeTo: .footnote)
                .foregroundStyle(Color.Label.secondary)
            dinnerActionLabel
        }
        .multilineTextAlignment(.leading)
    }

    private var dinnerActionLabel: some View {
        HStack(spacing: Const.actionSpacing) {
            Text(viewModel.hasDinnerProducts ? Texts.Home.Main.dinnerAdded : Texts.Home.Main.collectProducts)
            viewModel.hasDinnerProducts ? Image.System.checkmark : Image.System.arrowRight
        }
        .onestTextStyle(size: Const.captionFontSize, lineHeight: Const.captionLineHeight,
                       weight: .semibold, relativeTo: .footnote)
        .foregroundStyle(Color.accentColor)
    }

    // MARK: - Bindings

    private func quantityBinding(for productID: String) -> Binding<Int> {
        Binding(
            get: { viewModel.quantity(for: productID) },
            set: { viewModel.setQuantity($0, for: productID) }
        )
    }

    private enum Const {
        static let contentInset: CGFloat = 16
        static let maximumWidth: CGFloat = 760
        static let sectionSpacing: CGFloat = 11
        static let headerSpacing: CGFloat = 3
        static let headerTopInset: CGFloat = 8
        static let gridHeaderSpacing: CGFloat = 12
        static let gridSpacing: CGFloat = 16
        static let minimumCardWidth: CGFloat = 150
        static let chevronSpacing: CGFloat = 14
        static let headingFontSize: CGFloat = 17
        static let headingLineHeight: CGFloat = 22
        static let captionFontSize: CGFloat = 13
        static let captionLineHeight: CGFloat = 18
        static let chipFontSize: CGFloat = 12
        static let chipLineHeight: CGFloat = 16
        static let chipHorizontalInset: CGFloat = 7
        static let chipVerticalInset: CGFloat = 5
        static let dinnerSpacing: CGFloat = 4
        static let dinnerHorizontalInset: CGFloat = 16
        static let dinnerVerticalInset: CGFloat = 16
        static let dinnerCornerRadius: CGFloat = 16
        static let actionSpacing: CGFloat = 8
        static let borderWidth: CGFloat = 1
        static let shadowOpacity: Double = 0.05
        static let shadowRadius: CGFloat = 6
        static let shadowOffset: CGFloat = 4
    }
}

#Preview("Home — light") {
    NavigationStack { HomeView() }
        .preferredColorScheme(.light)
}

#Preview("Home — dark, large text") {
    NavigationStack { HomeView() }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
