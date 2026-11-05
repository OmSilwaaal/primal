import SwiftUI
import UIKit
import CoreMotion

// MARK: - Light on the glass
//
// One soft light shines on every glass surface (tiles, buttons, the tab bar, the calorie ring) and moves as the phone
// tilts and the page scrolls, as if a lamp in the room were catching the glass. It lives in screen space, so each
// surface shows the part of the same light that falls on it: the rim facing the light catches a thin bright line with
// a soft halo, the opposite rim a faint reflection, and a small bloom sits just inside the lit edge.
//
// Built for smoothness and to stay off SwiftUI's update path:
//   • Core Motion and scrolling only set where the light should be (its target).
//   • One CADisplayLink, at the screen's refresh rate (up to 120 Hz), moves the light towards the target with a
//     critically damped spring — it glides and settles without overshoot or the stepping of per-sample easing.
//   • Each surface is a small stack of Core Animation layers; every frame the display link updates their gradients
//     directly. No SwiftUI view is invalidated by the light, so scrolling and taps aren't slowed by it.
//   • The light breathes: its brightness swells and eases over about five seconds.
//
// Colour comes from the session's background photo (green in the forest, sand in the desert, blue at night), sampled
// in three strips and blended as the light slides across. Reduce Motion holds the light still and stops the breathing;
// Reduce Transparency removes it.

@MainActor
final class GlassLight {
    static let shared = GlassLight()

    /// Where the light rests with the phone held upright: left of centre, a third of the way down.
    nonisolated static let resting = CGPoint(x: 0.32, y: 0.34)

    /// Spring stiffness (rad/s): higher follows the hand more tightly. ~0.35 s to settle, never overshoots.
    private static let stiffness = 11.0
    /// One breath, in seconds, and how much the brightness swells (± fraction).
    private static let breathPeriod = 5.0
    private static let breathDepth = 0.16

    /// Unit-space screen position and velocity of the light; where tilt and scroll want it.
    private(set) var point = GlassLight.resting
    private var velocity = CGPoint.zero
    private var tiltTarget = GlassLight.resting
    private var scrollShift = 0.0
    /// Brightness multiplier from the breathing (1 = rest).
    private(set) var breath = 1.0
    private(set) var color = UIColor.white
    private(set) var fadeColor = UIColor.white

    private let motion = CMMotionManager()
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private let surfaces = NSHashTable<SheenSurfaceView>.weakObjects()
    /// Left, centre and right strips of the background photo, lifted to light-like colours. White until sampled.
    /// Eases towards `target` every frame, so a scene change on Data shifts the light's colour smoothly.
    private var palette: [SIMD3<Double>] = [[1, 1, 1], [1, 1, 1], [1, 1, 1]]
    private var target: [SIMD3<Double>] = [[1, 1, 1], [1, 1, 1], [1, 1, 1]]
    /// Every scene's palette, sampled once at launch; the session's is `sessionPalette`.
    private var scenePalettes: [Backdrop: [SIMD3<Double>]] = [:]
    private var sessionPalette: [SIMD3<Double>] = [[1, 1, 1], [1, 1, 1], [1, 1, 1]]
    /// The scene blend asked for last (nil = the session's photo), kept so it applies once palettes arrive.
    private var scene: (Backdrop, Backdrop, Double)?

    var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    private init() {
        Task.detached(priority: .utility) {
            let all = Dictionary(uniqueKeysWithValues: Backdrop.allCases.compactMap { scene in
                Self.samplePalette(assetName: scene.assetName).map { (scene, $0) }
            })
            await MainActor.run {
                let light = GlassLight.shared
                light.scenePalettes = all
                if let own = all[Backdrop.current] { light.sessionPalette = own; light.palette = own }
                light.retarget()
                light.palette = light.target
                light.updateColors()
                light.redrawAll()
            }
        }
        updateColors()
    }

    // MARK: Surfaces

