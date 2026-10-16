import SwiftUI

// Shared building blocks for the raw/carnivore and sunlight screens. Same tokens as the rest of the app.

struct RawScreen<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) { content }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ncBg, for: .navigationBar)
    }
}

struct RawCard<Content: View>: View {
    var title: String? = nil
    var trailing: String? = nil
    var trailingColor: Color = .ncSecondary
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack {
                    Text(title).font(.ncTitle).foregroundColor(.ncPrimary)
                    Spacer()
                    if let trailing {
                        Text(trailing).font(.system(size: 12, weight: .semibold)).foregroundColor(trailingColor)
                    }
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

struct Tag: View {
    let text: String
    var color: Color = .ncSecondary
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Rectangle())
    }
}

struct Disclaimer: View {
    var text = "Risk information only — nothing here clears food as safe or replaces medical advice. Reference values are general RDA/UL figures, not personalised."
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").font(.system(size: 12)).foregroundColor(.ncSecondary)
            Text(text).font(.system(size: 11)).foregroundColor(.ncSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4).padding(.top, 4)
    }
}

/// Horizontal gauge with an optional highlighted target band (values are 0…1 fractions of the track).
struct BandGauge: View {
    let value: Double          // 0…1
    var band: ClosedRange<Double>? = nil
    var color: Color = .ncPrimary
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.08))
                if let band {
                    Rectangle().fill(Color.ncGreen.opacity(0.22))
                        .frame(width: geo.size.width * (band.upperBound - band.lowerBound))
                        .offset(x: geo.size.width * band.lowerBound)
                }
                Rectangle().fill(color)
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
                    .animation(.smooth(duration: 0.6), value: value)
            }
        }
        .frame(height: height)
    }
}

struct Chip: View {
    let label: String
    var icon: String? = nil
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button {
            Haptics.selection()
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .medium)) }
                Text(label).font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(selected ? .ncOnPrimary : .ncPrimary)
            .padding(.horizontal, 12).frame(height: 34)
            .background(selected ? Color.ncPrimary : Color.ncSurfaceContHigh, in: Rectangle())
            .overlay(Rectangle().stroke(Color.white.opacity(selected ? 0 : 0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct ChipFlow<T: Identifiable & Hashable>: View {
    let items: [T]
    let label: (T) -> String
    var icon: ((T) -> String?)? = nil
    @Binding var selection: T
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items) { item in
                Chip(label: label(item), icon: icon?(item), selected: item == selection) { selection = item }
            }
        }
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing; rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; rowH = max(rowH, size.height)
        }
    }
}

struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundColor(.ncSecondary)
    }
}

struct RawField: View {
    let title: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: title)
            TextField("", text: $text)
                .keyboardType(keyboard)
                .font(.system(size: 15)).foregroundColor(.ncPrimary)
                .padding(.horizontal, 12).frame(height: 44)
                .background(Color.ncSurfaceContHigh, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
    }
}

/// 1…5 tap scale.
struct ScalePicker: View {
    let title: String
    var lowLabel = "Low"
    var highLabel = "High"
    @Binding var value: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.ncPrimary)
                Spacer()
                Text(value == 0 ? "—" : "\(value)/5").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundColor(.ncSecondary)
            }
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { n in
                    Button {
                        Haptics.selection()
                        withAnimation(.snappy(duration: 0.2)) { value = (value == n ? 0 : n) }
                    } label: {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(n == value ? Color.ncPrimary : Color.ncSurfaceContHigh)
                            .frame(height: 32)
                            .overlay(Text("\(n)").font(.system(size: 12, weight: .bold))
                                .foregroundColor(n == value ? .ncOnPrimary : .ncSecondary))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Text(lowLabel); Spacer(); Text(highLabel)
            }
            .font(.system(size: 10)).foregroundColor(.ncSecondary)
        }
    }
}

struct NavRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var badge: String? = nil
    var badgeColor: Color = .ncOrange
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundColor(.ncPrimary)
                .frame(width: 34, height: 34)
                .background(Color.ncSurfaceContHigh, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.ncPrimary)
                if let detail { Text(detail).font(.system(size: 12)).foregroundColor(.ncSecondary).lineLimit(1) }
            }
            Spacer()
            if let badge { Tag(text: badge, color: badgeColor) }
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundColor(.ncOutline)
        }
        .padding(12)
        .glassCard(radius: 3)
        .contentShape(Rectangle())
    }
}

extension RiskLevel {
    var color: Color {
        switch self {
        case .lower: .ncGreen
        case .moderate: .ncSky
        case .elevated: .ncOrange
        case .high: .ncError
        }
    }
}

/// Persisted raw/carnivore settings shared across screens.
enum RawSettings {
    static let modeKey = "dietMode"
    static let fatMinKey = "fatPctMin"
    static let fatMaxKey = "fatPctMax"
    static let startKey = "dietStartDate"
    static let sunGoalKey = "sunGoalMinutes"
    static let disclaimerKey = "rawDisclaimerAccepted"
}
