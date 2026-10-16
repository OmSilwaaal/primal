import SwiftUI

// MARK: - Nature × brutalist design system
//
// Three voices, used consistently:
//   • Brutal  – heavy, wide grotesque for the wordmark and every number that matters.
//   • Nature  – a quiet serif in widely spaced capitals for labels and captions, and for
//               qualitative headlines ("Mostly raw carnivore").
//   • Body    – plain system sans for reading.
// Surfaces are not boxed: sections sit on an out-of-focus foliage photograph and are divided by
// hairlines, with a strict 20pt margin and an 8pt spacing rhythm.

enum Space {
    static let margin: CGFloat = 20
    static let section: CGFloat = 40     // between sections
    static let block: CGFloat = 20       // label → content, between blocks inside a section
    static let item: CGFloat = 12        // between rows/items
}

extension Font {
    /// Heavy, wide grotesque for the wordmark and titles.
    static func brutal(_ size: CGFloat, weight: Font.Weight = .black) -> Font {
        .system(size: size, weight: weight).width(.expanded)
    }
    /// Numbers: wide, heavy, tabular so values don't jitter while animating.
    static func metric(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy).width(.expanded).monospacedDigit()
    }
    /// Serif for qualitative headlines and captions.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static let ncTitle = Font.serif(22)
}

extension View {
    /// Small spaced capitals (sans) — navigation and controls.
    func spacedCaps(_ size: CGFloat = 12, tracking: CGFloat = 1.8) -> some View {
        self.font(.system(size: size, weight: .medium)).tracking(tracking).textCase(.uppercase)
    }
    /// Serif spaced capitals — section labels and captions, like "W H E R E  B E A U T Y  G R O W S".
    func serifCaps(_ size: CGFloat = 12, tracking: CGFloat? = nil) -> some View {
        self.font(.serif(size)).tracking(tracking ?? size * 0.3).textCase(.uppercase)
    }
}

/// Out-of-focus foliage photograph, darkened so content stays readable, fading to black toward the bottom.
struct AppBackdrop: View {
    var intensity: Double = 1

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.ncBg
                Image("Foliage")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(intensity)
                    .clipped()
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.0), location: 0),
                    .init(color: .black.opacity(0.12), location: 0.3),
                    .init(color: .black.opacity(0.55), location: 0.62),
                    .init(color: .black.opacity(0.85), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}

/// The name in a heavy wide face, laid out at a fixed size and allowed to run past the right edge.
struct Wordmark: View {
    var text = "PRIMAL"
    var size: CGFloat = 56
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: size * 0.92)
            .overlay(alignment: .leading) {
                Text(text).font(.brutal(size)).foregroundColor(.ncPrimary)
                    .lineLimit(1).fixedSize()
                    .offset(x: -size * 0.05)
            }
            .accessibilityElement().accessibilityLabel(text)
    }
}

/// Section opener: optional index number, serif spaced-caps title, optional trailing note, then a hairline.
struct SectionLabel: View {
    var index: String? = nil
    let title: String
    var trailing: String? = nil
    var trailingColor: Color = .ncSecondary

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let index {
                    Text(index).font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundColor(.ncSecondary)
                }
                Text(title).serifCaps(12).foregroundColor(.ncPrimary)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing).font(.system(size: 12, weight: .medium)).foregroundColor(trailingColor)
                        .lineLimit(1)
                }
            }
            Hairline()
        }
    }
}

struct Hairline: View {
    var opacity: Double = 0.16
    var body: some View { Rectangle().fill(Color.ncPrimary.opacity(opacity)).frame(height: 1) }
}

/// Kept for older call sites.
struct RuleLabel: View {
    let text: String
    var body: some View { SectionLabel(title: text) }
}

/// Page title: serif caption (with an optional control on the right), then the big cropped title.
struct PageHeader<Accessory: View>: View {
    let title: String
    var caption: String = ""
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                Text(caption).serifCaps(11).foregroundColor(.ncPrimary.opacity(0.75))
                Spacer()
                accessory
            }
            .frame(minHeight: 44)
            Wordmark(text: title.uppercased(), size: 64)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PageHeader where Accessory == EmptyView {
    init(title: String, caption: String = "") {
        self.title = title; self.caption = caption; self.accessory = EmptyView()
    }
}

/// Square hairline icon button used in page headers.
struct HeaderIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .regular)).foregroundColor(.ncPrimary)
                .frame(width: 44, height: 44)
                .overlay(Rectangle().stroke(Color.ncPrimary.opacity(0.4), lineWidth: 1))
        }
        .smoothButton()
        .accessibilityLabel(label)
    }
}

/// Big number + unit + caption, the main way the app shows a value.
struct Metric: View {
    let value: String
    var unit: String = ""
    var caption: String? = nil
    var size: CGFloat = 56
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.metric(size)).foregroundColor(.ncPrimary)
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit).font(.serif(size * 0.32)).foregroundColor(.ncSecondary)
                }
            }
            if let caption { Text(caption).font(.system(size: 14)).foregroundColor(.ncSecondary) }
        }
    }
}

/// Thin progress line with optional target band.
struct LineGauge: View {
    let value: Double
    var band: ClosedRange<Double>? = nil
    var tint: Color = .ncPrimary
    var height: CGFloat = 3
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.ncPrimary.opacity(0.14))
                if let band {
                    Rectangle().fill(Color.ncPrimary.opacity(0.22))
                        .frame(width: geo.size.width * max(0, band.upperBound - band.lowerBound))
                        .offset(x: geo.size.width * band.lowerBound)
                }
                Rectangle().fill(tint)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
                    .animation(.smooth(duration: 0.6), value: value)
            }
        }
        .frame(height: height)
    }
}

/// A row of values divided by vertical hairlines.
struct StatStrip: View {
    struct Item: Identifiable { let id = UUID(); let label: String; let value: String; var note: String? = nil; var progress: Double? = nil }
    let items: [Item]
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.label).serifCaps(10).foregroundColor(.ncSecondary).lineLimit(1)
                    Text(item.value).font(.metric(22)).foregroundColor(.ncPrimary)
                        .lineLimit(1).minimumScaleFactor(0.55)
                        .contentTransition(.numericText())
                    if let p = item.progress { LineGauge(value: p, height: 2) }
                    if let note = item.note { Text(note).font(.system(size: 12)).foregroundColor(.ncSecondary).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, i == 0 ? 0 : 14)
                .overlay(alignment: .leading) {
                    if i > 0 { Rectangle().fill(Color.ncPrimary.opacity(0.14)).frame(width: 1) }
                }
            }
        }
    }
}
