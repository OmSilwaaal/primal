import SwiftUI

/// One carousel card: the group name large in the display font with a soft glow, the score as a small dot-matrix
/// number over "/ 100", a decorative expand button, and the group's nutrients (or, on Overall, the groups) as pills
/// along the bottom. The surface is the group's colour pouring from the top edge into its dark base, with faint
/// glows in the bottom corners, an inner bottom glow, a hairline highlight, the moving glass light and a soft outer
/// shadow in the group colour. The whole card is the button.
struct CarouselCard: View {
    let summary: DataGroupSummary
    let size: CGSize
    let onOpen: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                            .shadow(color: kind.color.opacity(0.7), radius: 14)
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            DotMatrixText(text: "\(summary.score)", pitch: 4)
                            Text("/ 100").font(.mono(12, .semibold)).foregroundColor(.white.opacity(0.85))
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
        let lows = summary.low
        return "\(kind.title), score \(summary.score), \(lows) low nutrient\(lows == 1 ? "" : "s")"
    }

    @ViewBuilder private func surface(_ shape: RoundedRectangle) -> some View {
        if reduceTransparency {
            ZStack { kind.base; kind.color.opacity(0.22) }.clipShape(shape)
        } else {
            ZStack {
                // Tinted glass over the photo, like the app's other tiles: a light frost and the group's dark base
                // at part strength, so the backdrop still shows through.
                Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                kind.base.opacity(0.62)
                // The colour pours from the top edge and is gone by about 80% of the height. Kept at half strength
                // at the very top so white text there stays above 4.5:1, even on the lime and sand cards.
                RadialGradient(colors: [kind.color.opacity(0.5), kind.color.opacity(0.18), .clear],
                               center: .top, startRadius: 0, endRadius: size.height * 0.8)
                RadialGradient(colors: [kind.color.opacity(0.2), .clear], center: .bottomLeading,
                               startRadius: 0, endRadius: size.width * 0.6)
                RadialGradient(colors: [kind.color.opacity(0.2), .clear], center: .bottomTrailing,
                               startRadius: 0, endRadius: size.width * 0.6)
                // Inner bottom glow.
                RadialGradient(colors: [kind.color.opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 1.05),
                               startRadius: 0, endRadius: size.width * 0.55)
            }
            .clipShape(shape)
            .glassSheen(in: shape, strength: 0.6)
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