    func register(_ surface: SheenSurfaceView) {
        surfaces.add(surface)
        surface.redraw(light: self)
        startIfNeeded()
    }

    func unregister(_ surface: SheenSurfaceView) {
        surfaces.remove(surface)
        if surfaces.allObjects.isEmpty { stop() }
    }

    private func startIfNeeded() {
        guard link == nil else { return }
        if motion.isDeviceMotionAvailable, !reduceMotion {
            motion.deviceMotionUpdateInterval = 1.0 / 60
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let g = data?.gravity else { return }
                MainActor.assumeIsolated { self?.setTilt(g) }
            }
        }
        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTime = 0
    }

    private func stop() {
        link?.invalidate()
        link = nil
        motion.stopDeviceMotionUpdates()
    }

    // MARK: Inputs

    /// Gravity is (0, -1, 0) held upright, (0, 0, -1) lying flat. Tilt right and the light slides left, tip the top
    /// away and it slides down, like a reflection of a fixed light.
    private func setTilt(_ g: CMAcceleration) {
        tiltTarget = CGPoint(x: Self.resting.x - g.x * 1.25, y: Self.resting.y + (g.y + 0.75) * 1.3)
    }

    /// A screen's vertical scroll offset, in points. The light drifts gently against the scroll — about a tenth of
    /// the screen over a screen's worth of scrolling — so the rims shimmer as the page moves.
    func scrolled(to offset: CGFloat) {
        let screens = Double(offset / max(UIScreen.main.bounds.height, 1))
        scrollShift = -0.1 * min(1.5, max(-0.3, screens))
    }

    // MARK: Scene

    /// Blend the light's colour between two scenes' palettes (`mix` 0 = `a`); nil, nil goes back to the session's.
    func setScene(_ a: Backdrop?, _ b: Backdrop?, mix: Double) {
        if let a, let b { scene = (a, b, min(1, max(0, mix))) } else { scene = nil }
        retarget()
        if reduceMotion || link == nil { palette = target; updateColors(); redrawAll() }
    }

    private func retarget() {
        guard let (a, b, t) = scene, let pa = scenePalettes[a], let pb = scenePalettes[b] else {
            target = sessionPalette
            return
        }
        target = zip(pa, pb).map { $0 + ($1 - $0) * t }
    }

    // MARK: Frame

    fileprivate func tick(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let dt = lastTime == 0 ? 1.0 / 60 : min(1.0 / 20, max(1.0 / 240, now - lastTime))
        lastTime = now

        if reduceMotion {
            point = Self.resting
            velocity = .zero
            breath = 1
        } else {
            let tx = min(1.25, max(-0.25, tiltTarget.x))
            let ty = min(1.25, max(-0.25, tiltTarget.y + scrollShift))
            // Critically damped spring: a = ω²(target − x) − 2ω·v.
            let w = Self.stiffness
            let ax = w * w * (tx - point.x) - 2 * w * velocity.x
            let ay = w * w * (ty - point.y) - 2 * w * velocity.y
            velocity.x += ax * dt; velocity.y += ay * dt
            point.x += velocity.x * dt; point.y += velocity.y * dt
            breath = 1 + Self.breathDepth * sin(now * 2 * .pi / Self.breathPeriod)
        }
        // The colour glides to its target (about 0.4 s to settle): exponential, so it never overshoots or steps.
        let k = reduceMotion ? 1 : 1 - exp(-dt * 7)
        palette = zip(palette, target).map { $0 + ($1 - $0) * k }
        updateColors()
        redrawAll()
    }

    private func redrawAll() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for surface in surfaces.allObjects { surface.redraw(light: self) }
        CATransaction.commit()
    }

    // MARK: Colour

    private func updateColors() {
        let t = min(1, max(0, Double(point.x)))
        color = Self.uiColor(Self.blend(palette, at: t))
        fadeColor = Self.uiColor(Self.blend(palette, at: 1 - t))
    }

    private static func blend(_ p: [SIMD3<Double>], at t: Double) -> SIMD3<Double> {
        t < 0.5 ? p[0] + (p[1] - p[0]) * (t * 2) : p[1] + (p[2] - p[1]) * ((t - 0.5) * 2)
    }

    private static func uiColor(_ v: SIMD3<Double>) -> UIColor { UIColor(red: v.x, green: v.y, blue: v.z, alpha: 1) }

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
            let lifted = UIColor(hue: h, saturation: min(0.7, max(0.2, s * 1.5)), brightness: 1, alpha: 1)
            var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0
            lifted.getRed(&r, green: &g, blue: &bl, alpha: &a)
            return SIMD3(Double(r), Double(g), Double(bl))
        }
    }
}

