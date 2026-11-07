import SwiftUI

struct ProductActions: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace
    @ScaledMetric(relativeTo: .body) private var actionHeight = Const.actionHeight

    let productName: String
    @Binding var quantity: Int

    var body: some View {
        VStack(spacing: Const.spacing) {
            GlassEffectContainer {
                ZStack {
                    if quantity == 0 {
                        addButton
                    } else {
                        quantityControl
                    }
                }
                .frame(minHeight: actionHeight)
            }
            hint
        }
        .animation(quantityAnimation, value: quantity)
    }

    // MARK: - Controls

    private var addButton: some View {
        Button { quantity = 1 } label: {
            Text(Texts.Product.Quantity.add)
                .appTextStyle(size: Const.buttonFontSize, lineHeight: Const.buttonLineHeight,
                               weight: .semibold, relativeTo: .headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .glassEffectID(Const.addGlassID, in: glassNamespace)
        .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        .accessibilityLabel(Texts.Product.Quantity.addProduct(productName))
        .accessibilityIdentifier(AccessibilityID.Product.Detail.add)
    }

    private var quantityControl: some View {
        HStack(spacing: .zero) {
            Button { quantity = max(ProductSelection.quantityRange.lowerBound, quantity - 1) } label: {
                symbol(Image.System.minus)
            }
            .accessibilityLabel(Texts.Product.Quantity.decreaseQuantity(productName))
            .accessibilityIdentifier(AccessibilityID.Product.Detail.decrease)
            quantityLabel
            Button { quantity = min(ProductSelection.quantityRange.upperBound, quantity + 1) } label: {
                symbol(Image.System.plus)
            }
            .disabled(quantity >= ProductSelection.quantityRange.upperBound)
            .accessibilityLabel(Texts.Product.Quantity.increaseQuantity(productName))
            .accessibilityIdentifier(AccessibilityID.Product.Detail.increase)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.Label.white)
        .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
        .glassEffectID(Const.counterGlassID, in: glassNamespace)
        .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Texts.Product.Quantity.quantityOf(productName))
        .accessibilityValue(Text(quantity, format: .number))
        .accessibilityIdentifier(AccessibilityID.Product.Detail.quantity)
    }

    private var quantityLabel: some View {
        Text(quantity, format: .number)
            .appTextStyle(size: Const.numberFontSize, lineHeight: Const.numberLineHeight, relativeTo: .title2)
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText(value: Double(quantity)))
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private func symbol(_ image: Image) -> some View {
        image
            .font(.title3.weight(.medium))
            .frame(width: actionHeight, height: actionHeight)
            .contentShape(.rect)
    }

    private var hint: some View {
        Text(quantity == 0 ? Texts.Product.compareHint : Texts.Product.inList)
            .appTextStyle(size: Const.hintFontSize, lineHeight: Const.hintLineHeight, relativeTo: .subheadline)
            .foregroundStyle(Color.Label.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            // Replace complete labels in a fixed-width slot to keep the transition centered.
            .id(quantity == 0)
            .transition(reduceMotion ? .identity : AnyTransition(.blurReplace))
            .accessibilityIdentifier(AccessibilityID.Product.Detail.hint)
    }

    private var quantityAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: Const.animationDuration)
    }

    private enum Const {
        static let spacing: CGFloat = 4
        static let actionHeight: CGFloat = 52
        static let buttonFontSize: CGFloat = 17
        static let buttonLineHeight: CGFloat = 22
        static let numberFontSize: CGFloat = 25
        static let numberLineHeight: CGFloat = 30
        static let hintFontSize: CGFloat = 15
        static let hintLineHeight: CGFloat = 20
        static let animationDuration: TimeInterval = 0.3
        static let addGlassID = "add"
        static let counterGlassID = "quantity"
    }
}

#Preview("Product actions") {
    @Previewable @State var quantity = 0
    ProductActions(productName: ProductMockData.products[0].name, quantity: $quantity)
        .padding()
}

#Preview("Product actions — dark, large text") {
    @Previewable @State var quantity = 1
    ProductActions(productName: ProductMockData.products[0].name, quantity: $quantity)
        .padding()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
