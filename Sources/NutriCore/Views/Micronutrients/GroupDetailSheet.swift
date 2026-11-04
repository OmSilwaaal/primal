import SwiftUI

/// A group in full, as a large sheet tinted with the group colour: "Today · N items", the name, the dot-matrix
/// score and a close button; Met / On track / Low counters; then every item, lowest percent first so what needs
/// attention leads, the lowest row tinted Ember. Overall lists every nutrient.
struct GroupDetailSheet: View {
    let summary: DataGroupSummary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var kind: DataGroupKind { summary.kind }

    var body: some View {
        let rows = summary.items.sorted { $0.share < $1.share }
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today · \(summary.items.count) items").font(.mono(11, .semibold)).tracking(0.88)
                        .textCase(.uppercase).foregroundColor(Mono.label)
                    Text(kind.title).font(.ui(size: 28, weight: .bold)).foregroundColor(.white)
                        .accessibilityAddTraits(.isHeader)
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        DotMatrixText(text: "\(summary.score)", pitch: 3)
                        Text("/ 100").font(.mono(11, .semibold)).foregroundColor(.white.opacity(0.8))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Score \(summary.score) out of 100")
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.ui(size: 15, weight: .semibold)).foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .glass(.clear, in: Circle(), interactive: true)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            HStack(spacing: 0) {
                counter(.ncMoss, summary.met, "Met")
                counter(.ncPrimary, summary.onTrack, "On track")
                counter(.ncEmber, summary.low, "Low")
            }

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, n in
                        row(n, emphasised: i == 0)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .padding(.horizontal, 20).padding(.top, 24)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground { background }
        .presentationCornerRadius(Bento.radius)
    }

    @ViewBuilder private var background: some View {
        if reduceTransparency {
            kind.base.ignoresSafeArea()
        } else {
            ZStack {
                kind.base.opacity(0.85)
                RadialGradient(colors: [kind.color.opacity(0.32), .clear], center: .top, startRadius: 0, endRadius: 420)
            }
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea()
        }
    }

    private func counter(_ color: Color, _ n: Int, _ word: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text("\(n)").font(.display(22)).foregroundColor(.white)
            }
            Text(word).font(.mono(11, .semibold)).tracking(0.66).textCase(.uppercase).foregroundColor(Mono.label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func row(_ n: NutrientInfo, emphasised: Bool) -> some View {
        let pct = n.share * 100
        let status = NutrientStatus(percent: pct)
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(status.color).frame(width: 8, height: 8)
                Text(n.name).font(.ui(size: 15, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                Text("\(NutrientRow.dec(n.current)) / \(NutrientRow.dec(n.goal)) \(n.unit)")
                    .font(.mono(11)).foregroundColor(Mono.label).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                Text("\(Int(pct.rounded()))%").font(.display(15)).foregroundColor(.white).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(status.color).frame(width: geo.size.width * min(max(n.share, 0), 1))
                }
            }
            .frame(height: 5)
        }
        .padding(14)
        .background {
            shape.fill(emphasised ? Color.ncEmber.opacity(0.18) : Color.white.opacity(0.05))
        }
        .overlay {
            shape.strokeBorder(emphasised ? Color.ncEmber.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(n.name)
        .accessibilityValue("\(NutrientRow.dec(n.current)) of \(NutrientRow.dec(n.goal)) \(n.unit), \(Int(pct.rounded())) percent, \(status.word)")
    }
}

#if DEBUG
#Preview("Sheet · Vitamins") {
    Color.black.sheet(isPresented: .constant(true)) { GroupDetailSheet(summary: DataPreview.summaries[2]) }
        .preferredColorScheme(.dark)
}

#Preview("Sheet · Overall") {
    Color.black.sheet(isPresented: .constant(true)) { GroupDetailSheet(summary: DataPreview.summaries[0]) }
        .preferredColorScheme(.dark)
}
#endif
