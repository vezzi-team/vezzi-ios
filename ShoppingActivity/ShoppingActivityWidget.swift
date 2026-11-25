import ActivityKit
import SwiftUI
import WidgetKit

@main
struct ShoppingActivityWidgets: WidgetBundle {
    var body: some Widget { ShoppingActivityWidget() }
}

private typealias TripState = ShoppingActivityAttributes.ContentState

private struct ShoppingActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShoppingActivityAttributes.self) { context in
            ShoppingActivityCard(state: context.state)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .widgetURL(context.attributes.progressURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    ShoppingActivityCard(state: context.state)
                }
            } compactLeading: {
                StoreBadge(state: context.state)
            } compactTrailing: {
                Text(verbatim: "\(context.state.bought)/\(context.state.total)")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                    .accessibilityLabel(Text("Bought"))
                    .accessibilityValue(Text(verbatim: "\(context.state.bought) / \(context.state.total)"))
            } minimal: {
                StoreBadge(state: context.state)
            }
            .keylineTint(.shoppingAccent)
            .widgetURL(context.attributes.progressURL)
        }
    }
}

private extension Color {
    static let shoppingAccent = Color("AccentColor")
}

private extension ShoppingActivityAttributes.Stage {
    var title: LocalizedStringKey {
        switch self {
        case .walking: "On the way to the store"
        case .shopping: "At the store"
        case .returning: "Heading home"
        case .summary: "Shopping summary"
        case .finishing: "Finishing shopping"
        }
    }

    var symbol: String {
        switch self {
        case .walking: "figure.walk"
        case .shopping: "basket.fill"
        case .returning: "house.fill"
        case .summary: "checklist"
        case .finishing: "arrow.triangle.2.circlepath"
        }
    }
}

private struct ShoppingActivityCard: View {
    let state: TripState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.stage.symbol)
                .resizable().scaledToFit()
                .foregroundStyle(Color.shoppingAccent)
                .frame(width: 40, height: 40)
                .padding(.vertical, 8)
                .frame(width: 57)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if state.storeName == nil {
                    Text(state.stage.title)
                        .font(.title3.bold())
                        .lineLimit(2)
                }

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.spent, format: .currency(code: "RUB").precision(.fractionLength(0...2)))
                            .font(.title2.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                            .accessibilityLabel(Text("Spent"))
                            .accessibilityValue(Text(state.spent, format: .currency(code: "RUB").precision(.fractionLength(0...2))))
                        HStack(spacing: 4) {
                            Text("Bought")
                            Text(verbatim: "\(state.bought) / \(state.total)").monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                    }
                    .layoutPriority(1)
                    if let storeName = state.storeName {
                        Text(verbatim: storeName)
                            .font(.title3.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .allowsTightening(true)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityHint(Text(state.stage.title))
                    }
                }
                ProgressView(value: Double(state.bought), total: Double(max(state.total, 1)))
                    .progressViewStyle(ShoppingProgressStyle())
                    .accessibilityHidden(true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ShoppingProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        Capsule()
            .fill(.primary.opacity(0.25))
            .overlay {
                GeometryReader { track in
                    Capsule()
                        .fill(Color.shoppingAccent)
                        .frame(width: track.size.width * (configuration.fractionCompleted ?? 0))
                }
            }
            .frame(height: 4)
    }
}

private struct StoreBadge: View {
    let state: TripState

    var body: some View {
        if let data = state.storeLogo, let image = UIImage(data: data) {
            Image(uiImage: image).renderingMode(.original).resizable().scaledToFit()
                .frame(width: 22, height: 22).clipShape(.circle)
                .accessibilityLabel(Text(verbatim: state.storeName ?? ""))
        } else if let name = state.storeName, let initial = name.first {
            Text(verbatim: String(initial).uppercased())
                .font(.caption.bold()).foregroundStyle(Color.shoppingAccent)
                .frame(width: 22, height: 22)
                .background(Color.shoppingAccent.opacity(0.18), in: .circle)
                .accessibilityLabel(Text(verbatim: name))
        } else {
            Image(systemName: state.stage.symbol)
                .foregroundStyle(Color.shoppingAccent)
                .accessibilityLabel(Text(state.stage.title))
        }
    }
}

private extension ShoppingActivityAttributes {
    static let preview = Self(sessionID: UUID(), planID: UUID())
}

private extension ShoppingActivityAttributes.ContentState {
    static let preview = Self(stage: .shopping, storeID: "1", storeName: "Перекрёсток",
                              bought: 3, total: 7, spent: 329.50)
}

#Preview("Lock Screen", as: .content, using: ShoppingActivityAttributes.preview) {
    ShoppingActivityWidget()
} contentStates: {
    ShoppingActivityAttributes.ContentState.preview
}

#Preview("Compact", as: .dynamicIsland(.compact), using: ShoppingActivityAttributes.preview) {
    ShoppingActivityWidget()
} contentStates: {
    ShoppingActivityAttributes.ContentState.preview
}
