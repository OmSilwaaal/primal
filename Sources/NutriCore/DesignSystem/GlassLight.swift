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
        motion.deviceMotionUpdateInterval = 1 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let gravity = data?.gravity else { return }
            MainActor.assumeIsolated { self?.follow(gravity) }
        }
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0 { motion.stopDeviceMotionUpdates() }
    }

    /// Gravity is (0, -1, 0) held upright, (0, 0, -1) lying flat. Tilt right and the light slides left, tip the top
    /// away and it slides down, like a reflection of a fixed light. Eased so sensor jitter never shows.
    private func follow(_ g: CMAcceleration) {
        let x = Self.resting.x - g.x * 0.9
        let y = Self.resting.y + (g.y + 0.75) * 1.1
        let target = UnitPoint(x: min(1.2, max(-0.2, x)), y: min(1.2, max(-0.2, y)))
        point = UnitPoint(x: point.x + (target.x - point.x) * 0.18, y: point.y + (target.y - point.y) * 0.18)
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

/// The light itself where it falls on one surface: a wide soft glow plus a brighter catch on the rim nearest it,
/// clipped to the glass's shape. Placed behind a surface's content, on top of the glass material.
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
                // The light's screen position, expressed in this surface's own unit space.
                let screen = UIScreen.main.bounds.size
                let frame = geo.frame(in: .global)
                let w = max(frame.width, 1), h = max(frame.height, 1)
                let center = UnitPoint(x: (p.x * screen.width - frame.minX) / w, y: (p.y * screen.height - frame.minY) / h)
                let reach = screen.height
                ZStack {
                    // Kept faint so the glass stays clear; the rim carries most of the light.
                    RadialGradient(colors: [light.color.opacity(0.16 * strength), light.fadeColor.opacity(0.05 * strength), .clear],
                                   center: center, startRadius: 0, endRadius: reach * 0.9)
                    shape.strokeBorder(
                        RadialGradient(colors: [light.color.opacity(0.85 * strength), light.fadeColor.opacity(0.25 * strength), .clear],
                                       center: center, startRadius: 0, endRadius: reach * 0.95),
                        lineWidth: 1.2)
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
}

extension View {
    /// Puts the moving light under this view's content, inside `shape`.
    func glassSheen<S: InsettableShape>(in shape: S, strength: Double = 1) -> some View {
        background { GlassSheen(shape: shape, strength: strength) }
    }
}
