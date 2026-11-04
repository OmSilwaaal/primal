import SwiftUI

/// One carousel card: the group name large in the display font, the score as a small dot-matrix number over
/// "/ 100", a decorative expand button, and the group's nutrients (Seasonal: the season and "Coming soon") as pills
/// along the bottom as progress bars (Seasonal: the season and "Coming soon"), all on clear Liquid Glass with the
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
                            Text("Eating with the seasons — coming soon")
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
                Spacer(minLength: 16)
                if summary.isComingSoon {
                    FlowLayout(spacing: 6) {
                        ForEach(summary.pills) { NutrientPill(model: $0) }
                    }
                } else {
                    NutrientBars(items: summary.items, cardHeight: size.height)
                }
            }
            .padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 24)
            .frame(width: size.width, alignment: .topLeading)
            .frame(minHeight: size.height, alignment: .topLeading)
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

/// The group's nutrients as the original bar chart: one fully rounded bar per nutrient, bottom-aligned, as tall as
/// its share of the target (never shorter than a flattened circle, so an empty one still reads), its short name
/// underneath. Moss when met, warm gray on track, Ember when low. Up to six to a row.
private struct NutrientBars: View {
    let items: [NutrientInfo]
    let cardHeight: CGFloat

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: 6).map { Array(items[$0..<min($0 + 6, items.count)]) }
        let height = cardHeight * (rows.count > 1 ? 0.21 : 0.4)   // the bars grow with the card
        VStack(alignment: .leading, spacing: 14) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(rows[r]) { n in
                        VStack(spacing: 7) {
                            NutrientBar(n: n, maxWidth: rows.count > 1 ? 26 : 34)
                                .frame(height: height)
                            Text(n.short).font(.mono(9, .semibold)).tracking(0.5).textCase(.uppercase)
                                .foregroundColor(.white.opacity(0.78))
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    // Short rows keep the same bar width as full ones.
                    ForEach(0..<(6 - rows[r].count) % 6, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                }
            }
        }
    }
}

private struct NutrientBar: View {
    let n: NutrientInfo
    var maxWidth: CGFloat = 34

    var body: some View {
        let share = min(max(n.share, 0), 1)
        GeometryReader { geo in
            let w = min(geo.size.width, maxWidth)
            let floor = w * 0.74
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Capsule().fill(fill(NutrientStatus(percent: n.share * 100)))
                    .frame(width: w, height: floor + (geo.size.height - floor) * share)
            }
            .frame(maxWidth: .infinity)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: share)
        .accessibilityHidden(true)
    }

    private func fill(_ s: NutrientStatus) -> LinearGradient {
        let colors: [Color] = switch s {
        case .met: [Color(hex: "#A9D293"), Color(hex: "#8FBA79")]
        case .low: [Color(hex: "#EC8D70"), Color(hex: "#E07C5F")]
        case .onTrack: [Color(hex: "#A4A39E"), Color(hex: "#8D8C87")]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
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
