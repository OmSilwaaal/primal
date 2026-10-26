import SwiftUI

/// The Algiz rune (ᛉ) from the app icon: a square-ended stem with two arms rising from just above its middle.
/// Drawn as one filled outline, aspect-fit and centred in the rect. Proportions match the icon generator.
struct AlgizMark: Shape {
    /// Stroke weight, as a fraction of the glyph height.
    var stroke: CGFloat = 0.145
    /// Arm angle from the stem, in degrees.
    var armAngle: Double = 43
    /// Where the arm centrelines meet the stem centreline, as a fraction of the height from the top.
    var join: CGFloat = 0.45

    func path(in rect: CGRect) -> Path {
        let tanA = CGFloat(tan(armAngle * .pi / 180))
        let armWidth = stroke / CGFloat(cos(armAngle * .pi / 180))
        let armTop = join * tanA
        let aspect = 2 * (armTop + armWidth / 2)

        let h = min(rect.height, rect.width / aspect)
        let t = stroke * h, w = armWidth * h, j = join * h, xTop = armTop * h
        let inner = j - (w / 2 + t / 2) / tanA
        let outer = j + (w / 2 - t / 2) / tanA

        let right: [CGPoint] = [
            CGPoint(x: t / 2, y: 0),
            CGPoint(x: t / 2, y: inner),
            CGPoint(x: xTop - w / 2, y: 0),
            CGPoint(x: xTop + w / 2, y: 0),
            CGPoint(x: t / 2, y: outer),
            CGPoint(x: t / 2, y: h),
        ]
        let outline = right + right.reversed().map { CGPoint(x: -$0.x, y: $0.y) }

        let origin = CGPoint(x: rect.midX, y: rect.midY - h / 2)
        var path = Path()
        path.addLines(outline.map { CGPoint(x: origin.x + $0.x, y: origin.y + $0.y) })
        path.closeSubpath()
        return path
    }
}
