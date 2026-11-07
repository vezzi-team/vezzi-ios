import SwiftUI

struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    @ObservedObject var session: AuthenticationSession
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Const.sectionSpacing) {
                        hero.id(ScrollTarget.hero)
                        formContent
                        if viewModel.phase != .success {
                            termsLink
                                .transition(stateTransition)
                        }
                    }
                    .padding(Const.contentInset)
                    .frame(maxWidth: Const.maximumWidth)
                    .frame(maxWidth: .infinity)
                    .animation(stateAnimation, value: viewModel.phase)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .contentShape(.rect)
                .onTapGesture { focusedField = nil }
                .onChange(of: viewModel.phase) { _, phase in
                    if phase == .success {
                        withAnimation(stateAnimation) { proxy.scrollTo(ScrollTarget.hero, anchor: .top) }
                    }
                }
            }
            .background(Color.Background.elevated)
            .navigationTitle(Texts.Authentication.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { dismissToolbar }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(trigger: viewModel.phase) { _, phase in
            switch phase {
            case .success: return .success
            case .failure: return .error
            case .idle, .loading: return nil
            }
        }
        .task(id: viewModel.request?.id) {
            await viewModel.authenticate(using: session,
                                         successDuration: reduceMotion ? .zero : Const.successDuration)
        }
        .onChange(of: viewModel.didComplete) { _, didComplete in
            if didComplete { dismiss() }
        }
        .onDisappear { viewModel.cancel(using: session) }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: Const.heroSpacing) {
            MotiMascotView(state: mascotState)
                .frame(maxWidth: Const.mascotWidth)
            VStack(spacing: Const.copySpacing) {
                Text(heroTitle)
                    .appTextStyle(.appText, weight: .semibold)
                    .foregroundStyle(Color.Label.primary)
                Text(heroSubtitle)
                    .appTextStyle(.caption)
                    .foregroundStyle(Color.Label.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: Const.copyWidth)
            .id(heroTitle)
            .transition(reduceMotion ? .identity : .opacity)
        }
        .frame(maxWidth: .infinity)
    }

    private var mascotState: MotiMascotView.State {
        switch viewModel.phase {
        case .idle: return focusedField == nil ? .idle : .typing
        case .loading: return .loading
        case .failure: return .error
        case .success: return .success
        }
    }

    private var heroTitle: String {
        switch viewModel.phase {
        case .idle: return Texts.Authentication.greeting
        case .loading: return isRegistering ? Texts.Authentication.creatingAccount : Texts.Authentication.signingIn
        case .failure: return Texts.Authentication.tryAgain
        case .success: return Texts.Authentication.welcome
        }
    }

    private var heroSubtitle: String {
        switch viewModel.phase {
        case .loading: return Texts.Authentication.checkingCredentials
        case .success: return Texts.Authentication.continueShopping
        default: return Texts.Authentication.subtitle
        }
    }

    // MARK: - Form

    private var formContent: some View {
        ZStack(alignment: .top) {
            if viewModel.phase != .success {
                form
                    .transition(stateTransition)
            }
            // Keep Text alive so numericText can animate its content when authentication succeeds.
            LoginSuccessConfirmation(isVisible: viewModel.phase == .success)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Const.formSpacing) {
            if viewModel.phase == .idle, let error = session.lastError {
                errorMessage(error.message)
            }
            emailField
            passwordField
            if let error = viewModel.formError { errorMessage(error) }
            signInButton
            registerButton
        }
    }

    private var emailField: some View {
        inputField(title: Texts.Authentication.email,
                   error: viewModel.emailError) {
            TextField(Texts.Authentication.emailPlaceholder, text: $viewModel.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focusedField, equals: .email)
                .onSubmit { focusedField = .password }
                .accessibilityIdentifier(AccessibilityID.Authentication.email)
        }
    }

    private var passwordField: some View {
        inputField(title: Texts.Authentication.password,
                   error: viewModel.passwordError) {
            SecureField(Texts.Authentication.passwordPlaceholder, text: $viewModel.password)
                .textContentType(.password)
                .submitLabel(.go)
                .focused($focusedField, equals: .password)
                .onSubmit { submit(.signIn) }
                .privacySensitive()
                .accessibilityIdentifier(AccessibilityID.Authentication.password)
        }
    }

    private func inputField<Input: View>(title: String, error: String?, @ViewBuilder input: () -> Input) -> some View {
        VStack(alignment: .leading, spacing: Const.fieldSpacing) {
            Text(title)
                .appTextStyle(.caption, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)
            input()
                .appTextStyle(.appText)
                .padding(.horizontal, Const.fieldInset)
                .frame(minHeight: Const.fieldHeight)
                .background(viewModel.isBusy ? Color.Background.secondary : Color.Background.elevated,
                            in: .rect(cornerRadius: Const.fieldRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: Const.fieldRadius)
                        .strokeBorder(error == nil ? Color.Border.primary : Color.Label.error,
                                      lineWidth: Const.borderWidth)
                }
                .disabled(viewModel.isBusy)
                .accessibilityLabel(title)
                .accessibilityHint(error ?? "")
            if let error { errorMessage(error) }
        }
        .foregroundStyle(Color.Label.primary)
    }

    private func errorMessage(_ text: String) -> some View {
        Text(text)
            .appTextStyle(.caption)
            .foregroundStyle(Color.Label.error)
            .fixedSize(horizontal: false, vertical: true)
            .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: Const.messageScale, anchor: .topLeading)))
            .accessibilityIdentifier(AccessibilityID.Authentication.error)
    }

    private var signInButton: some View {
        Button { submit(.signIn) } label: {
            actionLabel(title: Texts.Authentication.signIn, isLoading: isSigningIn)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(viewModel.isBusy)
        .accessibilityLabel(isSigningIn ? Texts.Authentication.signingIn : Texts.Authentication.signIn)
        .accessibilityIdentifier(AccessibilityID.Authentication.signIn)
    }

    private func actionLabel(title: String, isLoading: Bool) -> some View {
        // Keep the title's layout, including Dynamic Type wrapping, while replacing its visible content.
        Text(title)
            .appTextStyle(.appText, weight: .semibold)
            .hidden()
            .frame(maxWidth: .infinity, minHeight: Const.buttonContentHeight)
            .overlay {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(Color.Label.primary)
                            .transition(stateTransition)
                    } else {
                        Text(title)
                            .appTextStyle(.appText, weight: .semibold)
                            .transition(stateTransition)
                    }
                }
            }
            .accessibilityHidden(true)
    }

    private var termsLink: some View {
        Button {
            focusedField = nil
            // TODO: Open the terms URL when it is available.
        } label: {
            Text(Texts.Profile.Main.terms)
                .appTextStyle(.caption)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: Const.linkHeight)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityAddTraits(.isLink)
        .accessibilityRemoveTraits(.isButton)
        .accessibilityIdentifier(AccessibilityID.Authentication.terms)
    }

    private var isSigningIn: Bool {
        viewModel.phase == .loading && viewModel.request?.intent == .signIn
    }

    private var isRegistering: Bool {
        viewModel.phase == .loading && viewModel.request?.intent == .register
    }

    private var registerButton: some View {
        Button { submit(.register) } label: {
            actionLabel(title: Texts.Authentication.register, isLoading: isRegistering)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .tint(Color.Label.primary)
        .disabled(viewModel.isBusy)
        .accessibilityLabel(isRegistering ? Texts.Authentication.creatingAccount : Texts.Authentication.register)
        .accessibilityIdentifier(AccessibilityID.Authentication.register)
    }

    private var dismissToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                viewModel.cancel(using: session)
                dismiss()
            } label: {
                Label { Text(Texts.Authentication.close) } icon: { Image.System.xmark }
            }
            .tint(Color.Label.primary)
            .accessibilityIdentifier(AccessibilityID.Authentication.close)
        }
    }

    private func submit(_ intent: AuthenticationIntent) {
        viewModel.submit(intent)
        switch viewModel.phase {
        case .loading, .success: focusedField = nil
        case .failure(.invalidEmail), .failure(.emailAlreadyRegistered): focusedField = .email
        case .failure(.missingPassword), .failure(.passwordTooShort), .failure(.passwordTooLong): focusedField = .password
        default: break
        }
    }

    private var stateAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: Const.animationDuration)
    }

    private var stateTransition: AnyTransition {
        reduceMotion ? .identity : AnyTransition(.blurReplace)
    }

    private enum Field: Hashable { case email, password }
    private enum ScrollTarget { case hero }

    private enum Const {
        static let maximumWidth: CGFloat = 480
        static let contentInset: CGFloat = 16
        static let sectionSpacing: CGFloat = 24
        static let heroSpacing: CGFloat = 16
        static let copySpacing: CGFloat = 6
        static let formSpacing: CGFloat = 16
        static let fieldSpacing: CGFloat = 8
        static let mascotWidth: CGFloat = 294
        static let copyWidth: CGFloat = 310
        static let fieldInset: CGFloat = 12
        static let fieldHeight: CGFloat = 48
        static let fieldRadius: CGFloat = 10
        static let borderWidth: CGFloat = 1
        static let buttonContentHeight: CGFloat = 24
        static let linkHeight: CGFloat = 44
        static let messageScale: CGFloat = 0.96
        static let animationDuration: TimeInterval = 0.26
        static let successDuration: Duration = .milliseconds(900)
    }
}

private struct LoginSuccessConfirmation: View {
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(isVisible ? Texts.Authentication.successTitle : "")
            .appTextStyle(.title)
            .foregroundStyle(Color.accentColor)
            .multilineTextAlignment(.center)
            .lineLimit(Const.lineLimit)
            .minimumScaleFactor(Const.minimumScaleFactor)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .allowsHitTesting(false)
            .accessibilityHidden(!isVisible)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(AccessibilityID.Authentication.success)
    }

    private enum Const {
        static let lineLimit = 2
        static let minimumScaleFactor: CGFloat = 0.5
    }
}

#Preview("Login") {
    LoginView(session: AuthenticationSession.preview())
}

#Preview("Login — dark, large text") {
    LoginView(session: AuthenticationSession.preview())
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Login — welcome animation") {
    @Previewable @State var isVisible = false

    VStack {
        LoginSuccessConfirmation(isVisible: isVisible)
        Button(Texts.Authentication.signIn) {
            withAnimation(.smooth) { isVisible.toggle() }
        }
        .buttonStyle(.glassProminent)
    }
    .padding()
}
