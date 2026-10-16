import SwiftUI

// MARK: - Nature × brutalist toolkit
// Deep forest blacks, bone-white type, hard edges and offset echoes. Leaf imagery is drawn in code.

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

/// Procedural macro-leaf: gradient, a dark overlapping lobe and a network of veins.
struct LeafBackdrop: View {
    var seed: UInt64 = 7

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(hex: "#6FA676"), Color(hex: "#3A7646"), Color(hex: "#0B2F17"), Color(hex: "#03130A")],
                               startPoint: .topLeading, endPoint: .bottomTrailing)

                // soft cast shadows, like the dark blades in the reference
                Ellipse().fill(Color.black.opacity(0.28)).frame(width: geo.size.width * 0.25, height: geo.size.height * 1.4)
                    .rotationEffect(.degrees(-28)).offset(x: -geo.size.width * 0.12, y: -geo.size.height * 0.08).blur(radius: 14)

                Canvas { ctx, size in drawVeins(ctx, size) }

                // dark lobe with a pale rim
                Ellipse().fill(Color(hex: "#02140A"))
                    .frame(width: geo.size.width * 0.85, height: geo.size.height * 1.6)
                    .offset(x: geo.size.width * 0.62, y: geo.size.height * 0.1)
                    .overlay(
                        Ellipse().stroke(Color(hex: "#CFE3D6").opacity(0.55), lineWidth: 2)
                            .frame(width: geo.size.width * 0.85, height: geo.size.height * 1.6)
                            .offset(x: geo.size.width * 0.62, y: geo.size.height * 0.1).blur(radius: 1.5)
                    )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    private func drawVeins(_ ctx: GraphicsContext, _ size: CGSize) {
        var rng = SeededRNG(seed: seed)
        let w = size.width, h = size.height
        let p0 = CGPoint(x: -0.1 * w, y: 1.05 * h), p1 = CGPoint(x: 0.35 * w, y: 0.75 * h), p2 = CGPoint(x: 0.9 * w, y: 0.05 * h)
        func point(_ t: CGFloat) -> CGPoint {
            let a = 1 - t
            return CGPoint(x: a * a * p0.x + 2 * a * t * p1.x + t * t * p2.x, y: a * a * p0.y + 2 * a * t * p1.y + t * t * p2.y)
        }
        func tangent(_ t: CGFloat) -> CGPoint {
            let a = 1 - t
            let dx = 2 * a * (p1.x - p0.x) + 2 * t * (p2.x - p1.x), dy = 2 * a * (p1.y - p0.y) + 2 * t * (p2.y - p1.y)
            let l = max(hypot(dx, dy), 0.001); return CGPoint(x: dx / l, y: dy / l)
        }
        let light = Color(hex: "#DCEBDD")

        var mid = Path(); mid.move(to: p0); mid.addQuadCurve(to: p2, control: p1)
        ctx.stroke(mid, with: .color(light.opacity(0.28)), lineWidth: 1.8)

        var t: CGFloat = 0.04
        while t < 0.97 {
            let p = point(t), tan = tangent(t), nrm = CGPoint(x: -tan.y, y: tan.x)
            for side in [CGFloat(-1), 1] {
                let len = w * 0.55 * pow(sin(.pi * t), 0.6) * CGFloat(0.55 + 0.45 * rng.next())
                let ctrl = CGPoint(x: p.x + tan.x * len * 0.45 + nrm.x * side * len * 0.35, y: p.y + tan.y * len * 0.45 + nrm.y * side * len * 0.35)
                let end = CGPoint(x: p.x + tan.x * len * 0.95 + nrm.x * side * len * 0.85, y: p.y + tan.y * len * 0.95 + nrm.y * side * len * 0.85)
                var v = Path(); v.move(to: p); v.addQuadCurve(to: end, control: ctrl)
                ctx.stroke(v, with: .color(light.opacity(0.16)), lineWidth: 0.9)

                var u: CGFloat = 0.12
                while u < 0.95 {
                    let a = 1 - u
                    let q = CGPoint(x: a * a * p.x + 2 * a * u * ctrl.x + u * u * end.x, y: a * a * p.y + 2 * a * u * ctrl.y + u * u * end.y)
                    let sl = len * 0.22 * CGFloat(0.5 + 0.5 * rng.next())
                    for s2 in [CGFloat(-1), 1] {
                        let e = CGPoint(x: q.x + (tan.x * 0.6 + nrm.x * side * 0.4 + nrm.x * s2 * 0.5) * sl, y: q.y + (tan.y * 0.6 + nrm.y * side * 0.4 + nrm.y * s2 * 0.5) * sl)
                        var sub = Path(); sub.move(to: q); sub.addLine(to: e)
                        ctx.stroke(sub, with: .color(light.opacity(0.09)), lineWidth: 0.5)
                    }
                    u += 0.07
                }
            }
            t += 0.03
        }
    }
}

struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
    }
}

/// The name in a heavy wide face with a second copy shifted slightly behind it.
struct Wordmark: View {
    var text = "PRIMAL"
    var size: CGFloat = 56
    var shift = CGSize(width: 7, height: 5)
    @State private var drift = false

    var body: some View {
        ZStack(alignment: .leading) {
            Text(text).font(.brutal(size)).foregroundColor(Color(hex: "#A8C686").opacity(0.55))
                .offset(x: drift ? shift.width : shift.width * 0.4, y: drift ? shift.height : shift.height * 0.4)
            Text(text).font(.brutal(size)).foregroundColor(.ncPrimary)
        }
        .lineLimit(1).minimumScaleFactor(0.5)
        .onAppear { withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { drift = true } }
        .accessibilityLabel(text)
    }
}

/// Hairline rule with spaced-caps label, used to open sections.
struct RuleLabel: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Text(text).spacedCaps(10, tracking: 2).foregroundColor(.ncSecondary)
            Rectangle().fill(Color.ncPrimary.opacity(0.14)).frame(height: 1)
        }
    }
}

/// Compact leaf banner with a shifted title, used at the top of the main tabs.
struct LeafHeader: View {
    let title: String
    var caption: String = ""
    var seed: UInt64 = 3
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LeafBackdrop(seed: seed)
            LinearGradient(colors: [.clear, Color.ncBg.opacity(0.8)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Wordmark(text: title.uppercased(), size: 40, shift: CGSize(width: 5, height: 4))
                if !caption.isEmpty { Text(caption).spacedCaps(10, tracking: 2.6).foregroundColor(.ncPrimary.opacity(0.85)) }
            }
            .padding(16)
        }
        .frame(height: 130)
        .clipShape(Rectangle())
        .overlay(Rectangle().stroke(Color.ncPrimary.opacity(0.16), lineWidth: 1))
    }
}
