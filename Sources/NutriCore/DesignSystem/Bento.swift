import SwiftUI

// MARK: - Monochrome Liquid Glass + bento
//
// Grayscale only: white ink on a near-black base, with grays between. Depth comes from blur, light edges and shadow,
// never hue. Status is told with words and fill length (a filled "Low" pill, an outlined "On track" pill), not colour.
//
// Layout: one large tile per screen, then 1×1 tiles in pairs. Each small tile holds one number, one label and one
// thin bar. Tiles are tinted glass (Glass.swift), 28 pt corners, 16 pt screen margin, 12 pt between tiles.

enum Mono {
    static let base = Color(hex: "#0A0A0B")
    /// Tinted-glass ink and the thick sheet's ink.
    static let ink = Color(hex: "#18181A")
    static let sheetInk = Color(hex: "#1E1E20")
    /// Reduce Transparency: glass becomes this solid surface.
    static let solid = Color(hex: "#1C1C1E")
    /// The backdrop's circles run between these two grays.
    static let grayLight = Color(hex: "#8A8A8F")
    static let grayDark = Color(hex: "#38383C")

    static let text = Color.white
    static let label = Color.white.opacity(0.8)
    static let track = Color.white.opacity(0.18)
    /// Text on a solid white fill (the active tab, "Low" pills, primary buttons).
    static let onWhite = Color(hex: "#0A0A0B")
}

enum Bento {
    static let margin: CGFloat = 16
    static let gap: CGFloat = 12
    static let radius: CGFloat = 28
    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
}

/// Which meal a time of day belongs to, for meal rows and "Add to Lunch". There's no stored meal type, so it's by
/// the clock: breakfast before 11, lunch before 4 pm, dinner before 9 pm, then snack.
enum MealSlot {
    static func name(for date: Date = .now) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11: "Breakfast"
        case 11..<16: "Lunch"
        case 16..<21: "Dinner"
        default: "Snack"
        }
    }
}

extension Font {
    /// Screen titles: 34 pt bold SF.
    static var bentoTitle: Font { .ui(size: 34, weight: .bold) }
    /// Key numbers, 22 to 64 pt semibold SF. Use with `.tracking(Font.bentoTracking(size))`.
    static func bentoNumber(_ size: CGFloat) -> Font { .ui(size: size, weight: .semibold) }
    static func bentoTracking(_ size: CGFloat) -> CGFloat { -size * 0.03 }
    /// Tile labels: 13 pt (never under 12) at 80% white.
    static var bentoLabel: Font { .ui(size: 13, weight: .medium) }
    static var bentoBody: Font { .ui(size: 15) }
}

// MARK: - Tile surface

extension View {
    /// A bento tile: content padded inside see-through glass with 28 pt corners, so the photo shows through, and the
    /// moving light (coloured from the photo) on its rim. Solid under Reduce Transparency / Increase Contrast.
    func bentoTile(padding: CGFloat = 16, art: LineArt? = nil, artPlacement: LineArt.Placement = .corner) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .lineArt(art, placement: artPlacement)
            .liquidGlassPanel(in: Bento.shape)
    }

    /// Faint line art inside a tile, behind its content, anchored to an edge and cropped by the tile's corners.
    @ViewBuilder func lineArt(_ art: LineArt?, placement: LineArt.Placement = .corner,
                              radius: CGFloat = Bento.radius) -> some View {
        if let art {
            self
                .background(alignment: placement.alignment) {
                    Image(art.rawValue).resizable().scaledToFit()
                        .frame(width: placement.size, height: placement.size)
                        .opacity(0.2)
                        .offset(placement.offset)
                        .accessibilityHidden(true)
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            self
        }
    }
}

/// The app's line drawings (Paper strokes), used faintly inside tiles: a little of the outdoors in each one.
enum LineArt: String {
    case leaf = "lines-leaf", sprig = "lines-sprig", sun = "lines-sun", water = "lines-water"

    struct Placement {
        var alignment: Alignment
        var size: CGFloat
        var offset: CGSize
        /// Bottom-right, partly off the tile (the sun rising out of the corner).
        static let corner = Placement(alignment: .bottomTrailing, size: 140, offset: CGSize(width: 34, height: 44))
        /// Across the right side, behind the number (water running through the tile).
        static let band = Placement(alignment: .trailing, size: 160, offset: CGSize(width: 44, height: 14))
    }
}

// MARK: - Bar

/// The tile bar: 6 pt, white fill on a white 18% track. Fill length is the only status signal on it.
struct BentoBar: View {
    let value: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Mono.track)
                Capsule().fill(Mono.text)
                    .frame(width: max(value > 0 ? height : 0, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.5), value: value)
        .accessibilityHidden(true)
    }
}

// MARK: - Status

