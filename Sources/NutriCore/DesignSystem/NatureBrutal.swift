import SwiftUI

// MARK: - Vitalis design system: type, space, backdrop
//
// Three voices, used consistently:
//   • Display – Archivo Black for the wordmark and every number that matters.
//   • Body    – Helvetica-style system sans: bold 15 for names, regular for reading.
//   • Label   – IBM Plex Mono caps for section labels, units and data.
// Structure is square (radius 0) and divided by rules; anything that floats is glass.
// Every value carries its unit and goal. Tap targets are at least 44 pt.

enum Space {
    static let margin: CGFloat = 20
    static let section: CGFloat = 40     // between sections
    static let block: CGFloat = 20       // label → content, between blocks inside a section
    static let item: CGFloat = 12        // between rows/items
}

extension Font {
    /// The text style a design size scales with under Dynamic Type: the nearest one at or above it.
    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: return .caption2
        case ..<12.5: return .caption
        case ..<13.5: return .footnote
        case ..<15.5: return .subheadline
        case ..<16.5: return .callout
        case ..<19.5: return .body
        case ..<21: return .title3
        case ..<25: return .title2
        case ..<31: return .title
        default: return .largeTitle
        }
    }

    /// Sizes above this are display text (wordmarks, hero numbers). They're already large, and growing them
    /// further breaks the layout, so they stay fixed; everything at or below it scales with Dynamic Type.
    static let largestScalingSize: CGFloat = 40

    /// The system font (SF) at a design size that scales with Dynamic Type. Use instead of `.system(size:)`,
    /// which never scales. Same parameters, so call sites read the same.
    static func ui(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        // SwiftUI has no scaling `.system(size:)`, so text snaps to the nearest system text style (its default
        // size can differ from `size` by a point or two) and then scales with it.
        size > largestScalingSize
            ? .system(size: size, weight: weight, design: design)
            : .system(textStyle(for: size), design: design, weight: weight)
    }

    /// Archivo Black. Bundled in Resources/Fonts; falls back to a heavy expanded system face.
    static func display(_ size: CGFloat) -> Font {
        guard UIFont(name: "ArchivoBlack-Regular", size: size) != nil else {
            return .ui(size: size, weight: .black).width(.expanded)
        }
        return size > largestScalingSize
            ? .custom("ArchivoBlack-Regular", fixedSize: size)
            : .custom("ArchivoBlack-Regular", size: size, relativeTo: textStyle(for: size))
    }
    /// IBM Plex Mono for labels, units and tabular data. Scales with Dynamic Type.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black: name = "IBMPlexMono-SemiBold"
        case .medium: name = "IBMPlexMono-Medium"
        default: name = "IBMPlexMono"
        }
        return UIFont(name: name, size: size) != nil
            ? .custom(name, size: size, relativeTo: textStyle(for: size))
            : .ui(size: size, weight: weight, design: .monospaced)
    }
    /// Wordmark and titles.
    static func brutal(_ size: CGFloat, weight: Font.Weight = .black) -> Font { .display(size) }
    /// Hero numbers.
    static func metric(_ size: CGFloat) -> Font { .display(size).monospacedDigit() }
    /// Formerly a serif; the design system has no serif, so reading text is plain sans.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .ui(size: size, weight: weight)
    }
    static let ncTitle = Font.ui(size: 22, weight: .bold)
}

extension View {
    /// Mono caps for controls: 12 pt semibold, tracked .12em.
    func spacedCaps(_ size: CGFloat = 12, tracking: CGFloat? = nil) -> some View {
        self.font(.mono(size, .semibold)).tracking(tracking ?? size * 0.12).textCase(.uppercase)
    }
    /// Section label: Plex Mono 500 caps, tracked .16em. Kept under its old name for existing call sites.
    func serifCaps(_ size: CGFloat = 11, tracking: CGFloat? = nil) -> some View {
        self.font(.mono(size)).tracking(tracking ?? size * 0.16).textCase(.uppercase)
    }
    /// The design's label voice.
    func monoLabel(_ size: CGFloat = 11) -> some View {
        self.serifCaps(size).foregroundColor(.ncSecondary)
    }
}

/// The photographs behind every screen. One is picked each time the app launches, never the same as last time,
/// and used on every screen for that session. All are from Unsplash under the Unsplash License (free for
/// commercial use, no attribution required), cropped to 2:3 and darkened the same way.
enum Backdrop: String, CaseIterable {
    case forest, desert, ocean, fog, night

