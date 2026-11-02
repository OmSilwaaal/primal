import SwiftUI
import CoreMotion

// MARK: - Light behind the glass
//
// One soft light shines down the screen, under every Liquid Glass surface (tab bar, Home panels, glass dots), and
// slides as the phone tilts, as if a lamp in the room were catching the glass. It lives in screen space, so each surface
// shows the part of the same light that falls on it: the ones nearer the light glow more. One motion manager drives
// all of them, and it only runs while at least one glass surface is on screen.
//
// The light takes its colour from the session's background photo (green in the forest, sand in the desert, blue at
// night). The photo is sampled in three strips, left to right; as the light slides across with the tilt it blends
// between them, so the colour shifts slightly as the phone moves, and each glow fades towards the opposite strip's
// colour for a gentle gradient.

@MainActor
final class GlassLight: ObservableObject {
    static let shared = GlassLight()

    /// Where the light rests with the phone held upright, and always under Reduce Motion: upper left of the screen.
    nonisolated static let resting = UnitPoint(x: 0.3, y: 0.22)

    /// The light's position on screen in unit space; may sit a little outside 0…1 so it can slide off an edge.
    @Published private(set) var point = GlassLight.resting {
        didSet { updateColors() }
    }
    /// The light's colour where it is now, and the colour its glow fades towards.
    @Published private(set) var color = Color.white
    @Published private(set) var fadeColor = Color.white

    private let motion = CMMotionManager()
    private var users = 0
    /// Left, centre and right strips of the background photo, lifted to light-like colours. White until sampled.
    private var palette: [SIMD3<Double>] = [[1, 1, 1], [1, 1, 1], [1, 1, 1]]

    private init() {
        let asset = Backdrop.current.assetName
        Task.detached(priority: .utility) {
            guard let sampled = Self.samplePalette(assetName: asset) else { return }
            await MainActor.run {
                GlassLight.shared.palette = sampled
                GlassLight.shared.updateColors()
            }
        }
    }

    func start() {
        users += 1
        guard users == 1, motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = Self.sampleInterval
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let gravity = data?.gravity else { return }
            MainActor.assumeIsolated { self?.follow(gravity) }
        }
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0 { motion.stopDeviceMotionUpdates() }
    }

    private static let sampleInterval = 1.0 / 60
    /// How long the light takes to catch up with the phone (time constant). Long enough that it trails the hand a
    /// little and glides, short enough that it still feels attached to the tilt.
    private static let lag = 0.45
    private static let easing = 1 - exp(-sampleInterval / lag)

    /// Where the tilt alone puts the light, and how far scrolling nudges it; the light eases towards their sum.
    private var tiltTarget = GlassLight.resting
    private var scrollShift = 0.0
    /// Eases the light when the motion sensor isn't driving it (no sensor, or Simulator).
    private var settleTask: Task<Void, Never>?

    /// Gravity is (0, -1, 0) held upright, (0, 0, -1) lying flat. Tilt right and the light slides left, tip the top
    /// away and it slides down, like a reflection of a fixed light. Eased with a ~0.45 s lag so it glides after
    /// the hand rather than snapping, and sensor jitter never shows.
    private func follow(_ g: CMAcceleration) {
        tiltTarget = UnitPoint(x: Self.resting.x - g.x * 1.1, y: Self.resting.y + (g.y + 0.75) * 1.2)
        step()
    }

    /// A screen's vertical scroll offset, in points. The light drifts gently against the scroll — up to about a
    /// tenth of the screen over a screen's worth of scrolling — so the rims shimmer as the page moves.
    func scrolled(to offset: CGFloat) {
        let screens = Double(offset / max(UIScreen.main.bounds.height, 1))
        let shift = -0.1 * min(1.5, max(-0.3, screens))
        guard abs(shift - scrollShift) > 0.0005 else { return }
        scrollShift = shift
        guard !motion.isDeviceMotionActive, settleTask == nil else { return }
        settleTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.step() {
                try? await Task.sleep(for: .seconds(Self.sampleInterval))
            }
            self?.settleTask = nil
        }
    }

    /// Moves the light one frame towards its target. Returns false once it has arrived.
    @discardableResult private func step() -> Bool {
        let tx = min(1.25, max(-0.25, tiltTarget.x))
        let ty = min(1.25, max(-0.25, tiltTarget.y + scrollShift))
        let k = Self.easing
        let next = UnitPoint(x: point.x + (tx - point.x) * k, y: point.y + (ty - point.y) * k)
        // Skip invisible sub-pixel moves so resting glass doesn't redraw 60 times a second.
        guard abs(next.x - point.x) > 0.0004 || abs(next.y - point.y) > 0.0004 else { return false }
        point = next
        return true
    }

    private func updateColors() {
        let t = min(1, max(0, point.x))
        color = Self.rgb(Self.blend(palette, at: t))
        fadeColor = Self.rgb(Self.blend(palette, at: 1 - t))
    }

    private static func blend(_ p: [SIMD3<Double>], at t: Double) -> SIMD3<Double> {
        t < 0.5 ? p[0] + (p[1] - p[0]) * (t * 2) : p[1] + (p[2] - p[1]) * ((t - 0.5) * 2)
    }

    private static func rgb(_ v: SIMD3<Double>) -> Color { Color(red: v.x, green: v.y, blue: v.z) }

    /// Averages the photo's left, centre and right thirds by drawing it into a 3×1 bitmap, then lifts each to full
    /// brightness with moderate saturation so it reads as coloured light rather than a dark photo tone.
    nonisolated private static func samplePalette(assetName: String) -> [SIMD3<Double>]? {
        guard let image = UIImage(named: assetName)?.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: 3 * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: 3, height: 1, bitsPerComponent: 8, bytesPerRow: 12,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: 3, height: 1))
            return true
        }
        guard drawn else { return nil }
        return (0..<3).map { i in
            let c = UIColor(red: CGFloat(pixels[i * 4]) / 255, green: CGFloat(pixels[i * 4 + 1]) / 255,
                            blue: CGFloat(pixels[i * 4 + 2]) / 255, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            let lifted = UIColor(hue: h, saturation: min(0.75, max(0.25, s * 1.6)), brightness: 1, alpha: 1)
            var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0
            lifted.getRed(&r, green: &g, blue: &bl, alpha: &a)
            return SIMD3(Double(r), Double(g), Double(bl))
        }
    }
}

