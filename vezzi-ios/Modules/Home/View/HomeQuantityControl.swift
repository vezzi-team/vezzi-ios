import SwiftUI

struct HomeQuantityControl: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let productID: String
    let productName: String
    @Binding var quantity: Int

    var body: some View {
        Group {
            if quantity == 0 {
                if dynamicTypeSize.isAccessibilitySize {
                    accessibleAddButton
                } else {
                    addButton
                }
            } else if dynamicTypeSize.isAccessibilitySize {
                accessibleStepper
            } else {
                compactStepper
            }
        }
    }

    // MARK: - Controls

    private var addButton: some View {
        Button { quantity = 1 } label: {
            symbol(Image.System.plus)
        }
        .buttonStyle(.plain)
        .background(alignment: .bottom) { controlBackground }
        .accessibilityLabel(Texts.Home.Quantity.addProduct(productName))
        .accessibilityIdentifier(AccessibilityID.Home.Quantity.add(productID))
    }

    private var compactStepper: some View {
        HStack(spacing: .zero) {
            Button { quantity = max(HomeViewModel.quantityRange.lowerBound, quantity - 1) } label: {
                symbol(Image.System.minus)
            }
            .accessibilityLabel(Texts.Home.Quantity.decreaseQuantity(productName))
            .accessibilityIdentifier(AccessibilityID.Home.Quantity.decrease(productID))
            quantityLabel
            Button { quantity = min(HomeViewModel.quantityRange.upperBound, quantity + 1) } label: {
                symbol(Image.System.plus)
            }
            .disabled(quantity >= HomeViewModel.quantityRange.upperBound)
            .accessibilityLabel(Texts.Home.Quantity.increaseQuantity(productName))
            .accessibilityIdentifier(AccessibilityID.Home.Quantity.increase(productID))
        }
        .buttonStyle(.plain)
        .background(alignment: .bottom) { controlBackground }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Texts.Home.Quantity.quantityOf(productName))
        .accessibilityValue(Text(quantity, format: .number))
        .accessibilityIdentifier(AccessibilityID.Home.productQuantity(productID))
    }

    private var quantityLabel: some View {
        Text(quantity, format: .number)
            .onestTextStyle(size: Const.fontSize, lineHeight: Const.lineHeight, relativeTo: .footnote)
            .monospacedDigit()
            .foregroundStyle(Color.Label.white)
            .frame(minWidth: Const.valueWidth, minHeight: Const.visualHeight)
            .frame(height: Const.controlHeight, alignment: .bottom)
            .accessibilityHidden(true)
    }

    private func symbol(_ image: Image) -> some View {
        image
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.Label.white)
            .frame(width: Const.buttonWidth, height: Const.visualHeight)
            .frame(height: Const.controlHeight, alignment: .bottom)
            .contentShape(.rect)
    }

    private var controlBackground: some View {
        RoundedRectangle(cornerRadius: Const.cornerRadius)
            .fill(Color.accentColor)
            .frame(height: Const.visualHeight)
    }

    private var accessibleStepper: some View {
        Stepper(value: $quantity, in: HomeViewModel.quantityRange) {
            Text(quantity, format: .number)
                .monospacedDigit()
                .onestTextStyle(.appText, weight: .semibold)
        }
        .accessibilityLabel(Texts.Home.Quantity.quantityOf(productName))
        .accessibilityValue(Text(quantity, format: .number))
        .accessibilityIdentifier(AccessibilityID.Home.productQuantity(productID))
    }

    private var accessibleAddButton: some View {
        Button { quantity = 1 } label: {
            Label { Text(Texts.Home.Quantity.add) } icon: { Image.System.plus }
        }
        .onestTextStyle(.appText, weight: .semibold)
        .buttonStyle(.glassProminent)
        .accessibilityLabel(Texts.Home.Quantity.addProduct(productName))
        .accessibilityIdentifier(AccessibilityID.Home.Quantity.add(productID))
    }

    private enum Const {
        static let buttonWidth: CGFloat = 28
        static let visualHeight: CGFloat = 28
        static let controlHeight: CGFloat = 44
        static let valueWidth: CGFloat = 20
        static let cornerRadius: CGFloat = 10
        static let fontSize: CGFloat = 13
        static let lineHeight: CGFloat = 18
    }
}

#Preview {
    @Previewable @State var quantity = 1
    let product = HomeMockData.products[0]
    HomeQuantityControl(productID: product.id, productName: product.name, quantity: $quantity)
        .padding()
}
