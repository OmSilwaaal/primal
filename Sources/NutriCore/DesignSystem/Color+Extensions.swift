import SwiftUI

// MARK: - Primal Design System
// ─────────────────────────────────────────────────────────────────────────────
// Monochrome: Ink canvas, Paper type and fills, Mute for labels and units.
// One status pair — Moss (goal met, location) and Ember (low intake, remove).
// Anything that floats uses glass (see Glass.swift).
// ─────────────────────────────────────────────────────────────────────────────

extension Color {
    // Backgrounds (darkest -> lightest)
    static let ncBg                  = Color(hex: "#0A0B0A") // Ink
    static let ncSurface             = Color(hex: "#141614") // solid fallback for glass
    static let ncSurfaceContLowest   = Color(hex: "#101012") // cards
    static let ncSurfaceContLow      = Color(hex: "#141416")
    static let ncSurfaceCont         = Color(hex: "#17171A")
    static let ncSurfaceContHigh     = Color(hex: "#202024")
    static let ncSurfaceContHighest  = Color(hex: "#2A2A2F")
    static let ncSurfaceBright       = Color(hex: "#26262B")

    // Text
    static let ncPrimary             = Color(hex: "#F2F1EC") // Paper, 18.4:1 on Ink
    static let ncOnPrimary           = Color(hex: "#0A0B0A") // text/icons on a ncPrimary fill
    static let ncOnSurface           = Color(hex: "#F2F1EC")
    static let ncSecondary           = Color(hex: "#9DA19B") // Mute, 7.6:1 on Ink
    static let ncSoft                = Color(hex: "#C9CBC5") // secondary copy on glass

    // Lines
    static let ncOutline             = Color(hex: "#52525B")
    static let ncOutlineVariant      = Color(hex: "#27272A")
    static let ncBorder              = Color(hex: "#FAFAFA").opacity(0.12)
    static let ncBorderSub           = Color.white.opacity(0.05)

    // Accents (tuned for dark backgrounds). *Light variants are translucent tints.
    static let ncIndigo              = Color(hex: "#E6E3D8")
    static let ncIndigoLight         = Color(hex: "#E6E3D8").opacity(0.16)
    static let ncGreen               = Color(hex: "#E6E3D8")
    static let ncGreenLight          = Color(hex: "#E6E3D8").opacity(0.14)
    static let ncOrange              = Color(hex: "#D2B98A")
    static let ncOrangeLight         = Color(hex: "#D2B98A").opacity(0.16)
    static let ncSky                 = Color(hex: "#BDBAB0")
    static let ncSkyLight            = Color(hex: "#BDBAB0").opacity(0.14)
    static let ncError               = Color.ncEmber

    // Status pair (oklch .80 .10 135 / oklch .72 .15 35)
    static let ncMoss                = Color(hex: "#A2CD8B")
    static let ncEmber               = Color(hex: "#F37E61")

    // Legacy alias
    static let ncSurface2            = Color(hex: "#17171A")
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

// MARK: - Card
struct CardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    /// Cards no longer draw a box; content sits directly on the background.
    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func glassCard(radius: CGFloat = 16) -> some View {
        modifier(CardModifier(cornerRadius: radius))
    }
}

// MARK: - Haptics
enum Haptics {
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: "isHapticsEnabled") as? Bool ?? true }

    static func tap() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Button styles
/// Press feedback shared by every button: a small scale-down with a quick spring back and a light tap.
/// No opacity flicker, so text stays crisp while pressed.
struct SmoothButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.72), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tap() }
            }
    }
}

extension View {
    func smoothButton() -> some View { self.buttonStyle(SmoothButtonStyle()) }
}

/// Filled call-to-action: square Paper block, bold spaced caps in Ink. 56 pt by default.
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 56
    var radius: CGFloat = 0
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold)).tracking(2.2).textCase(.uppercase)
            .foregroundColor(.ncOnPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color.ncPrimary, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tap() }
            }
    }
}

/// Quiet secondary action: square clear glass with mono caps.
struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 48
    var radius: CGFloat = 0
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mono(12, .semibold)).tracking(1.4).textCase(.uppercase)
            .foregroundColor(.ncPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .glass(.clear, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.72), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tap() }
            }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primal: PrimaryButtonStyle { PrimaryButtonStyle() }
}
extension ButtonStyle where Self == SecondaryButtonStyle {
    static var primalSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
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