/// Low under 60% of the daily target, Done at 100%, On track between.
enum BentoStatus {
    case low, onTrack, done

    init(progress: Double) {
        self = progress >= 1 ? .done : progress < 0.6 ? .low : .onTrack
    }

    var title: String {
        switch self {
        case .low: "Low"
        case .onTrack: "On track"
        case .done: "Done"
        }
    }
}

/// Low: a filled white pill with dark text. On track and Done: outlined pills (Done adds a check).
struct BentoStatusPill: View {
    let status: BentoStatus

    var body: some View {
        HStack(spacing: 4) {
            if status == .done { Image(systemName: "checkmark").font(.ui(size: 11, weight: .bold)) }
            Text(status.title).font(.ui(size: 12, weight: .semibold))
        }
        .foregroundColor(status == .low ? Mono.onWhite : Mono.text)
        .padding(.horizontal, 10).frame(height: 24)
        .background {
            if status == .low { Capsule().fill(Mono.text) }
        }
        .overlay {
            if status != .low { Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1) }
        }
        .fixedSize()
    }
}

// MARK: - Tile

/// One number, one label, one thin bar. `detail` is the quiet text after the number ("of 2.5 L").
struct BentoTile: View {
    let title: String
    let value: String
    var detail: String? = nil
    let progress: Double
    var status: BentoStatus? = nil
    var symbol: String? = nil
    var art: LineArt? = nil
    var artPlacement: LineArt.Placement = .corner

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.ui(size: 13, weight: .semibold)) }
                Text(title).font(.bentoLabel).lineLimit(1).minimumScaleFactor(0.85)
            }
            .foregroundColor(Mono.label)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(.bentoNumber(30)).tracking(Font.bentoTracking(30)).foregroundColor(Mono.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                if let detail {
                    Text(detail).font(.ui(size: 13)).foregroundColor(Mono.label).lineLimit(1).minimumScaleFactor(0.8)
                }
                if let status {
                    Spacer(minLength: 4)
                    BentoStatusPill(status: status).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                }
            }

            BentoBar(value: progress)
        }
        .bentoTile(art: art, artPlacement: artPlacement)
        .accessibilityElement(children: .combine)
        .accessibilityValue(status.map { $0.title } ?? "")
    }
}

/// Lays tiles out two to a row (one per row at accessibility text sizes).
struct BentoPair<Left: View, Right: View>: View {
    @ViewBuilder let left: () -> Left
    @ViewBuilder let right: () -> Right
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: Bento.gap) { left(); right() }
        } else {
            HStack(alignment: .top, spacing: Bento.gap) { left(); right() }
        }
    }
}

// MARK: - Round glass button

/// A 44 pt clear-glass circle for header and camera controls (profile, close, flash).
struct BentoRoundButtonStyle: ButtonStyle {
    var size: CGFloat = 44
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(size: 17, weight: .semibold))
            .foregroundColor(Mono.text)
            .frame(width: size, height: size)
            .glassSheen(in: Circle(), strength: 0.7)
            .glass(.clear, in: Circle(), interactive: true)
            .contentShape(Circle())
            .dynamicTypeSize(...DynamicTypeSize.large)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Primary action: solid white capsule, dark text. Secondary: clear glass capsule, white text.
struct BentoCapsuleButtonStyle: ButtonStyle {
    var solid = false
    var height: CGFloat = 52
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(size: 16, weight: .semibold))
            .foregroundColor(solid ? Mono.onWhite : Mono.text)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity).frame(minHeight: height)
            .background { if solid { Capsule().fill(Mono.text) } }
            .modifier(ClearCapsule(active: !solid))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }

    private struct ClearCapsule: ViewModifier {
        let active: Bool
        func body(content: Content) -> some View {
            if active { content.glass(.clear, in: Capsule(), interactive: true) } else { content }
        }
    }
}

extension ButtonStyle where Self == BentoRoundButtonStyle {
    static var bentoRound: BentoRoundButtonStyle { BentoRoundButtonStyle() }
}
extension ButtonStyle where Self == BentoCapsuleButtonStyle {
    static var bentoPrimary: BentoCapsuleButtonStyle { BentoCapsuleButtonStyle(solid: true) }
    static var bentoSecondary: BentoCapsuleButtonStyle { BentoCapsuleButtonStyle(solid: false) }
}

// MARK: - Segmented

/// Clear glass capsule with equal segments; the selected one is a solid white pill with dark text.
struct BentoSegmented<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let on = option.value == selection
                Button {
                    guard !on else { return }
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.ui(size: 14, weight: .semibold))
                        .foregroundColor(on ? Mono.onWhite : Mono.text)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background {
                            if on { Capsule().fill(Mono.text).matchedGeometryEffect(id: "pill", in: pill) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .glass(.clear, in: Capsule())
    }
}
