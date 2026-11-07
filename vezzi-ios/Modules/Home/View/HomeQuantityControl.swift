import SwiftUI

struct HomeQuantityControl: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace
    @ScaledMetric(relativeTo: .subheadline) private var valueWidth = Const.valueWidth
    @ScaledMetric(relativeTo: .footnote) private var addSymbolSize = Const.addSymbolSize
    let productID: String
    let productName: String
    @Binding var quantity: Int

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                if quantity == 0 {
                    accessibleAddButton
                } else {
                    accessibleStepper
                }
            } else {
                compactControl
            }
        }
        .animation(quantityAnimation, value: quantity)
    }

    // MARK: - Controls

    private var compactControl: some View {
        // Separate effect IDs let the inserted and removed glass surfaces morph into each other.
        GlassEffectContainer(spacing: Const.glassSpacing) {
            ZStack(alignment: .bottomTrailing) {
                if quantity == 0 {
                    addButton
                } else {
                    compactStepper
                }
            }
            // Keep a stable slot for both the add button and the expanded counter.
            .frame(minWidth: Const.buttonWidth * 2 + valueWidth,
                   minHeight: Const.addButtonSize, alignment: .bottomTrailing)
        }
    }

    private var addButton: some View {
        Button { setQuantity(1) } label: {
            Image.System.plus
                .font(.system(size: addSymbolSize, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: Const.addButtonSize, height: Const.addButtonSize)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID(Const.addGlassID, in: glassNamespace)
        .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        .accessibilityLabel(Texts.Home.Quantity.addProduct(productName))
        .accessibilityIdentifier(AccessibilityID.Home.Quantity.add(productID))
    }

    private var compactStepper: some View {
        HStack(spacing: .zero) {
            Button { setQuantity(max(HomeViewModel.quantityRange.lowerBound, quantity - 1)) } label: {
                symbol(Image.System.minus)
            }
            .accessibilityLabel(Texts.Home.Quantity.decreaseQuantity(productName))
            .accessibilityIdentifier(AccessibilityID.Home.Quantity.decrease(productID))
            quantityLabel
            Button { setQuantity(min(HomeViewModel.quantityRange.upperBound, quantity + 1)) } label: {
                symbol(Image.System.plus)
            }
            .disabled(quantity >= HomeViewModel.quantityRange.upperBound)
            .accessibilityLabel(Texts.Home.Quantity.increaseQuantity(productName))
            .accessibilityIdentifier(AccessibilityID.Home.Quantity.increase(productID))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID(Const.counterGlassID, in: glassNamespace)
        .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        .frame(height: Const.controlHeight, alignment: .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Texts.Home.Quantity.quantityOf(productName))
        .accessibilityValue(Text(quantity, format: .number))
        .accessibilityIdentifier(AccessibilityID.Home.productQuantity(productID))
    }

    private var quantityLabel: some View {
        Text(quantity, format: .number)
            .appTextStyle(size: Const.fontSize, lineHeight: Const.lineHeight, relativeTo: .footnote)
            .monospacedDigit()
            .contentTransition(numberTransition)
            .foregroundStyle(Color.Label.primary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: valueWidth, minHeight: Const.visualHeight)
            .accessibilityHidden(true)
    }

    private func symbol(_ image: Image) -> some View {
        image
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: Const.buttonWidth, height: Const.visualHeight)
            .contentShape(Rectangle().inset(by: -Const.hitInset))
    }

    private var accessibleStepper: some View {
        Stepper(value: $quantity, in: HomeViewModel.quantityRange) {
            Text(quantity, format: .number)
                .monospacedDigit()
                .appTextStyle(.appText, weight: .semibold)
                .contentTransition(numberTransition)
        }
        .accessibilityLabel(Texts.Home.Quantity.quantityOf(productName))
        .accessibilityValue(Text(quantity, format: .number))
        .accessibilityIdentifier(AccessibilityID.Home.productQuantity(productID))
    }

    private var accessibleAddButton: some View {
        Button { setQuantity(1) } label: {
            Label { Text(Texts.Home.Quantity.add) } icon: { Image.System.plus }
        }
        .appTextStyle(.appText, weight: .semibold)
        .buttonStyle(.glass)
        .accessibilityLabel(Texts.Home.Quantity.addProduct(productName))
        .accessibilityIdentifier(AccessibilityID.Home.Quantity.add(productID))
    }

    // MARK: - Animation

    private func setQuantity(_ value: Int) {
        withAnimation(quantityAnimation) { quantity = value }
    }

    private var quantityAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: Const.animationDuration)
    }

    private var numberTransition: ContentTransition {
        reduceMotion ? .identity : .numericText(value: Double(quantity))
    }

    private enum Const {
        static let buttonWidth: CGFloat = 28
        static let visualHeight: CGFloat = 34
        static let addButtonSize: CGFloat = 46
        static let addSymbolSize: CGFloat = 18
        static let controlHeight: CGFloat = 44
        static let hitInset = (controlHeight - visualHeight) / 2
        static let valueWidth: CGFloat = 20
        static let fontSize: CGFloat = 15
        static let lineHeight: CGFloat = 20
        static let animationDuration: TimeInterval = 0.3
        static let glassSpacing: CGFloat = 40
        static let addGlassID = "add"
        static let counterGlassID = "quantity"
    }
}

#Preview("Quantity — light") {
    @Previewable @State var quantity = 0
    let product = HomeMockData.products[0]
    HomeQuantityControl(productID: product.id, productName: product.name, quantity: $quantity)
        .padding()
        .background(Color.Background.placeholder)
        .preferredColorScheme(.light)
}

#Preview("Quantity — dark") {
    @Previewable @State var quantity = 1
    let product = HomeMockData.products[0]
    HomeQuantityControl(productID: product.id, productName: product.name, quantity: $quantity)
        .padding()
        .background(Color.Background.placeholder)
        .preferredColorScheme(.dark)
}

#Preview("Quantity — accessibility") {
    @Previewable @State var quantity = 0
    let product = HomeMockData.products[0]
    HomeQuantityControl(productID: product.id, productName: product.name, quantity: $quantity)
        .padding()
        .dynamicTypeSize(.accessibility3)
}
