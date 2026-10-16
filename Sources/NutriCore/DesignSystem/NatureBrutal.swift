import SwiftUI

// MARK: - Nature × brutalist toolkit
// Black canvas, out-of-focus foliage glowing through a heavy gaussian blur, bone-white wide type,
// square edges and hairlines.

extension Font {
    /// Heavy, wide grotesque used for the wordmark and titles.
    static func brutal(_ size: CGFloat, weight: Font.Weight = .black) -> Font {
        .system(size: size, weight: weight).width(.expanded)
    }
    static let ncTitle = Font.brutal(15, weight: .heavy)
}

extension View {
    /// Small spaced capitals used for labels and navigation.
    func spacedCaps(_ size: CGFloat = 11, tracking: CGFloat = 1.6) -> some View {
        self.font(.system(size: size, weight: .medium)).tracking(tracking).textCase(.uppercase)
    }
}

/// Black background with soft, heavily blurred foliage-coloured light — like out-of-focus leaves in the dark.
struct AppBackdrop: View {
    var intensity: Double = 1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Color.ncBg
                Group {
                    blob("#245A33", 0.85, w * 0.95, h * 0.30, -26, x: -w * 0.30, y: -h * 0.22)
                    blob("#38804B", 0.55, w * 0.50, h * 0.22, 32, x: w * 0.34, y: -h * 0.06)
                    blob("#12402A", 0.85, w * 0.90, h * 0.26, -12, x: w * 0.10, y: h * 0.26)
                    blob("#5E9E6C", 0.30, w * 0.30, h * 0.12, 55, x: -w * 0.18, y: h * 0.10)
                    blob("#C5DDBE", 0.16, w * 0.24, h * 0.07, -40, x: w * 0.30, y: -h * 0.26)
                    blob("#1A4025", 0.55, w * 0.80, h * 0.20, 18, x: -w * 0.20, y: h * 0.42)
                }
                .opacity(intensity)
                // keep the lower half calm so content stays legible
                LinearGradient(colors: [.clear, Color.ncBg.opacity(0.6), Color.ncBg.opacity(0.94)], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .drawingGroup()
        .ignoresSafeArea()
    }

    private func blob(_ hex: String, _ opacity: Double, _ w: CGFloat, _ h: CGFloat, _ angle: Double, x: CGFloat, y: CGFloat) -> some View {
        Ellipse().fill(Color(hex: hex).opacity(opacity))
            .frame(width: w, height: h)
            .rotationEffect(.degrees(angle))
            .offset(x: x, y: y)
            .blur(radius: 55)
    }
}

/// The name in a heavy wide face. It is laid out at a fixed size and allowed to run past the right edge,
/// so the last letter is cropped by the screen.
struct Wordmark: View {
    var text = "PRIMAL"
    var size: CGFloat = 56
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: size * 0.92)
            .overlay(alignment: .leading) {
                Text(text).font(.brutal(size)).foregroundColor(.ncPrimary)
                    .lineLimit(1).fixedSize()
                    .offset(x: -size * 0.05)
            }
            .accessibilityElement().accessibilityLabel(text)
    }
}

/// Hairline rule with spaced-caps label.
struct RuleLabel: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Text(text).spacedCaps(10, tracking: 2).foregroundColor(.ncSecondary)
            Rectangle().fill(Color.ncPrimary.opacity(0.14)).frame(height: 1)
        }
    }
}

/// Page title block: wide wordmark, spaced caption and a hairline underneath.
struct PageHeader: View {
    let title: String
    var caption: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption).spacedCaps(10, tracking: 2.6).foregroundColor(.ncSecondary)
                .opacity(caption.isEmpty ? 0 : 1).frame(height: caption.isEmpty ? 0 : nil)
            Wordmark(text: title.uppercased(), size: 62)
            Rectangle().fill(Color.ncPrimary.opacity(0.18)).frame(height: 1).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