/// CADisplayLink retains its target; this keeps it from retaining the light.
private final class DisplayLinkProxy {
    weak var light: GlassLight?
    init(_ light: GlassLight) { self.light = light }
    @objc func tick(_ link: CADisplayLink) {
        MainActor.assumeIsolated { light?.tick(link) }
    }
}

// MARK: - Surface

/// The light where it falls on one surface, drawn with Core Animation layers and updated by `GlassLight` each frame.
final class SheenSurfaceView: UIView {
    var makePath: (CGRect) -> CGPath = { UIBezierPath(rect: $0).cgPath }
    var strength: Double = 1

    /// Light caught inside the glass: a soft wash rising from the bottom, a pool of the light's colour sitting in
    /// the lower part of the surface, and a bright line along the bottom edge — like light trapped in thick glass.
    private let volume = CAGradientLayer()
    private let pool = CAGradientLayer()
    private let baseLine = CAGradientLayer()
    private let baseLineMask = CAShapeLayer()
    private let bloom = CAGradientLayer()
    private let halo = CAGradientLayer()
    private let rim = CAGradientLayer()
    private let haloMask = CAShapeLayer()
    private let rimMask = CAShapeLayer()
    private let clip = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        pool.type = .radial
        bloom.type = .radial
        halo.type = .conic
        rim.type = .conic
        for mask in [haloMask, rimMask, baseLineMask] {
            mask.fillColor = UIColor.clear.cgColor
            mask.strokeColor = UIColor.white.cgColor
        }
        haloMask.lineWidth = 7
        rimMask.lineWidth = 2.4   // half of it lies outside the shape and is clipped: ~1.2 pt visible
        halo.mask = haloMask
        rim.mask = rimMask
        baseLineMask.lineWidth = 3
        baseLine.mask = baseLineMask
        layer.addSublayer(volume)
        layer.addSublayer(pool)
        layer.addSublayer(baseLine)
        layer.addSublayer(bloom)
        layer.addSublayer(halo)
        layer.addSublayer(rim)
        layer.mask = clip
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { GlassLight.shared.register(self) } else { GlassLight.shared.unregister(self) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = makePath(bounds)
        clip.path = path
        haloMask.path = path
        rimMask.path = path
        baseLineMask.path = path
        for l in [volume, pool, baseLine, baseLineMask, bloom, halo, rim, haloMask, rimMask, clip] as [CALayer] {
            l.frame = bounds
        }
        CATransaction.commit()
        redraw(light: GlassLight.shared)
    }
    

