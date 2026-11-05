import SwiftUI

/// One carousel card: the group name large in the display font, the score as a small dot-matrix number over
/// "/ 100", a decorative expand button, and the group's nutrients along the bottom as progress bars (Seasonal: the
/// season as a pill; "coming soon" is said once, under the wheel), all on clear Liquid Glass with the
/// moving glass light. The whole card is the button.
struct CarouselCard: View {
    let summary: DataGroupSummary
    let size: CGSize
    let onOpen: () -> Void

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
                        if summary.isComingSoon {
                            Text("Eating with the seasons")
                                .font(.mono(12, .semibold)).tracking(0.9).textCase(.uppercase)
                                .foregroundColor(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            HStack(alignment: .lastTextBaseline, spacing: 6) {
                                DotMatrixText(text: "\(summary.score)", pitch: 4)
                                Text("/ 100").font(.mono(12, .semibold)).foregroundColor(.white.opacity(0.85))
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
                if summary.isComingSoon {
                    Spacer(minLength: 16)
                    FlowLayout(spacing: 6) {
                        ForEach(summary.pills) { NutrientPill(model: $0) }
                    }
                } else {
                    // Centred in the space under the title, with equal room above and below.
                    Spacer(minLength: 18)
                    NutrientBars(items: summary.items)
                    Spacer(minLength: 18)
                }
            }
            .padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 24)
            .frame(width: size.width, alignment: .topLeading)
            .frame(minHeight: size.height, alignment: .topLeading)
            // The group's drawing rising out of the bottom-right corner, as on Home's tiles (scaled to the card).
            .lineArt(kind.art, placement: LineArt.Placement(alignment: .bottomTrailing, size: size.width * 0.6,
                                                            offset: CGSize(width: size.width * 0.12, height: size.width * 0.2)),
                     radius: radius)
            // Clear glass: the wheel cuts each card out of the ones behind it, so nothing shows through but the photo.
            .glass(.clear, in: shape)
            .glassSheen(in: shape, strength: 0.6)
            .contentShape(shape)
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
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
}

/// The group's nutrients as bars running left to right: the short name, then a rounded track filled to the
/// nutrient's share of its target (never less than a dot, so an empty one still reads), then the percent. Moss when
/// met, warm gray on track, Ember when low. Rows tighten as the list grows so every group fits the card.
private struct NutrientBars: View {
    let items: [NutrientInfo]

    var body: some View {
        let dense = items.count > 7
        VStack(spacing: dense ? 9 : 16) {
            ForEach(items) { n in
                HStack(spacing: 10) {
                    Text(n.short).font(.mono(dense ? 10 : 11, .semibold)).tracking(0.5).textCase(.uppercase)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: 38, alignment: .leading)
                    NutrientBar(n: n)
                        .frame(height: dense ? 8 : 12)
                    Text("\(Int((min(max(n.share, 0), 9.99) * 100).rounded()))%")
                        .font(.mono(dense ? 10 : 11, .semibold)).monospacedDigit()
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct NutrientBar: View {
    let n: NutrientInfo

    var body: some View {
        let share = min(max(n.share, 0), 1)
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(fill(NutrientStatus(percent: n.share * 100)))
                    .frame(width: max(h, geo.size.width * share))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: share)
        .accessibilityHidden(true)
    }

    private func fill(_ s: NutrientStatus) -> LinearGradient {
        let colors: [Color] = switch s {
        case .met: [Color(hex: "#8FBA79"), Color(hex: "#A9D293")]
        case .low: [Color(hex: "#E07C5F"), Color(hex: "#EC8D70")]
        case .onTrack: [Color(hex: "#8D8C87"), Color(hex: "#A4A39E")]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
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
