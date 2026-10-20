import SwiftUI

/// Sign-in: the wordmark centred over the photo, three stacked capsule buttons, and a "Log in" link.
/// Email opens an inline form in the same place as the buttons.
struct OnboardingView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var emailMode = false
    @State private var isSignUp = true
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field { case email, password }
    private var canSubmit: Bool { !email.isEmpty && !password.isEmpty && !authManager.isLoading }

    var body: some View {
        ZStack {
            AppBackdrop(intensity: 1)
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button("Skip") { authManager.continueAsGuest() }
                        .font(.system(size: 15)).foregroundColor(.ncPrimary.opacity(0.8))
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .accessibilityHint("Use Vitalis without an account")
                }
                Spacer()
            }
            .zIndex(1)

            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer().frame(height: geo.size.height * 0.27)
                    wordmark
                    Spacer(minLength: 32)

                    VStack(spacing: 14) {
                        if emailMode { emailForm } else { providerButtons }
                    }
                    .disabled(authManager.isLoading)
                    .opacity(authManager.isLoading ? 0.6 : 1)

                    if let error = authManager.authError {
                        Text(error).font(.system(size: 13)).foregroundColor(.ncEmber)
                            .multilineTextAlignment(.center)
                            .padding(.top, 14)
                    }

                    footer
                        .padding(.top, 28)

                    VStack(spacing: 2) {
                        Text("By continuing you agree to our")
                            .font(.system(size: 12)).foregroundColor(.ncPrimary.opacity(0.55))
                        LegalLinks()
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 44)
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .animation(.easeOut(duration: 0.22), value: emailMode)
        .onSubmit {
            if focus == .email { focus = .password } else { submit() }
        }
    }

    private var wordmark: some View {
        VStack(spacing: 22) {
            Text("VITALIS")
                .font(.system(size: 44, weight: .regular))
                .tracking(19)
                .padding(.leading, 19) // optically recentre the trailing tracking
                .foregroundColor(.ncPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text("Nutrition built on real food")
                .font(.system(size: 11, weight: .medium)).tracking(3.6).textCase(.uppercase)
                .foregroundColor(.ncPrimary.opacity(0.85))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var providerButtons: some View {
        Button { Task { await authManager.signInWithApple() } } label: {
            AuthButtonLabel(title: "Continue with Apple") {
                Image(systemName: "applelogo").font(.system(size: 19, weight: .medium))
            }
        }
        .buttonStyle(CapsuleAuthButtonStyle(filled: true))

        Button { Task { await authManager.signInWithGoogle() } } label: {
            AuthButtonLabel(title: "Continue with Google") {
                GoogleGMark(color: .ncPrimary).frame(width: 18, height: 18)
            }
        }
        .buttonStyle(CapsuleAuthButtonStyle(filled: false))

        Button { openEmail(signUp: true) } label: {
            AuthButtonLabel(title: "Continue with Email") {
                Image(systemName: "envelope").font(.system(size: 16, weight: .regular))
            }
        }
        .buttonStyle(CapsuleAuthButtonStyle(filled: false))
    }

    @ViewBuilder
    private var emailForm: some View {
        authField("Email", text: $email, field: .email)
        authField("Password", text: $password, field: .password, secure: true)

        Button(action: submit) {
            Text(isSignUp ? "Create account" : "Log in").frame(maxWidth: .infinity)
        }
        .buttonStyle(CapsuleAuthButtonStyle(filled: true))
        .opacity(canSubmit ? 1 : 0.45)
        .disabled(!canSubmit)

        Button("Other ways to continue") {
            focus = nil
            authManager.authError = nil
            emailMode = false
        }
        .font(.system(size: 14)).foregroundColor(.ncPrimary.opacity(0.7))
        .frame(minHeight: 44)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(emailMode && !isSignUp ? "New here?" : "Already have an account?")
                .foregroundColor(.ncPrimary.opacity(0.7))
            Button(emailMode && !isSignUp ? "Sign up" : "Log in") {
                openEmail(signUp: emailMode && !isSignUp)
            }
            .foregroundColor(.ncPrimary)
            .underline()
            .frame(minHeight: 44)
        }
        .font(.system(size: 15))
    }

    private func openEmail(signUp: Bool) {
        authManager.authError = nil
        isSignUp = signUp
        emailMode = true
        focus = .email
    }

    private func authField(_ placeholder: String, text: Binding<String>, field: Field, secure: Bool = false) -> some View {
        Group {
            if secure {
                SecureField("", text: text).textContentType(isSignUp ? .newPassword : .password)
                    .submitLabel(.go)
            } else {
                TextField("", text: text).textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.next)
            }
        }
        .focused($focus, equals: field)
        .font(.system(size: 16)).foregroundColor(.ncPrimary)
        .placeholder(when: text.wrappedValue.isEmpty) {
            Text(placeholder).font(.system(size: 16)).foregroundColor(.ncPrimary.opacity(0.55))
        }
        .padding(.horizontal, 24)
        .frame(height: 50)
        .background(Capsule().fill(Color.black.opacity(0.25)))
        .overlay(Capsule().strokeBorder(Color.ncPrimary.opacity(0.85), lineWidth: 1))
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        Task {
            if isSignUp {
                await authManager.signUp(email: email, password: password)
            } else {
                await authManager.signIn(email: email, password: password)
            }
            if authManager.isAuthenticated {
                password = ""
                ToastCenter.shared.show(isSignUp ? "Welcome" : "Welcome back")
            }
        }
    }
}

// MARK: - Capsule auth buttons

/// Icon in a fixed slot, then the title; the pair is centred in the capsule.
private struct AuthButtonLabel<Icon: View>: View {
    let title: String
    @ViewBuilder var icon: Icon
    var body: some View {
        HStack(spacing: 18) {
            icon.frame(width: 22, height: 22)
            Text(title)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Full-width 50 pt capsule. Filled: Paper with Ink text. Outline: 1 pt Paper border over the photo.
struct CapsuleAuthButtonStyle: ButtonStyle {
    var filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .regular))
            .foregroundColor(filled ? .ncOnPrimary : .ncPrimary)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(filled ? Color.ncPrimary : Color.black.opacity(0.18)))
            .overlay(Capsule().strokeBorder(filled ? Color.clear : Color.ncPrimary.opacity(0.85), lineWidth: 1))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

/// Google "G" drawn as a single-colour ring with a gap at the upper right and the crossbar.
struct GoogleGMark: View {
    var color: Color = .ncPrimary
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let lw = s * 0.2
            ZStack {
                Circle()
                    .trim(from: 0.0, to: 0.88)
                    .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .butt))
                    .padding(lw / 2)
                Rectangle()
                    .fill(color)
                    .frame(width: s * 0.48, height: lw)
                    .offset(x: s * 0.24 - lw / 4)
            }
            .frame(width: s, height: s)
        }
        .accessibilityHidden(true)
    }
}

struct OnboardingFeatureRow: View {
    let icon: String      // index label, e.g. "01"
    let tint: Color
    let tintBg: Color
    let label: String
    let sub: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(icon).font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundColor(.ncSecondary)
                    .frame(width: 22, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(.serif(19)).foregroundColor(.ncPrimary)
                    Text(sub).font(.system(size: 13)).foregroundColor(.ncSecondary)
                }
                Spacer()
            }
            .padding(.vertical, 14)
            Hairline(opacity: 0.12)
        }
    }
}
