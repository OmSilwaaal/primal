import SwiftUI

struct OnboardingView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @FocusState private var focus: Field?

    private enum Field { case email, password }
    private var canSubmit: Bool { !email.isEmpty && !password.isEmpty && !authManager.isLoading }

    var body: some View {
        ZStack {
            AppBackdrop(intensity: 1)

            VStack(spacing: 0) {
                Spacer(minLength: 80)
                VStack(spacing: 14) {
                    Text("PRIMAL").font(.display(64)).tracking(20.5)
                        .padding(.leading, 20.5) // optically recentre the trailing tracking
                        .foregroundColor(.ncPrimary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("Nutrition, tracked plainly").font(.mono(11)).tracking(2.2).textCase(.uppercase)
                        .foregroundColor(.ncSecondary)
                }
                Spacer(minLength: 40)

                VStack(spacing: 12) {
                    authField("Email", text: $email, field: .email)
                    authField("Password", text: $password, field: .password, secure: true)

                    Button(isSignUp ? "Sign up" : "Log in", action: submit)
                        .buttonStyle(.primal)
                        .opacity(canSubmit ? 1 : 0.4)
                        .disabled(!canSubmit)
                        .padding(.top, 8)

                    Button(isSignUp ? "Already have an account? Log in" : "Don't have an account? Sign up") {
                        withAnimation(.easeOut(duration: 0.2)) { isSignUp.toggle() }
                    }
                    .font(.system(size: 13)).foregroundColor(.ncSecondary)
                    .frame(minHeight: 44)

                    if let error = authManager.authError {
                        Text(error).font(.system(size: 13)).foregroundColor(.ncEmber).multilineTextAlignment(.center)
                    }

                    HStack(spacing: 12) {
                        Hairline(opacity: 0.2)
                        Text("Or").monoLabel(10)
                        Hairline(opacity: 0.2)
                    }
                    .padding(.vertical, 6)

                    HStack(spacing: 10) {
                        CompactAuthButton(title: "Apple", icon: .system("applelogo"),
                                          fg: .ncOnPrimary, bg: .ncPrimary, border: .clear) {
                            Task { await authManager.signInWithApple() }
                        }
                        CompactAuthButton(title: "Google", icon: .google,
                                          fg: .ncPrimary, bg: .clear,
                                          border: Color.white.opacity(0.2)) {
                            Task { await authManager.signInWithGoogle() }
                        }
                    }
                    .disabled(authManager.isLoading)
                    .opacity(authManager.isLoading ? 0.6 : 1)

                    Text("By continuing you agree to the Terms of Service and Privacy Policy.")
                        .font(.system(size: 12)).foregroundColor(.ncSecondary)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 28)
        }
        .onSubmit {
            if focus == .email { focus = .password } else { submit() }
        }
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
            Text(placeholder).font(.system(size: 16)).foregroundColor(.ncSecondary)
        }
        .padding(.horizontal, 22)
        .frame(height: 56)
        .background(Rectangle().fill(.ultraThinMaterial).overlay(Color.white.opacity(0.08)))
        .overlay(Rectangle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
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
                ToastCenter.shared.show("Welcome back")
            }
        }
    }
}

// MARK: - Compact provider button
struct CompactAuthButton: View {
    enum Icon { case system(String), google }

    let title: String
    let icon: Icon
    let fg: Color
    let bg: Color
    let border: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                switch icon {
                case .system(let name):
                    Image(systemName: name).font(.system(size: 15, weight: .semibold))
                case .google:
                    GoogleGMark().frame(width: 16, height: 16)
                }
                Text(title).font(.system(size: 13, weight: .heavy)).tracking(1.2).textCase(.uppercase)
            }
            .foregroundColor(fg)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(bg)
            .overlay(Rectangle().stroke(border, lineWidth: 1))
        }
        .smoothButton()
    }
}

/// Multicolor Google "G" drawn from four arcs plus the crossbar.
struct GoogleGMark: View {
    private let blue = Color(hex: "#4285F4")
    private let red = Color(hex: "#EA4335")
    private let yellow = Color(hex: "#FBBC05")
    private let green = Color(hex: "#34A853")

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let lw = s * 0.22
            ZStack {
                arc(from: 0.50, to: 0.75, color: yellow, lw: lw)
                arc(from: 0.25, to: 0.50, color: green, lw: lw)
                arc(from: 0.75, to: 0.93, color: red, lw: lw)
                arc(from: 0.00, to: 0.25, color: blue, lw: lw)
                Rectangle()
                    .fill(blue)
                    .frame(width: s * 0.52, height: lw)
                    .offset(x: s * 0.24)
            }
            .frame(width: s, height: s)
            .padding(lw / 2)
        }
    }

    private func arc(from: CGFloat, to: CGFloat, color: Color, lw: CGFloat) -> some View {
        Circle()
            .trim(from: from, to: to)
            .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .butt))
            .rotationEffect(.degrees(0))
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
