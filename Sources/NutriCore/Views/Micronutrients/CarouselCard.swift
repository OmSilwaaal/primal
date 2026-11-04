import SwiftUI

/// One carousel card: the group name large in the display font with a soft glow, the score as a small dot-matrix
/// number over "/ 100", a decorative expand button, and the group's nutrients (Seasonal: the season and "Coming soon") as pills
/// along the bottom. The surface is the group's colour pouring from the top edge into its dark base, with faint
/// glows in the bottom corners and an inner bottom glow that drift slowly, a fine grain, a hairline highlight, the moving glass light and a soft outer
/// shadow in the group colour. The whole card is the button.
struct CarouselCard: View {
    let summary: DataGroupSummary
    let size: CGSize
    let onOpen: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var kind: DataGroupKind { summary.kind }
    private var radius: CGFloat { 58 * size.width / 270 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(kind.title)
                            .font(.display(44)).foregroundColor(.white)
                            .lineLimit(1).minimumScaleFactor(0.55)
                            // A soft glow in the group colour, plus a dark lift for contrast on the lighter tops.
                            .grained(0.3)
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                            .shadow(color: kind.color.opacity(0.7), radius: 14)
                        if summary.isComingSoon {
                            Text("Eating with the seasons — coming soon")
                                .font(.outermost(14)).foregroundColor(.white.opacity(0.88))
                                .fixedSize(horizontal: false, vertical: true)
                                .grained()
                        } else {
                            HStack(alignment: .lastTextBaseline, spacing: 6) {
                                DotMatrixText(text: "\(summary.score)", pitch: 4)
                                Text("/ 100").font(.outermost(14)).foregroundColor(.white.opacity(0.88)).grained()
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.ui(size: 14, weight: .semibold)).foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .liquidGlassPanel(in: Circle())
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 16)
                FlowLayout(spacing: 6) {
                    ForEach(summary.pills) { NutrientPill(model: $0) }
                }
            }
            .padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 24)
            .frame(width: size.width, alignment: .topLeading)
            .frame(minHeight: size.height, alignment: .topLeading)
            .background { surface(shape) }
            .overlay { shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
            .contentShape(shape)
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .shadow(color: kind.color.opacity(0.33), radius: 28, y: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens details")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        if summary.isComingSoon { return "Seasonal eating, coming soon" }
        let lows = summary.low
        return "\(kind.title), score \(summary.score), \(lows) low nutrient\(lows == 1 ? "" : "s")"
    }

    @ViewBuilder private func surface(_ shape: RoundedRectangle) -> some View {
        if reduceTransparency {
            ZStack { kind.base; kind.color.opacity(0.22) }.clipShape(shape)
        } else if reduceMotion {
            glow(at: 0).clipShape(shape).glassSheen(in: shape, strength: 0.6)
        } else {
            // The colour breathes: its glows drift slowly around the card on out-of-step cycles.
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                glow(at: context.date.timeIntervalSinceReferenceDate)
            }
            .clipShape(shape)
            .glassSheen(in: shape, strength: 0.6)
        }
    }

    /// The card's colour at time `t`: poured from the top edge (gone by ~80% of the height), faint glows in the
    /// bottom corners and an inner bottom glow, each drifting and swelling slowly, under a fine grain. Kept at half
    /// strength at the very top so white text there stays above 4.5:1 on every colour.
    private func glow(at t: Double) -> some View {
        let w = size.width, h = size.height
        func wave(_ period: Double, _ phase: Double = 0) -> Double { sin(t * 2 * .pi / period + phase) }
        return ZStack {
            // Tinted glass over the photo: a light frost and the group's dark base at part strength.
            Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
            kind.base.opacity(0.62)
            RadialGradient(colors: [kind.color.opacity(0.5), kind.color.opacity(0.18), .clear],
                           center: UnitPoint(x: 0.5 + 0.12 * wave(13), y: 0),
                           startRadius: 0, endRadius: h * (0.8 + 0.05 * wave(9, 1)))
            RadialGradient(colors: [kind.color.opacity(0.2 + 0.06 * wave(7)), .clear],
                           center: UnitPoint(x: 0.08 * wave(11, 2), y: 1 + 0.04 * wave(8)),
                           startRadius: 0, endRadius: w * (0.6 + 0.08 * wave(10, 3)))
            RadialGradient(colors: [kind.color.opacity(0.2 + 0.06 * wave(8, 2)), .clear],
                           center: UnitPoint(x: 1 + 0.08 * wave(12, 4), y: 1 + 0.04 * wave(9, 1)),
                           startRadius: 0, endRadius: w * (0.6 + 0.08 * wave(11)))
            RadialGradient(colors: [kind.color.opacity(0.22 + 0.06 * wave(6, 1)), .clear],
                           center: UnitPoint(x: 0.5 + 0.1 * wave(14, 2), y: 1.05),
                           startRadius: 0, endRadius: w * 0.55)
            // Grain, so the colour reads like pigment rather than a flat digital gradient.
            GrainLayer(opacity: 0.16, blend: .overlay)
        }
    }
}

#if DEBUG
#Preview("Cards") {
    ScrollView(.horizontal) {
        HStack(spacing: 20) {
            ForEach(DataPreview.summaries) { s in
                CarouselCard(summary: s, size: CGSize(width: 270, height: 400)) {}
            }
        }
        .padding(30)
    }
    .background(Color(hex: "#08090A"))
    .preferredColorScheme(.dark)
}
#endif
