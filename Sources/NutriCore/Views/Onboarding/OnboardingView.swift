import SwiftUI

struct OnboardingView: View {
    @StateObject private var authManager = AuthManager.shared

    var body: some View {
        ZStack {
            Color.ncBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Leaf hero with the shifted wordmark ──────────────────────
                ZStack(alignment: .bottomLeading) {
                    LeafBackdrop(seed: 5)
                    LinearGradient(colors: [.clear, Color.ncBg.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 22) {
                            Text("Raw").spacedCaps(10, tracking: 2.4)
                            Text("Sun").spacedCaps(10, tracking: 2.4)
                            Text("Index").spacedCaps(10, tracking: 2.4)
                            Spacer()
                        }
                        .foregroundColor(.ncPrimary.opacity(0.9))
                        Spacer()
                        Wordmark(size: 74, shift: CGSize(width: 10, height: 7))
                        Text("Eat what grows wild").spacedCaps(11, tracking: 4).foregroundColor(.ncPrimary.opacity(0.85))
                    }
                    .padding(.horizontal, 20).padding(.top, 64).padding(.bottom, 24)
                }
                .frame(maxHeight: .infinity)
                .ignoresSafeArea(edges: .top)

                // ── Features ─────────────────────────────────────────────────
                VStack(spacing: 0) {
                    OnboardingFeatureRow(icon: "flame", tint: .ncOrange, tintBg: .clear,
                                         label: "Raw-food safety score", sub: "Freezer log, batches and recalls")
                    Rectangle().fill(Color.ncPrimary.opacity(0.14)).frame(height: 1)
                    OnboardingFeatureRow(icon: "leaf", tint: .ncIndigo, tintBg: .clear,
                                         label: "Diet rater", sub: "Where you sit from omnivore to raw")
                    Rectangle().fill(Color.ncPrimary.opacity(0.14)).frame(height: 1)
                    OnboardingFeatureRow(icon: "sun.max", tint: .ncGreen, tintBg: .clear,
                                         label: "Sunlight tracker", sub: "Time outside and the vitamin D window")
                }
                .glassCard(radius: 3)
                .padding(.horizontal, 20)
                .padding(.top, 20)

                // ── Auth ─────────────────────────────────────────────────────
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        CompactAuthButton(title: "Apple", icon: .system("applelogo"),
                                          fg: .ncOnPrimary, bg: .ncPrimary, border: .clear) {
                            Task { await authManager.signInWithApple() }
                        }
                        CompactAuthButton(title: "Google", icon: .google,
                                          fg: .ncPrimary, bg: .clear,
                                          border: Color.ncPrimary.opacity(0.5)) {
                            Task { await authManager.signInWithGoogle() }
                        }
                    }
                    .disabled(authManager.isLoading)
                    .opacity(authManager.isLoading ? 0.6 : 1)

                    if let error = authManager.authError {
                        Text(error).font(.system(size: 12)).foregroundColor(.ncError).multilineTextAlignment(.center)
                    }

                    Text("By continuing, you agree to our **Terms of Service** and **Privacy Policy**")
                        .font(.system(size: 11)).foregroundColor(.ncSecondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 28)
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
                Text(title).font(.system(size: 12, weight: .heavy)).tracking(1.2).textCase(.uppercase)
            }
            .foregroundColor(fg)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(border, lineWidth: 1))
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
    let icon: String
    let tint: Color
    let tintBg: Color
    let label: String
    let sub: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
                .background(tintBg)
                .cornerRadius(10)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ncPrimary)
                Text(sub)
                    .font(.ncBodySm)
                    .foregroundColor(.ncSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
