import SwiftUI

extension Color {
    // Monochrome Minimalist Palette (Dynamic for Light/Dark themes)
    static let ncBg = Color(UIColor { $0.userInterfaceStyle == .dark ? .black : .white })
    static let ncSurface = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.08, alpha: 1) : UIColor(white: 0.96, alpha: 1) })
    static let ncSurface2 = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.15, alpha: 1) : UIColor(white: 0.9, alpha: 1) })
    
    static let ncPrimary = Color(UIColor { $0.userInterfaceStyle == .dark ? .white : .black })
    static let ncSecondary = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.6, alpha: 1) : UIColor(white: 0.4, alpha: 1) })
}

// MARK: - Smooth Micro-animations
struct SmoothButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: configuration.isPressed)
    }
}

extension View {
    func smoothButton() -> some View {
        self.buttonStyle(SmoothButtonStyle())
    }
}
