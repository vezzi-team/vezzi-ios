import SwiftUI

struct AddressSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: AddressSearchViewModel
    @FocusState private var isSearchFocused: Bool
    let onSelect: (AddressSearchSelection) -> Void

    init(near coordinate: ShoppingCoordinate, service: any AddressSearching,
         onSelect: @escaping (AddressSearchSelection) -> Void) {
        _viewModel = StateObject(wrappedValue: AddressSearchViewModel(near: coordinate, service: service))
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            results
                .navigationTitle(Texts.Routes.AddressSearch.title)
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: queryBinding,
                            placement: .navigationBarDrawer(displayMode: .always),
                            prompt: Texts.Routes.AddressSearch.prompt)
                .searchFocused($isSearchFocused)
                .onSubmit(of: .search) { [focus = $isSearchFocused] in
                    focus.wrappedValue = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        dismissButton
                    }
                }
        }
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .onAppear { isSearchFocused = true }
        .task(id: scenePhase == .active ? viewModel.requestID : nil) {
            guard scenePhase == .active else { return }
            await viewModel.search()
        }
        .task(id: scenePhase == .active ? viewModel.selectedSuggestion?.id : nil) {
            guard scenePhase == .active, viewModel.selectedSuggestion != nil else { return }
            if let result = await viewModel.resolveSelection() {
                onSelect(result)
                dismiss()
            }
        }
    }

    // The native search field can keep its callbacks after the sheet closes.
    private var queryBinding: Binding<String> {
        Binding(
            get: { [weak viewModel] in viewModel?.query ?? "" },
            set: { [weak viewModel] in viewModel?.updateQuery($0) }
        )
    }

    private var dismissButton: some View {
        Button { dismiss() } label: {
            Label { Text(Texts.Routes.AddressSearch.dismiss) } icon: { Image.System.chevronDown }
        }
        .labelStyle(.iconOnly)
        .tint(Color.Label.primary)
        .accessibilityIdentifier(AccessibilityID.Routes.AddressSearch.cancel)
    }

    private var results: some View {
        Group {
            if viewModel.suggestions.isEmpty {
                feedbackContent
            } else {
                suggestions
            }
        }
        .screenStateFade(for: viewModel.suggestions.isEmpty)
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier(AccessibilityID.Routes.AddressSearch.results)
    }

    private var suggestions: some View {
        List {
            if viewModel.hasError {
                failureFeedback.listRowSeparator(.hidden)
            }
            ForEach(viewModel.suggestions) { suggestion in
                suggestionRow(suggestion)
            }
        }
        .listStyle(.plain)
    }

    private var feedbackContent: some View {
        GeometryReader { geometry in
            ScrollView {
                feedback.frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
    }

    private func suggestionRow(_ suggestion: AddressSuggestion) -> some View {
        Button {
            isSearchFocused = false
            viewModel.select(suggestion)
        } label: {
            HStack(spacing: Const.spacing) {
                VStack(alignment: .leading, spacing: Const.captionSpacing) {
                    Text(suggestion.title.addressCapitalized).foregroundStyle(Color.Label.primary)
                    if !suggestion.subtitle.isEmpty {
                        Text(suggestion.subtitle.addressCapitalized).font(.footnote).foregroundStyle(Color.Label.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if viewModel.selectedSuggestion == suggestion { ProgressView() }
            }
            .padding(.vertical, Const.captionSpacing)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.selectedSuggestion != nil)
        .accessibilityIdentifier(AccessibilityID.Routes.AddressSearch.suggestion(suggestion.id))
    }

    private var feedback: MotiStateView {
        if viewModel.hasError {
            return failureFeedback
        } else if !viewModel.canSearch {
            return MotiStateView(title: Texts.Routes.AddressSearch.hintTitle, description: Texts.Routes.AddressSearch.hint,
                          expression: .winking)
        } else if viewModel.isSearching {
            return MotiStateView(title: Texts.Routes.AddressSearch.loading, expression: .winking, isLoading: true)
        } else {
            return MotiStateView(title: Texts.Routes.AddressSearch.empty, description: Texts.Routes.AddressSearch.emptyDescription)
        }
    }

    private var failureFeedback: MotiStateView {
        MotiStateView(title: Texts.Routes.AddressSearch.failureTitle, description: Texts.Routes.AddressSearch.failure,
                      action: .init(title: Texts.Routes.retry, perform: viewModel.retry))
    }

    private enum Const {
        static let spacing: CGFloat = 12
        static let captionSpacing: CGFloat = 4
    }
}

#Preview("Address search") {
    AddressSearchView(near: .previewOrigin, service: PreviewAddressSearch()) { _ in }
}
