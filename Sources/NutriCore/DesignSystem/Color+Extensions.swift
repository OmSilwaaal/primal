import SwiftUI

// MARK: - Primal Design System (black theme)
// ─────────────────────────────────────────────────────────────────────────────
// Near-black canvas, stacked surfaces separated by hairline borders rather than
// shadows, white as the primary action colour, one soft indigo accent.
// ─────────────────────────────────────────────────────────────────────────────

extension Color {
    // Backgrounds (darkest -> lightest)
    static let ncBg                  = Color(hex: "#060B07")
    static let ncSurface             = Color(hex: "#0A110C")
    static let ncSurfaceContLowest   = Color(hex: "#0D150F") // cards
    static let ncSurfaceContLow      = Color(hex: "#111A13")
    static let ncSurfaceCont         = Color(hex: "#151F17")
    static let ncSurfaceContHigh     = Color(hex: "#1B271E")
    static let ncSurfaceContHighest  = Color(hex: "#263528")
    static let ncSurfaceBright       = Color(hex: "#223024")

    // Text
    static let ncPrimary             = Color(hex: "#EDEFE4")
    static let ncOnPrimary           = Color(hex: "#07100A") // text/icons on a ncPrimary fill
    static let ncOnSurface           = Color(hex: "#EDEFE4")
    static let ncSecondary           = Color(hex: "#8FA092")

    // Lines
    static let ncOutline             = Color(hex: "#4C5E50")
    static let ncOutlineVariant      = Color(hex: "#1F2B22")
    static let ncBorder              = Color(hex: "#EDEFE4").opacity(0.12)
    static let ncBorderSub           = Color.white.opacity(0.05)

    // Accents (tuned for dark backgrounds). *Light variants are translucent tints.
    static let ncIndigo              = Color(hex: "#A8C686")
    static let ncIndigoLight         = Color(hex: "#A8C686").opacity(0.16)
    static let ncGreen               = Color(hex: "#5FB978")
    static let ncGreenLight          = Color(hex: "#5FB978").opacity(0.14)
    static let ncOrange              = Color(hex: "#E0A458")
    static let ncOrangeLight         = Color(hex: "#E0A458").opacity(0.16)
    static let ncSky                 = Color(hex: "#7FB5B0")
    static let ncSkyLight            = Color(hex: "#7FB5B0").opacity(0.14)
    static let ncError               = Color(hex: "#D9694F")

    // Legacy alias
    static let ncSurface2            = Color(hex: "#151F17")
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
            .background(Color.ncSurfaceContLowest, in: RoundedRectangle(cornerRadius: r, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .stroke(Color.ncPrimary.opacity(0.16), lineWidth: 1)
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

/// Filled call-to-action: bone block with dark caps text and an offset outline echo that closes on press.
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
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.ncIndigo.opacity(0.7), lineWidth: 1)
                    .offset(x: configuration.isPressed ? 0 : 4, y: configuration.isPressed ? 0 : 4)
            )
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
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
