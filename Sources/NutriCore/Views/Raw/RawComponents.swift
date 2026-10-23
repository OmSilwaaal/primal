import SwiftUI

// Shared building blocks used across the app. See DesignSystem/NatureBrutal.swift for the rules.

struct RawScreen<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            AppBackdrop(intensity: 0.7)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.section) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let subtitle { Text(subtitle).serifCaps(11).foregroundColor(.ncSecondary) }
                        Text(title).font(.brutal(34)).foregroundColor(.ncPrimary)
                            .lineLimit(2).minimumScaleFactor(0.7)
                            .accessibilityAddTraits(.isHeader)
                    }
                    content
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, 8)
                .padding(.bottom, 140)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// A section: serif label + hairline, then content. No box.
struct RawCard<Content: View>: View {
    var title: String? = nil
    var trailing: String? = nil
    var trailingColor: Color = .ncSecondary
    var index: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            if let title { SectionLabel(index: index, title: title, trailing: trailing, trailingColor: trailingColor) }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Tag: View {
    let text: String
    var color: Color = .ncSecondary
    var body: some View {
        Text(text)
            .font(.ui(size: 11, weight: .semibold)).tracking(0.8).textCase(.uppercase)
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .overlay(Rectangle().stroke(color.opacity(0.45), lineWidth: 1))
            .lineLimit(1)
    }
}

struct Disclaimer: View {
    var text = "Risk information only — nothing here clears food as safe or replaces medical advice. Reference values are general RDA/UL figures, not personalised."
    var body: some View {
        Text(text)
            .font(.serif(13)).italic()
            .foregroundColor(.ncSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Progress bar (thin). `band` and `value` are 0…1 fractions of the track.
struct BandGauge: View {
    let value: Double
    var band: ClosedRange<Double>? = nil
    var color: Color = .ncPrimary
    var height: CGFloat = 3
    var body: some View { LineGauge(value: value, band: band, tint: color, height: min(height, 4)) }
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
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.ui(size: 12, weight: .medium)) }
                Text(label).font(.mono(11, .semibold)).tracking(0.9).textCase(.uppercase)
            }
            .foregroundColor(selected ? .ncOnPrimary : .ncPrimary)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(selected ? Color.ncPrimary : Color.clear)
            .overlay(Rectangle().strokeBorder(Color.ncPrimary.opacity(selected ? 0 : 0.3), lineWidth: 1))
            .contentShape(Rectangle())
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
    var body: some View { Text(text).serifCaps(10).foregroundColor(.ncSecondary) }
}

/// Underlined text field — no box.
struct RawField: View {
    let title: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: title)
            TextField("", text: $text)
                .keyboardType(keyboard)
                .focused($focused)
                .font(.ui(size: 17)).foregroundColor(.ncPrimary)
                .frame(minHeight: 44)
            Rectangle().fill(Color.ncPrimary.opacity(focused ? 0.8 : 0.22)).frame(height: 1)
                .animation(.easeOut(duration: 0.2), value: focused)
        }
    }
}

/// 1…5 scale as a row of hairline cells.
struct ScalePicker: View {
    let title: String
    var lowLabel = "Low"
    var highLabel = "High"
    @Binding var value: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.ui(size: 16, weight: .medium)).foregroundColor(.ncPrimary)
                Spacer()
                Text(value == 0 ? "—" : "\(value)").font(.metric(18)).foregroundColor(.ncPrimary)
            }
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { n in
                    Button {
                        Haptics.selection()
                        withAnimation(.snappy(duration: 0.2)) { value = (value == n ? 0 : n) }
                    } label: {
                        Rectangle()
                            .fill(n <= value ? Color.ncPrimary : Color.clear)
                            .frame(minHeight: 44)
                            .overlay(Rectangle().stroke(Color.ncPrimary.opacity(n <= value ? 0 : 0.24), lineWidth: 1))
                            .overlay(Text("\(n)").font(.ui(size: 13, weight: .semibold))
                                .foregroundColor(n <= value ? .ncOnPrimary : .ncSecondary))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) \(n) of 5")
                }
            }
            HStack { Text(lowLabel); Spacer(); Text(highLabel) }
                .font(.ui(size: 12)).foregroundColor(.ncSecondary)
        }
    }
}

/// Index-style navigation row: number, title, detail, chevron, hairline underneath.
struct NavRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var badge: String? = nil
    var badgeColor: Color = .ncOrange
    var index: String? = nil
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                if let index {
                    Text(index).font(.mono(12)).foregroundColor(.ncSecondary)
                        .frame(width: 22, alignment: .leading)
                } else {
                    Image(systemName: icon).font(.ui(size: 16, weight: .regular)).foregroundColor(.ncPrimary)
                        .frame(width: 22)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.ui(size: 15, weight: .bold)).foregroundColor(.ncPrimary)
                    if let detail { Text(detail).font(.ui(size: 12)).foregroundColor(.ncSecondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 8)
                if let badge { Tag(text: badge, color: badgeColor) }
                Image(systemName: "arrow.up.right").font(.ui(size: 12, weight: .medium)).foregroundColor(.ncSecondary)
            }
            .frame(minHeight: 64)
            Hairline(opacity: 0.28)
        }
        .contentShape(Rectangle())
    }
}

extension RiskLevel {
    var color: Color {
        switch self {
        case .lower, .moderate: .ncPrimary
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
