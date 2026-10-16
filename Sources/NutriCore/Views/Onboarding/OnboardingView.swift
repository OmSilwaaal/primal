import SwiftUI

struct OnboardingView: View {
    @StateObject private var authManager = AuthManager.shared

    var body: some View {
        ZStack {
            AppBackdrop(intensity: 1)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Primal").font(.serif(17)).foregroundColor(.ncPrimary)
                    Spacer()
                    Text("Raw  ·  Sun  ·  Index").serifCaps(10).foregroundColor(.ncPrimary.opacity(0.8))
                }
                .padding(.top, 12)

                Spacer()

                VStack(alignment: .leading, spacing: 18) {
                    Text("Ancestral nutrition, measured").serifCaps(11).foregroundColor(.ncPrimary.opacity(0.85))
                    Wordmark(size: 86)
                }

                Spacer()

                VStack(spacing: 0) {
                    OnboardingFeatureRow(icon: "01", tint: .ncPrimary, tintBg: .clear,
                                         label: "Raw-food safety", sub: "Risk score, freezer log, batches and recalls")
                    OnboardingFeatureRow(icon: "02", tint: .ncPrimary, tintBg: .clear,
                                         label: "Diet rater", sub: "Where you sit from omnivore to raw carnivore")
                    OnboardingFeatureRow(icon: "03", tint: .ncPrimary, tintBg: .clear,
                                         label: "Sunlight", sub: "Time outside and today's vitamin D window")
                }
                .overlay(alignment: .top) { Hairline() }

                VStack(spacing: 16) {
                    HStack(spacing: 10) {
                        CompactAuthButton(title: "Apple", icon: .system("applelogo"),
                                          fg: .ncOnPrimary, bg: .ncPrimary, border: .clear) {
                            Task { await authManager.signInWithApple() }
                        }
                        CompactAuthButton(title: "Google", icon: .google,
                                          fg: .ncPrimary, bg: .clear,
                                          border: Color.ncPrimary.opacity(0.45)) {
                            Task { await authManager.signInWithGoogle() }
                        }
                    }
                    .disabled(authManager.isLoading)
                    .opacity(authManager.isLoading ? 0.6 : 1)

                    if let error = authManager.authError {
                        Text(error).font(.system(size: 13)).foregroundColor(.ncError).multilineTextAlignment(.center)
                    }

                    Text("By continuing you agree to the Terms of Service and Privacy Policy.")
                        .font(.serif(12)).italic().foregroundColor(.ncSecondary)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                }
                .padding(.top, 28).padding(.bottom, 20)
            }
            .padding(.horizontal, Space.margin)
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