/// The light itself where it falls on one surface. Directional, like a real lamp on a sheet of glass: the rim facing
/// the light catches a bright, thin highlight that fades away within a short arc around the edge; the opposite inner
/// rim gets a faint reflected catch; and a small soft bloom sits just inside the lit corner. The body of the glass is
/// never lit, so it stays clear. Surfaces nearer the light catch more of it. Placed behind a surface's content.
struct GlassSheen<S: InsettableShape>: View {
    let shape: S
    var strength: Double = 1
    @ObservedObject private var light = GlassLight.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(shape: S, strength: Double = 1) {
        self.shape = shape
        self.strength = strength
    }

    var body: some View {
        if !reduceTransparency {
            let p = reduceMotion ? GlassLight.resting : light.point
            GeometryReader { geo in
                let screen = UIScreen.main.bounds.size
                let frame = geo.frame(in: .global)
                let w = max(frame.width, 1), h = max(frame.height, 1)
                // From this surface's centre towards the light, in screen points (y down, so angles run clockwise
                // from the trailing edge, as SwiftUI's gradients expect).
                let dx = p.x * screen.width - frame.midX, dy = p.y * screen.height - frame.midY
                let angle = Angle.radians(atan2(dy, dx))
                // Nearer the light, brighter catch: full within a third of the screen, down to 40% far away.
                let distance = (dx * dx + dy * dy).squareRoot() / screen.height
                let k = strength * min(1, max(0.4, 1.15 - distance))
                // Where the bloom sits: the point on the surface's edge facing the light, pulled slightly inside.
                let reachX = dx / max(abs(dx), abs(dy) * w / h, 1) * 0.42
                let reachY = dy / max(abs(dy), abs(dx) * h / w, 1) * 0.42
                let bloom = UnitPoint(x: 0.5 + reachX, y: 0.5 + reachY)
                ZStack {
                    // Soft light just inside the lit edge; small, so the rest of the glass stays clear.
                    RadialGradient(colors: [light.color.opacity(0.10 * k), .clear],
                                   center: bloom, startRadius: 0, endRadius: min(w, h) * 0.45)
                    // A soft halo along the lit rim…
                    shape.strokeBorder(rim(angle, main: 0.45 * k, back: 0.10 * k), lineWidth: 4)
                        .blur(radius: 3)
                    // …and the crisp catch itself.
                    shape.strokeBorder(rim(angle, main: 0.95 * k, back: 0.28 * k), lineWidth: 1.1)
                }
            }
            .clipShape(shape)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { light.start() }
            .onDisappear { light.stop() }
        }
    }

    /// Bright where the rim faces the light, gone within ~60° either side, and a faint reflected catch opposite.
    private func rim(_ angle: Angle, main: Double, back: Double) -> AngularGradient {
        let lit = light.color, far = light.fadeColor
        return AngularGradient(stops: [
            .init(color: lit.opacity(main), location: 0),
            .init(color: lit.opacity(main * 0.35), location: 0.07),
            .init(color: .clear, location: 0.17),
            .init(color: .clear, location: 0.38),
            .init(color: far.opacity(back), location: 0.5),
            .init(color: .clear, location: 0.62),
            .init(color: .clear, location: 0.83),
            .init(color: lit.opacity(main * 0.35), location: 0.93),
            .init(color: lit.opacity(main), location: 1),
        ], center: .center, angle: angle)
    }
}

extension View {
    /// Lets this vertical ScrollView nudge the glass light as it scrolls (iOS 18+; the light just holds still on 17).
    @ViewBuilder func glassLightFollowsScroll() -> some View {
        if #available(iOS 18.0, *) {
            onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
                GlassLight.shared.scrolled(to: y)
            }
        } else {
            self
        }
    }

    /// Puts the moving light under this view's content, inside `shape`.
    func glassSheen<S: InsettableShape>(in shape: S, strength: Double = 1) -> some View {
        background { GlassSheen(shape: shape, strength: strength) }
    }
}
