import SwiftUI

// MARK: - Primal Design System (synced from Google Stitch "Autonomous Metabolic Intelligence" theme)
// Source: projects/12049417744954362917
// ─────────────────────────────────────────────────────────────────────────────
// primary:                  #18181b
// secondary:                #6366f1
// background:               #f4f4f7
// surface:                  #f4f4f7
// on-surface:               #18181b
// on-surface-variant:       #71717a
// outline:                  #a1a1aa
// outline-variant:          #e4e4e7
// surface-container-lowest: #ffffff
// surface-container-low:    #fafaf9
// surface-container-high:   #e4e4e7
// ─────────────────────────────────────────────────────────────────────────────

extension Color {
    // Backgrounds
    static let ncBg                  = Color(hex: "#f4f4f7")
    static let ncSurface             = Color(hex: "#f4f4f7")
    static let ncSurfaceContLowest   = Color(hex: "#ffffff")
    static let ncSurfaceContLow      = Color(hex: "#fafaf9")
    static let ncSurfaceCont         = Color(hex: "#f4f4f6")
    static let ncSurfaceContHigh     = Color(hex: "#e4e4e7")
    static let ncSurfaceContHighest  = Color(hex: "#d4d4d8")
    static let ncSurfaceBright       = Color(hex: "#ffffff")

    // Text
    static let ncPrimary             = Color(hex: "#18181b") // zinc-900
    static let ncOnPrimary           = Color(hex: "#ffffff")
    static let ncOnSurface           = Color(hex: "#18181b")
    static let ncSecondary           = Color(hex: "#71717a") // on-surface-variant zinc-500

    // Accents
    static let ncOutline             = Color(hex: "#a1a1aa")
    static let ncOutlineVariant      = Color(hex: "#e4e4e7")
    static let ncError               = Color(hex: "#ef4444")

    // Brand accents for Light AI Theme
    static let ncIndigo              = Color(hex: "#6366f1")
    static let ncIndigoLight         = Color(hex: "#ede9fe")
    static let ncGreen               = Color(hex: "#059669")
    static let ncGreenLight          = Color(hex: "#ecfdf5")
    static let ncOrange              = Color(hex: "#f97316")
    static let ncOrangeLight         = Color(hex: "#ffedd5")

    // Legacy aliases (used by existing views)
    static let ncSurface2            = Color(hex: "#ffffff")
    static let ncBorder              = Color.black.opacity(0.05)
    static let ncBorderSub           = Color.black.opacity(0.03)
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue:  Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - Light Theme Glass Card (White surface + faint border + soft shadow)
struct LightGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .background(Color.ncSurfaceContLowest)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

extension View {
    func glassCard(radius: CGFloat = 16) -> some View {
        modifier(LightGlassCard(cornerRadius: radius))
    }
}

// MARK: - Smooth Button
struct SmoothButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65, blendDuration: 0), value: configuration.isPressed)
    }
}

extension View {
    func smoothButton() -> some View { self.buttonStyle(SmoothButtonStyle()) }
}

// MARK: - Typography helpers
extension Font {
    // Plus Jakarta Sans for headlines, Inter for body/labels (simulated with system fonts)
    static let ncLabelMonoBold    = Font.system(size: 11, weight: .bold, design: .default)
    static let ncLabelMonoReg     = Font.system(size: 11, weight: .medium, design: .default)
    static let ncMetricMobile     = Font.system(size: 32, weight: .bold, design: .default)
    static let ncHeadlineMd       = Font.system(size: 18, weight: .bold)
    static let ncBodySm           = Font.system(size: 13, weight: .regular)
    static let ncLabelTag         = Font.system(size: 11, weight: .semibold)
}
