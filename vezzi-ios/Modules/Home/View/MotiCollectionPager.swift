import SwiftUI

/// Three editorial artwork placeholders from the Home design.
struct MotiCollectionPager: View {
    @State private var selection = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let colors = [Color.MotiCollection.pasta, Color.MotiCollection.cinema, Color.MotiCollection.salad]

    var body: some View {
        VStack(spacing: 6) {
            TabView(selection: $selection) {
                ForEach(colors.indices, id: \.self) { index in
                    deck(index).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .aspectRatio(322 / 178, contentMode: .fit)
            .frame(maxWidth: 322)
            HStack(spacing: 4) {
                ForEach(colors.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == selection ? Color.Label.secondary : Color.Label.tertiary)
                        .frame(width: index == selection ? 14 : 4, height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Texts.Home.Discovery.moti)
        .accessibilityValue([Texts.Home.Discovery.pasta, Texts.Home.Discovery.movies, Texts.Home.Discovery.salad][selection])
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(min(selection + 1, 2))
            case .decrement: select(max(selection - 1, 0))
            @unknown default: break
            }
        }
    }

    private func deck(_ index: Int) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack {
                sideCard((index + 2) % 3, width: width, side: -1)
                sideCard((index + 1) % 3, width: width, side: 1)
                card(index)
                    .frame(width: width * 250 / 322, height: width * 170 / 322)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func sideCard(_ index: Int, width: CGFloat, side: CGFloat) -> some View {
        Button { select(index) } label: { card(index) }
            .buttonStyle(.plain)
            .frame(width: width * 220 / 322, height: width * 150 / 322)
            .rotationEffect(.degrees(5 * side))
            .offset(x: side * width * 45 / 322, y: 0)
    }

    private func card(_ index: Int) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(colors[index])
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.Border.primary))
            .shadow(color: Color.Shadow.primary.opacity(0.08), radius: 3, y: 2)
    }

    private func select(_ index: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selection = index }
    }
}
