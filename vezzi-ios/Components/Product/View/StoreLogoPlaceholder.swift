import SwiftUI

struct StoreLogoPlaceholder: View {
    fileprivate enum Const { static let previewSize: CGFloat = 36 }

    var style: ShimmerStyle = .standard

    var body: some View {
        image
            .resizable()
            .scaledToFit()
            .foregroundStyle(style == .lighter ? Color.Background.placeholderLighter : Color.Background.placeholder)
            .shimmer(style: style)
            .accessibilityHidden(true)
    }

    private var image: Image {
        style == .lighter ? Image.Product.storeAvatar : Image.Product.storeIcon
    }
}

#Preview("Store logo") {
    StoreLogoPlaceholder()
        .frame(width: StoreLogoPlaceholder.Const.previewSize, height: StoreLogoPlaceholder.Const.previewSize)
        .padding()
}
