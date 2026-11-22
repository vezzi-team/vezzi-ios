import SwiftUI

/// All pages are destinations in the route's existing NavigationStack.
struct ShoppingProgressView: View {
    let trip: ShoppingTrip
    let page: ShoppingTrip.Page
    let isCurrent: Bool
    @ObservedObject var list: ShoppingListRepository
    let next: (ShoppingTrip.Page) -> Void
    @State private var confirmsFinish = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        Group {
            switch page {
            case .route(let id):
                if let index = trip.plan.stops.firstIndex(where: { $0.id == id }) {
                    ShoppingLegView(trip: trip, index: index, isCurrent: isCurrent) { next(.store(id)) }
                }
            case .returnHome:
                ShoppingLegView(trip: trip, index: trip.plan.stops.count, isCurrent: isCurrent) { next(.summary) }
            case .store(let id), .editStore(let id):
                if let index = trip.plan.stops.firstIndex(where: { $0.id == id }) { storePage(index) }
            case .summary:
                summaryPage
            }
        }
        .background(Color.Background.primary)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .alert(Texts.Trip.saveError, isPresented: Binding(get: { list.tripFailure != nil },
                                                          set: { if !$0 { list.clearTripFailure() } })) {
            Button(Texts.ShoppingList.understood, role: .cancel) {}
        }
    }

    private var title: String {
        switch page {
        case .route, .returnHome: Texts.Trip.route
        case .store, .editStore: Texts.Trip.shopping
        case .summary: Texts.Trip.summary
        }
    }

    private func storePage(_ index: Int) -> some View {
        let stop = trip.plan.stops[index]
        let following: ShoppingPlanStop? = if case .editStore = page { nil } else { trip.plan.stops.dropFirst(index + 1).first }
        let destination: ShoppingTrip.Page
        if case .editStore = page { destination = .summary }
        else if let following { destination = .route(following.id) }
        else { destination = trip.returnsHome ? .returnHome : .summary }
        return storeContents(stop, following: following)
            .safeAreaBar(edge: .bottom) {
                ShoppingRouteButton(placement: .bottomBar) {
                    next(destination)
                } label: {
                    Text(destination == .summary ? Texts.Trip.viewSummary : Texts.Trip.nextRoute)
                }
                .accessibilityIdentifier(AccessibilityID.Trip.next)
            }
    }

    private func storeContents(_ stop: ShoppingPlanStop, following: ShoppingPlanStop?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                TripStoreLabel(stop: stop, large: true)
                purchaseMetrics(stop)
                HStack(alignment: .firstTextBaseline) {
                    Text(Texts.Trip.products).font(.title3.bold())
                    Spacer()
                    Text(Texts.ShoppingList.products(stop.items.count) + " · " + TripFormat.price(stop.subtotal))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: ProductGridLayout.columns(for: textSize), spacing: 12) {
                    ForEach(stop.items, id: \.product.id) { item in
                        ProductCard(product: item.cardProduct(in: stop.store), showsPricePrefix: false,
                                    isPurchased: item.isBought, quantity: .constant(item.quantity)) {
                            guard let id = item.itemID else { return }
                            list.togglePurchase(itemID: id, planID: trip.plan.id)
                        }
                        .disabled(item.itemID == nil || trip.pendingFinish != nil)
                    }
                }
                progressHint(Texts.Trip.markHint)
                if let following { nextStore(following) }
                else { totals(compact: true) }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }

    private func purchaseMetrics(_ stop: ShoppingPlanStop) -> some View {
        let bought = stop.boughtItems.count
        let spent = stop.spent
        return VStack(spacing: 12) {
            LabeledContent(Texts.Trip.boughtAtStore) {
                Text(Texts.Trip.count(bought, stop.items.count))
                    .contentTransition(reduceMotion ? .identity : .numericText(value: Double(bought)))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: bought)
            }
            .font(.headline)
            LabeledContent(Texts.Trip.amount) {
                animatedAmount(spent)
                    .fontWeight(.semibold)
            }
        }
        .monospacedDigit()
        .tripCard()
    }

    private func nextStore(_ stop: ShoppingPlanStop) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(Texts.Trip.nextStore).font(.caption).foregroundStyle(.secondary)
            Text([stop.store.chainName ?? stop.store.name, StoreDisplayText.address(stop.store.address)]
                .compactMap { $0 }.joined(separator: " · ")).font(.headline)
        }
        .tripCard(tint: Color.accentColor.opacity(0.08))
    }

    private var summaryPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                totals(compact: false)
                Text(Texts.Trip.byStore).font(.title3.bold())
                ForEach(trip.plan.stops) { stop in
                    Button { next(.editStore(stop.id)) } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                TripStoreLabel(stop: stop)
                                Spacer(minLength: 4)
                                Text(TripFormat.price(stop.spent)).font(.headline)
                                Image.System.chevronRight.font(.footnote).foregroundStyle(.secondary)
                            }
                            Divider()
                            if stop.boughtItems.isEmpty {
                                Text(Texts.Trip.noneBought).font(.footnote).foregroundStyle(.secondary)
                            } else {
                                ForEach(stop.boughtItems, id: \.product.id) { item in
                                    LabeledContent(item.cardProduct(in: stop.store).displayName,
                                                   value: Texts.Trip.quantity(item.quantity)).font(.footnote)
                                }
                            }
                        }
                        .tripCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(AccessibilityID.Trip.store(stop.id))
                }
                progressHint(Texts.Trip.editHint)
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .safeAreaBar(edge: .bottom) { finishButton }
    }

    private var finishButton: some View {
        let isFinishing = trip.pendingFinish != nil && list.isBusy
        let title = trip.pendingFinish != nil && !isFinishing ? Texts.Routes.retry : Texts.Trip.finish
        return ShoppingRouteButton(placement: .footer) {
            if let pending = trip.pendingFinish { finish(pending) }
            else { confirmsFinish = true }
        } label: {
            Text(Texts.Trip.finish)
                .hidden()
                .overlay {
                    if isFinishing {
                        ProgressView().controlSize(.regular).tint(Color.Label.primary)
                    } else { Text(title) }
                }
        }
        .tint(Color.accentColor)
        .accessibilityLabel(title)
        .accessibilityIdentifier(AccessibilityID.Trip.next)
        .disabled(isFinishing)
        .alert(Texts.Trip.finishQuestion, isPresented: $confirmsFinish) {
            Button(Texts.Trip.deleteList) { finish(.delete) }
            Button(Texts.Trip.keepList) { finish(.keep) }
            Button(Texts.Authentication.cancel, role: .cancel) {}
        }
        .tint(Color.Label.primary)
    }

    private func finish(_ disposition: ShoppingTrip.ListDisposition) {
        Task { await list.finishShopping(disposition) }
    }

    private func progressHint(_ defaultText: String) -> some View {
        let text: String
        if list.hasCacheFailure { text = Texts.ShoppingList.cacheError }
        else if trip.needsSync && list.failure == .offline {
            text = trip.pendingFinish == nil ? Texts.Trip.offlineMarks : Texts.Trip.offlineFinish
        } else { text = defaultText }
        return Text(text).font(.footnote).foregroundStyle(.secondary)
    }

    private func totals(compact: Bool) -> some View {
        let amount = animatedAmount(trip.spent).font(compact ? .title3.bold() : .largeTitle.bold())
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Texts.Trip.total).font(.headline)
                if compact { Spacer(); amount }
            }
            if !compact { amount }
            Text(Texts.Trip.bought(trip.boughtCount, trip.items.count)).font(.subheadline).foregroundStyle(.secondary)
        }
        .tripCard()
    }

    private func animatedAmount(_ amount: Decimal) -> some View {
        Text(TripFormat.price(amount))
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText(value: NSDecimalNumber(decimal: amount).doubleValue))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: amount)
    }
}

private enum TripFormat {
    static func price(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: "RUB").precision(.fractionLength(0...2)))
    }
}

extension View {
    fileprivate func tripCard(tint: Color = Color.Background.elevated) -> some View {
        padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(tint, in: .rect(cornerRadius: 20))
    }
}

struct TripStoreLabel: View {
    let stop: ShoppingPlanStop
    var caption: String?
    var large = false

    var body: some View {
        let name = stop.store.chainName ?? stop.store.name
        HStack(spacing: 12) {
            Text(String(name.prefix(1)).uppercased()).font(.title3.bold())
                .frame(width: 46, height: 46)
                .background(Color.Background.placeholder, in: .rect(cornerRadius: 15))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if let caption { Text(caption).font(.caption).foregroundStyle(.secondary) }
                Text(name).font(large ? .title.bold() : .headline)
                if caption == nil, let address = StoreDisplayText.address(stop.store.address) {
                    Text(address.addressCapitalized).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