    func redraw(light: GlassLight) {
        guard let window, bounds.width > 1, bounds.height > 1 else { return }
        let frame = convert(bounds, to: window)
        let screen = window.bounds.size
        let w = frame.width, h = frame.height
        // From this surface's centre towards the light, in points.
        let dx = light.point.x * screen.width - frame.midX
        let dy = light.point.y * screen.height - frame.midY
        let angle = atan2(dy, dx)
        // Nearer the light, brighter: full within a third of the screen, down to 45% far away; then the breath.
        let distance = (dx * dx + dy * dy).squareRoot() / screen.height
        let k = strength * min(1, max(0.45, 1.15 - distance)) * light.breath
        let lit = light.color, far = light.fadeColor

        // Conic gradients start at the trailing edge and run clockwise; aim the start at the light.
        let dir = CGPoint(x: 0.5 + cos(angle) * 0.5, y: 0.5 + sin(angle) * 0.5)
        for (layer, main, back) in [(halo, 0.4 * k, 0.1 * k), (rim, 0.85 * k, 0.26 * k)] {
            layer.startPoint = CGPoint(x: 0.5, y: 0.5)
            layer.endPoint = dir
            layer.colors = [lit.withAlphaComponent(min(1, main)), lit.withAlphaComponent(min(1, main * 0.4)),
                            UIColor.clear, UIColor.clear, far.withAlphaComponent(min(1, back)), UIColor.clear,
                            UIColor.clear, lit.withAlphaComponent(min(1, main * 0.4)),
                            lit.withAlphaComponent(min(1, main))].map(\.cgColor)
            layer.locations = [0, 0.07, 0.17, 0.38, 0.5, 0.62, 0.83, 0.93, 1]
        }

        // The pool: one glow in screen space, centred on the light itself and about two thirds of the screen wide.
        // Each surface shows only the part of it that falls on it — bright on the glass nearest the light, a faint
        // edge on glass further off, nothing on glass out of reach — so neighbouring tiles read as lit by the same
        // lamp rather than each carrying its own glow.
        let p = strength * light.breath
        let radius = Double(screen.width) * 0.72
        let centre = CGPoint(x: (light.point.x * screen.width - frame.minX) / w,
                             y: (light.point.y * screen.height - frame.minY) / h)
        pool.startPoint = centre
        pool.endPoint = CGPoint(x: centre.x + radius / w, y: centre.y + radius / h)
        pool.colors = [lit.withAlphaComponent(min(1, 0.42 * p)), lit.withAlphaComponent(min(1, 0.2 * p)),
                       far.withAlphaComponent(min(1, 0.06 * p)), UIColor.clear].map(\.cgColor)
        pool.locations = [0, 0.32, 0.68, 1]
        // The uniform wash and base line are gone: they made every block look the same.
        volume.colors = nil
        baseLine.colors = nil

        // Bloom: just inside the edge facing the light.
        let reachX = dx / max(abs(dx), abs(dy) * w / h, 1) * 0.42
        let reachY = dy / max(abs(dy), abs(dx) * h / w, 1) * 0.42
        let r = min(w, h) * 0.55
        bloom.startPoint = CGPoint(x: 0.5 + reachX, y: 0.5 + reachY)
        bloom.endPoint = CGPoint(x: bloom.startPoint.x + r / w, y: bloom.startPoint.y + r / h)
        bloom.colors = [lit.withAlphaComponent(min(1, 0.16 * k)), lit.withAlphaComponent(0)].map(\.cgColor)
    }
}

/// SwiftUI wrapper for one surface's light, clipped to `shape`.
private struct SheenSurface<S: Shape>: UIViewRepresentable {
    let shape: S
    let strength: Double

    func makeUIView(context: Context) -> SheenSurfaceView {
        let view = SheenSurfaceView()
        update(view)
        return view
    }

    func updateUIView(_ view: SheenSurfaceView, context: Context) {
        update(view)
        view.setNeedsLayout()
    }

    private func update(_ view: SheenSurfaceView) {
        let shape = shape
        view.makePath = { shape.path(in: $0).cgPath }
        view.strength = strength
    }
}

/// The light on one surface, behind its content.
struct GlassSheen<S: Shape>: View {
    let shape: S
    var strength: Double = 1
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(shape: S, strength: Double = 1) {
        self.shape = shape
        self.strength = strength
    }

    var body: some View {
        if !reduceTransparency {
            SheenSurface(shape: shape, strength: strength)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
    func glassSheen<S: Shape>(in shape: S, strength: Double = 1) -> some View {
        background { GlassSheen(shape: shape, strength: strength) }
    }
}
