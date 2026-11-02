import SwiftUI
import CoreMotion

// MARK: - Light behind the glass
//
// One soft light shines down the screen, under every Liquid Glass surface (tab bar, Home panels, glass dots), and
// slides as the phone tilts, as if a lamp in the room were catching the glass. It lives in screen space, so each surface
// shows the part of the same light that falls on it: the ones nearer the light glow more. One motion manager drives
// all of them, and it only runs while at least one glass surface is on screen.
//
// The light is white: the app is monochrome, so glass gets depth from light and shadow, never hue.

@MainActor
final class GlassLight: ObservableObject {
    static let shared = GlassLight()

    /// Where the light rests with the phone held upright, and always under Reduce Motion: upper left of the screen.
    nonisolated static let resting = UnitPoint(x: 0.3, y: 0.22)

    /// The light's position on screen in unit space; may sit a little outside 0…1 so it can slide off an edge.
    @Published private(set) var point = GlassLight.resting

    private let motion = CMMotionManager()
    private var users = 0

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
                    RadialGradient(colors: [Color.white.opacity(0.16 * strength), Color.white.opacity(0.05 * strength), .clear],
                                   center: center, startRadius: 0, endRadius: reach * 0.9)
                    shape.strokeBorder(
                        RadialGradient(colors: [Color.white.opacity(0.85 * strength), Color.white.opacity(0.25 * strength), .clear],
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
