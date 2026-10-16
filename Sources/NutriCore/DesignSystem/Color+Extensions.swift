import SwiftUI

// MARK: - Primal Design System (black theme)
// ─────────────────────────────────────────────────────────────────────────────
// Near-black canvas, stacked surfaces separated by hairline borders rather than
// shadows, white as the primary action colour, one soft indigo accent.
// ─────────────────────────────────────────────────────────────────────────────

extension Color {
    // Backgrounds (darkest -> lightest)
    static let ncBg                  = Color(hex: "#050505")
    static let ncSurface             = Color(hex: "#0B0B0C")
    static let ncSurfaceContLowest   = Color(hex: "#101012") // cards
    static let ncSurfaceContLow      = Color(hex: "#141416")
    static let ncSurfaceCont         = Color(hex: "#17171A")
    static let ncSurfaceContHigh     = Color(hex: "#202024")
    static let ncSurfaceContHighest  = Color(hex: "#2A2A2F")
    static let ncSurfaceBright       = Color(hex: "#26262B")

    // Text
    static let ncPrimary             = Color(hex: "#FAFAFA")
    static let ncOnPrimary           = Color(hex: "#09090B") // text/icons on a ncPrimary fill
    static let ncOnSurface           = Color(hex: "#FAFAFA")
    static let ncSecondary           = Color(hex: "#8E8E96")

    // Lines
    static let ncOutline             = Color(hex: "#52525B")
    static let ncOutlineVariant      = Color(hex: "#27272A")
    static let ncBorder              = Color(hex: "#FAFAFA").opacity(0.12)
    static let ncBorderSub           = Color.white.opacity(0.05)

    // Accents (tuned for dark backgrounds). *Light variants are translucent tints.
    static let ncIndigo              = Color(hex: "#C9D6C0")
    static let ncIndigoLight         = Color(hex: "#C9D6C0").opacity(0.16)
    static let ncGreen               = Color(hex: "#4FC48A")
    static let ncGreenLight          = Color(hex: "#4FC48A").opacity(0.14)
    static let ncOrange              = Color(hex: "#F0A35E")
    static let ncOrangeLight         = Color(hex: "#F0A35E").opacity(0.16)
    static let ncSky                 = Color(hex: "#6FB7D6")
    static let ncSkyLight            = Color(hex: "#6FB7D6").opacity(0.14)
    static let ncError               = Color(hex: "#F07167")

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
    func body(content: Content) -> some View {
        let r = min(cornerRadius, 3)
        content
            .background(Color.ncSurfaceContLowest.opacity(0.80), in: RoundedRectangle(cornerRadius: r, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .stroke(Color.ncPrimary.opacity(0.14), lineWidth: 1)
            )
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

/// Filled call-to-action: square bone block with dark spaced-caps text.
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 52
    var radius: CGFloat = 2
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .heavy)).tracking(1.4).textCase(.uppercase)
            .foregroundColor(.ncOnPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color.ncPrimary, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tap() }
            }
    }
}

/// Quiet secondary action: raised surface with a hairline border.
struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 44
    var radius: CGFloat = 2
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold)).tracking(1.1).textCase(.uppercase)
            .foregroundColor(.ncPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color.ncSurfaceContHigh, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.ncPrimary.opacity(0.28), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? 0.05 : 0)
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
