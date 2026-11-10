import SwiftUI

struct ShoppingPlanStoresView: View {
    let stops: [ShoppingPlanStop]

    var body: some View {
        VStack(spacing: Const.spacing) {
            ForEach(stops) { stop in
                ShoppingPlanStoreRow(stop: stop)
            }
        }
        .padding(Const.inset)
        .frame(idealWidth: Const.width)
        .environment(\.isShimmerEnabled, true)
        .accessibilityIdentifier(AccessibilityID.ShoppingList.storePopover)
    }

    private enum Const {
        static let spacing: CGFloat = 12
        static let inset: CGFloat = 16
        static let width: CGFloat = 320
    }
}

struct ShoppingPlanStoreRow: View {
    let stop: ShoppingPlanStop

    var body: some View {
        HStack(alignment: .top, spacing: Const.spacing) {
            StoreLogoPlaceholder()
                .frame(width: Const.logoSize, height: Const.logoSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Const.captionSpacing) {
                Text(stop.store.chainName ?? stop.store.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.Label.primary)
                if let address = StoreDisplayText.address(stop.store.address) {
                    Text(address).font(.caption).foregroundStyle(Color.Label.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Texts.ShoppingList.products(stop.items.count))
                .font(.caption).foregroundStyle(Color.Label.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private enum Const {
        static let spacing: CGFloat = 12
        static let logoSize: CGFloat = 28
        static let captionSpacing: CGFloat = 2
    }
}
