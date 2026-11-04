import SwiftUI

struct HomeProductCard: View {
    let product: HomeProduct
    @Binding var quantity: Int
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Const.contentSpacing) {
            productButton
            purchaseControls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.Background.elevated)
        .clipShape(.rect(cornerRadius: Const.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Const.cornerRadius)
            .strokeBorder(Color.Border.primary, lineWidth: Const.borderWidth))
        .shadow(color: Color.Shadow.primary.opacity(Const.shadowOpacity), radius: Const.shadowRadius, y: Const.shadowOffset)
    }

    // MARK: - Product

    private var productButton: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: Const.imageSpacing) {
                artwork
                productInfo
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.Home.product(product.id))
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: Const.artworkCornerRadius)
            .fill(Color.Background.placeholder)
            .aspectRatio(Const.artworkAspectRatio, contentMode: .fit)
            .shimmer()
            .accessibilityHidden(true)
    }

    private var productInfo: some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text(product.name)
                .onestTextStyle(size: Const.nameFontSize, lineHeight: Const.nameLineHeight,
                               weight: .semibold, relativeTo: .headline)
                .foregroundStyle(Color.Label.primary)
            Text(product.package)
                .onestTextStyle(size: Const.packageFontSize, lineHeight: Const.packageLineHeight, relativeTo: .footnote)
                .foregroundStyle(Color.Label.secondary)
        }
        .padding(.horizontal, Const.contentInset)
    }

    // MARK: - Offers

    private var purchaseControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: Const.controlsSpacing) {
                offersSummary.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: .zero)
                quantityControl.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: Const.controlsSpacing) {
                offersSummary
                quantityControl
            }
        }
        .padding(.horizontal, Const.contentInset)
        .padding(.bottom, Const.bottomInset)
    }

    private var offersSummary: some View {
        VStack(alignment: .leading, spacing: Const.priceSpacing) {
            storeBadges
            if let price = product.lowestPrice {
                HomePriceLabel(price: price)
                    .onestTextStyle(size: Const.nameFontSize, lineHeight: Const.nameLineHeight,
                                   weight: .semibold, relativeTo: .headline)
            }
        }
    }

    private var storeBadges: some View {
        HStack(spacing: Const.storeOverlap) {
            ForEach(Array(product.offers.enumerated()), id: \.element.id) { index, _ in
                Image.Home.storeAvatar
                    .foregroundStyle(Color.Background.placeholder)
                    .frame(width: Const.storeSize, height: Const.storeSize)
                    .shimmer()
                    .overlay(Circle().strokeBorder(Color.Border.primary, lineWidth: Const.borderWidth))
                    .zIndex(-Double(index))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Texts.Home.Product.offeredAtStores)
        .accessibilityValue(product.offers.map(\.name).joined(separator: ", "))
    }

    private var quantityControl: some View {
        HomeQuantityControl(productID: product.id, productName: product.name, quantity: $quantity)
    }

    private enum Const {
        static let contentSpacing: CGFloat = 4
        static let imageSpacing: CGFloat = 10
        static let controlsSpacing: CGFloat = 8
        static let priceSpacing: CGFloat = 2
        static let contentInset: CGFloat = 10
        static let bottomInset: CGFloat = 6
        static let cornerRadius: CGFloat = 16
        static let artworkCornerRadius: CGFloat = 10
        static let artworkAspectRatio: CGFloat = 1
        static let storeSize: CGFloat = 24
        static let storeOverlap: CGFloat = -4
        static let borderWidth: CGFloat = 1
        static let nameFontSize: CGFloat = 17
        static let nameLineHeight: CGFloat = 22
        static let packageFontSize: CGFloat = 13
        static let packageLineHeight: CGFloat = 18
        static let shadowOpacity: Double = 0.05
        static let shadowRadius: CGFloat = 4
        static let shadowOffset: CGFloat = 2
    }
}

struct HomePriceLabel: View {
    let price: Decimal

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Const.spacing) {
            Text(Texts.Home.Product.priceFrom)
            Text(price, format: .currency(code: "RUB").precision(.fractionLength(0)))
        }
        .foregroundStyle(Color.Label.primary)
        .accessibilityElement(children: .combine)
    }

    private enum Const {
        static let spacing: CGFloat = 4
    }
}

#Preview {
    @Previewable @State var quantity = 1
    HomeProductCard(product: HomeMockData.products[0], quantity: $quantity, open: {})
        .padding()
}