    var assetName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() + "Dark" }

    static let current: Backdrop = {
        let key = "lastBackdrop"
        let last = UserDefaults.standard.string(forKey: key).flatMap(Backdrop.init(rawValue:))
        let pick = allCases.filter { $0 != last }.randomElement() ?? .forest
        UserDefaults.standard.set(pick.rawValue, forKey: key)
        return pick
    }()
}

/// The session's darkened photograph (see `Backdrop`) behind every screen, with the design's top/bottom scrim.
struct AppBackdrop: View {
    var intensity: Double = 1
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.ncBg
                Image(Backdrop.current.assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    // Crop at 62% across rather than centred (the photo is 2:3, wider than a phone).
                    .offset(x: -max(0, geo.size.height * 2 / 3 - geo.size.width) * 0.12)
                    .opacity(intensity)
                    .clipped()
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .black.opacity(0.25), location: 0.4),
                    .init(color: .black.opacity(0.45), location: 0.75),
                    .init(color: .black.opacity(0.7), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                // Increase Contrast: the photo recedes further behind text.
                if contrast == .increased { Color.black.opacity(0.35) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}

/// The name in a heavy wide face, laid out at a fixed size and allowed to run past the right edge.
struct Wordmark: View {
    var text = "VITALIS"
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
                    Text(index).font(.mono(11)).foregroundColor(.ncSecondary)
                }
                Text(title).monoLabel()
                    .accessibilityAddTraits(.isHeader) // VoiceOver: jump between sections with the rotor
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing).font(.mono(12, .semibold)).tracking(0.96).textCase(.uppercase).foregroundColor(trailingColor)
                        .lineLimit(1)
                }
            }
            Rule()
        }
    }
}

/// 2 pt Paper rule that opens a list.
struct Rule: View {
    var body: some View { Rectangle().fill(Color.ncPrimary).frame(height: 2) }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text(caption).monoLabel()
                Spacer()
                accessory
            }
            .frame(minHeight: 44)
            Text(title).font(.ui(size: 30, weight: .bold)).foregroundColor(.ncPrimary)
                .accessibilityAddTraits(.isHeader)
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
                .font(.ui(size: 16, weight: .regular)).foregroundColor(.ncPrimary)
                .frame(width: 44, height: 44)
                .glass(.clear, in: Rectangle())
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
                    Text(unit.uppercased()).font(.mono(max(11, size * 0.22))).foregroundColor(.ncSecondary)
                }
            }
            if let caption { Text(caption).font(.ui(size: 14)).foregroundColor(.ncSecondary) }
        }
    }
}

/// Thin progress line with optional target band.
struct LineGauge: View {
    let value: Double
    var band: ClosedRange<Double>? = nil
    var tint: Color = .ncPrimary
    var height: CGFloat = 4
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

/// A row of values divided by vertical hairlines. At large text sizes, where the labels no longer fit
/// side by side, the values stack into rows divided by horizontal hairlines.
struct StatStrip: View {
    struct Item: Identifiable { let id = UUID(); let label: String; let value: String; var note: String? = nil; var progress: Double? = nil }
    let items: [Item]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    cell(item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, i == 0 ? 0 : 14)
                        .overlay(alignment: .leading) {
                            if i > 0 { Rectangle().fill(Color.ncPrimary.opacity(0.14)).frame(width: 1) }
                        }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    cell(item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .overlay(alignment: .top) {
                            if i > 0 { Rectangle().fill(Color.ncPrimary.opacity(0.14)).frame(height: 1) }
                        }
                }
            }
        }
    }

    private func cell(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // fixedSize: labels never break inside a word; ViewThatFits stacks the strip instead.
            Text(item.label).monoLabel().lineLimit(1).fixedSize()
            Text(item.value).font(.ui(size: 22)).foregroundColor(.ncPrimary)
                .lineLimit(1).minimumScaleFactor(0.55)
                .contentTransition(.numericText())
            if let p = item.progress { LineGauge(value: p, height: 2) }
            if let note = item.note { Text(note.uppercased()).font(.mono(11)).foregroundColor(.ncSecondary).lineLimit(1) }
        }
        .accessibilityElement(children: .combine)
    }
}
