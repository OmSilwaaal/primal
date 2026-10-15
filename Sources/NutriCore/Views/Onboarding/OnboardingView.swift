import SwiftUI

struct OnboardingView: View {
    @StateObject private var authManager = AuthManager.shared

    var body: some View {
        ZStack {
            Color.ncBg.ignoresSafeArea()

            // Soft indigo glow behind the brand mark
            Circle()
                .fill(Color.ncIndigo.opacity(0.14))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(y: -230)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                // ── Brand ────────────────────────────────────────────────────
                VStack(spacing: 18) {
                    Image(systemName: "hexagon")
                        .font(.system(size: 34, weight: .light))
                        .foregroundColor(.ncIndigo)
                        .frame(width: 76, height: 76)
                        .glassCard(radius: 22)

                    VStack(spacing: 8) {
                        Text("Primal")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundColor(.ncPrimary)
                        Text("Ancestral nutrition, measured.")
                            .font(.system(size: 15))
                            .foregroundColor(.ncSecondary)
                    }
                }

                Spacer(minLength: 24)

                // ── Features ─────────────────────────────────────────────────
                VStack(spacing: 0) {
                    OnboardingFeatureRow(icon: "barcode.viewfinder", tint: .ncIndigo, tintBg: .ncIndigoLight,
                                         label: "Optical food scanner", sub: "AI-powered nutrient tracking")
                    Divider().padding(.leading, 62)
                    OnboardingFeatureRow(icon: "flame.fill", tint: .ncOrange, tintBg: .ncOrangeLight,
                                         label: "Fasting tracker", sub: "20:4 protocol, live countdown")
                    Divider().padding(.leading, 62)
                    OnboardingFeatureRow(icon: "drop.fill", tint: .ncGreen, tintBg: .ncGreenLight,
                                         label: "Electrolyte monitor", sub: "Water & salt balance")
                }
                .glassCard(radius: 18)
                .padding(.horizontal, 20)

                Spacer(minLength: 24)

                // ── Auth ─────────────────────────────────────────────────────
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        CompactAuthButton(title: "Apple", icon: .system("applelogo"),
                                          fg: .white, bg: .black, border: .clear) {
                            Task { await authManager.signInWithApple() }
                        }
                        CompactAuthButton(title: "Google", icon: .google,
                                          fg: .ncPrimary, bg: .ncSurfaceContLowest,
                                          border: Color.black.opacity(0.1)) {
                            Task { await authManager.signInWithGoogle() }
                        }
                    }
                    .disabled(authManager.isLoading)
                    .opacity(authManager.isLoading ? 0.6 : 1)

                    if let error = authManager.authError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.ncError)
                            .multilineTextAlignment(.center)
                    }

                    Text("By continuing, you agree to our **Terms of Service** and **Privacy Policy**")
                        .font(.system(size: 11))
                        .foregroundColor(.ncSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
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
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(fg)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(bg)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(border, lineWidth: 1))
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
