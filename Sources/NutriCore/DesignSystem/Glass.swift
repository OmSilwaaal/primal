import SwiftUI

// MARK: - Glass materials
//
// Three weights, for anything that floats over content. Monochrome: grays and white only.
//   • clear  – white 8%, blur, 18% border, 20% top highlight. Buttons, segmented controls, round controls.
//   • tinted – blur + white 10%→3% gradient + ink #18181A at 50%, 16% border, 28% top highlight,
//              shadow black 35% r32 y12. Bento tiles, map header, toasts.
//   • thick  – ink #1E1E20 at 66% over a heavier blur, 20% border. Sheets, place detail.
// Reduce Transparency swaps the blur for solid #1C1C1E; Increase Contrast darkens the tint and lifts the border to 50%.

enum GlassStyle {
    case clear, tinted, thick

    fileprivate var material: Material { self == .thick ? .thinMaterial : .ultraThinMaterial }
    fileprivate var tint: Color {
        switch self {
        case .clear: Color.white.opacity(0.08)
        case .tinted: Mono.ink.opacity(0.5)
        case .thick: Mono.sheetInk.opacity(0.66)
        }
    }
    /// Top-to-bottom white wash that gives tiles their sheen.
    fileprivate var wash: (top: Double, bottom: Double)? { self == .tinted ? (0.10, 0.03) : nil }
    fileprivate var border: Double {
        switch self {
        case .clear: 0.18
        case .tinted: 0.16
        case .thick: 0.2
        }
    }
    fileprivate var highlight: Double {
        switch self {
        case .clear: 0.2
        case .tinted: 0.28
        case .thick: 0.25
        }
    }
    fileprivate var shadow: (opacity: Double, radius: CGFloat, y: CGFloat) {
        switch self {
        case .clear: (0, 0, 0)
        case .tinted: (0.35, 32, 12)
        case .thick: (0.5, 25, -10)
        }
    }
}

// On iOS 26 every weight is system Liquid Glass (navigation layer: controls, toasts, floating sheets):
//   • clear  – .clear, the most see-through variant; .interactive() on buttons (shimmer and bounce on touch).
//   • tinted – .clear with a light ink tint, so floating messages stay legible while the photo shows through.
//   • thick  – .regular with a light ink tint, for sheets that hold a lot of text.
// Glass can't sample glass, so anything inside a thick panel draws the see-through panel instead (`glassNested`).
// Glass that sits on a rotating wheel stays drawn too: rotation makes system glass morph.

extension EnvironmentValues {
    /// Set inside a system-glass panel: nested glass draws the see-through panel instead of more system glass.
    @Entry var glassNested = false
    /// Off where interactive glass would steal horizontal drags from a wheel next to it (it reacts ~24 pt out).
    @Entry var glassInteractive = true
}

private struct GlassModifier<S: InsettableShape>: ViewModifier {
    let style: GlassStyle
    let shape: S
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.glassNested) private var nested
    @Environment(\.glassInteractive) private var interactiveAllowed

    func body(content: Content) -> some View {
        if !reduceTransparency, contrast != .increased, #available(iOS 26.0, *) {
            let touch = interactive && interactiveAllowed
            switch style {
            case .clear:
                if nested {
                    content.liquidGlassPanel(in: shape)
                } else {
                    content.glassEffect(.clear.interactive(touch), in: shape)
                }
            case .tinted:
                content.glassEffect(.clear.tint(Mono.ink.opacity(0.25)).interactive(touch), in: shape)
            case .thick:
                content
                    .environment(\.glassNested, true)
                    .glassEffect(.regular.tint(Mono.sheetInk.opacity(0.3)), in: shape)
            }
        } else {
            drawn(content)
        }
    }

    private func drawn(_ content: Content) -> some View {
        let increased = contrast == .increased
        return content
            .background {
                if reduceTransparency {
                    // Reduce Transparency: an opaque surface instead of blur.
                    shape.fill(Mono.solid)
                } else {
                    shape.fill(style.material)
                        .overlay {
                            if let wash = style.wash {
                                shape.fill(LinearGradient(colors: [.white.opacity(wash.top), .white.opacity(wash.bottom)],
                                                          startPoint: .top, endPoint: .bottom))
                            }
                        }
                        .overlay(shape.fill(style.tint))
                        // Increase Contrast: a darker tint so text over the backdrop stays legible.
                        .overlay(shape.fill(Color.black.opacity(increased ? 0.35 : 0)))
                        .environment(\.colorScheme, .dark)
                }
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(increased ? 0.5 : style.border), lineWidth: 1)
                // Inner top highlight.
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(style.highlight), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.08)),
                    lineWidth: 1)
            }
            .shadow(color: .black.opacity(style.shadow.opacity), radius: style.shadow.radius, y: style.shadow.y)
    }
}

extension View {
    /// `interactive`: a tappable control; on iOS 26 its glass shimmers and bounces on touch.
    func glass<S: InsettableShape>(_ style: GlassStyle = .clear, in shape: S, interactive: Bool = false) -> some View {
        modifier(GlassModifier(style: style, shape: shape, interactive: interactive))
    }
    func glass(_ style: GlassStyle = .clear, interactive: Bool = false) -> some View {
        modifier(GlassModifier(style: style, shape: Rectangle(), interactive: interactive))
    }
}

/// Groups nearby glass so it samples the backdrop together and blends where pieces meet (GlassEffectContainer on
/// iOS 26; a plain pass-through before).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

extension View {
    /// Partial-height sheets: system Liquid Glass on iOS 26 (no custom background, per Apple); the thick ink before.
    @ViewBuilder func glassSheetBackground() -> some View {
        if #available(iOS 26.0, *) {
            self.environment(\.glassNested, true)
        } else {
            self.presentationBackground {
                Mono.sheetInk.opacity(0.66).background(.thinMaterial).environment(\.colorScheme, .dark)
            }
        }
    }
}

// MARK: - Liquid Glass panel

/// A see-through glass panel for content on the backdrop (bento tiles, Home's date pills): a faint white film, a
/// hairline rim with a top highlight, and the moving light. No blur and no system Liquid Glass, so the photo shows
/// through undistorted (system glass frosts it and lenses it at the edges). Legible because the backdrop itself is
/// already blurred and darkened. Reduce Transparency and Increase Contrast get an opaque surface.
private struct LiquidGlassPanel<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .background(Mono.solid, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(contrast == .increased ? 0.5 : 0.16), lineWidth: 1))
        } else {
            content
                // Clear like a sheet of glass: a barely-there film and a faint hairline edge; the moving light draws
                // the bright catch on whichever rim faces it.
                .glassSheen(in: shape)
                .background(shape.fill(Color.white.opacity(0.015)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        }
    }
}

extension View {
    func liquidGlassPanel<S: InsettableShape>(in shape: S) -> some View {
        modifier(LiquidGlassPanel(shape: shape))
    }
}

// MARK: - Buttons

/// Square clear-glass control with mono caps ("SEARCH", "BACK").
struct GlassButtonStyle: ButtonStyle {
    var height: CGFloat = 44
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mono(12, .semibold)).tracking(1.44).textCase(.uppercase)
            .foregroundColor(.ncPrimary)
            .padding(.horizontal, 16)
            .frame(minHeight: height)
            .glass(.clear, interactive: true)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

/// Text-only action in Mute mono caps ("SIGN OUT", "CANCEL").
struct TextButtonStyle: ButtonStyle {
    var color: Color = .ncSecondary
    var height: CGFloat = 44
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mono(12, .semibold)).tracking(1.68).textCase(.uppercase)
            .foregroundColor(color)
            .frame(minHeight: height)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// A 44 pt clear-glass circle for small header actions (Search, weather). Its contents keep a fixed size so
/// they always fit the dot; long-press shows them enlarged for people using large text.
struct GlassDotButtonStyle: ButtonStyle {
    var size: CGFloat = 44
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.ncPrimary)
            .frame(width: size, height: size)
            .glassSheen(in: Circle(), strength: 0.8)
            .glass(.clear, in: Circle(), interactive: true)
            .contentShape(Circle())
            .dynamicTypeSize(...DynamicTypeSize.large)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A full-width capsule of white-tinted Liquid Glass with dark caps text: the primary action on a glass screen
/// (Home's Log food). The moving light catches its rim like the other glass.
struct WhiteGlassButtonStyle: ButtonStyle {
    var height: CGFloat = 56
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.ui(size: 14, weight: .bold)).tracking(2.2).textCase(.uppercase)
            .foregroundColor(.ncOnPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: height)
            .glassSheen(in: Capsule(), strength: 0.9)
        return Group {
            if reduceTransparency {
                label.background(Color.ncPrimary, in: Capsule())
            } else if #available(iOS 26.0, *) {
                label.glassEffect(.regular.tint(Color.white.opacity(0.78)), in: Capsule())
            } else {
                label
                    .background(Color.white.opacity(0.8), in: Capsule())
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .contentShape(Capsule())
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
        .onChange(of: configuration.isPressed) { _, pressed in
            if pressed { Haptics.tap() }
        }
    }
}

extension ButtonStyle where Self == WhiteGlassButtonStyle {
    static var whiteGlass: WhiteGlassButtonStyle { WhiteGlassButtonStyle() }
}

extension ButtonStyle where Self == GlassDotButtonStyle {
    static var glassDot: GlassDotButtonStyle { GlassDotButtonStyle() }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle { GlassButtonStyle() }
}
extension ButtonStyle where Self == TextButtonStyle {
    static var text: TextButtonStyle { TextButtonStyle() }
}

// MARK: - Segmented control

/// Equal-width segments on clear glass; the selected one is a solid Paper block.
struct GlassSegmented<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var capsule = false
    var height: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let on = option.value == selection
                Button {
                    guard !on else { return }
                    Haptics.selection()
                    withAnimation(.easeOut(duration: 0.25)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.mono(12, .semibold)).tracking(1.2).textCase(.uppercase)
                        .foregroundColor(on ? .ncOnPrimary : .ncPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: height)
                        .background {
                            if on {
                                if capsule { Capsule().fill(Color.ncPrimary) } else { Rectangle().fill(Color.ncPrimary) }
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(capsule ? 5 : 4)
        .modifier(SegmentBackground(capsule: capsule))
    }
}

private struct SegmentBackground: ViewModifier {
    let capsule: Bool
    func body(content: Content) -> some View {
        if capsule {
            content.glass(.clear, in: Capsule())
        } else {
            content.glass(.clear)
        }
    }
}

// MARK: - Option chip

/// Square option: outline when off, solid Paper when on ("MODERATE", "BUTCHER").
struct OptionChip: View {
    let label: String
    let selected: Bool
    var glassy = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            Text(label)
                .font(.mono(glassy ? 12 : 11, .semibold)).tracking(glassy ? 1.2 : 0.9).textCase(.uppercase)
                .foregroundColor(selected ? .ncOnPrimary : .ncPrimary)
                .padding(.horizontal, glassy ? 16 : 14)
                .frame(minHeight: 44)
                .background {
                    if selected {
                        Rectangle().fill(Color.ncPrimary)
                    } else if glassy {
                        Rectangle().fill(.ultraThinMaterial).overlay(Color.white.opacity(0.08))
                    }
                }
                .overlay(Rectangle().strokeBorder(glassy ? Color.white.opacity(0.2) : Color.ncPrimary.opacity(0.3), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Nutrient row

enum IntakeStatus: Int, Comparable {
    case low, onTrack, met
    init(progress p: Double) { self = p >= 0.9 ? .met : p < 0.5 ? .low : .onTrack }
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var tag: String {
        switch self {
        case .met: "MET"
        case .low: "LOW"
        case .onTrack: "ON TRACK"
        }
    }
    var bar: Color {
        switch self {
        case .met: .ncMoss
        case .low: .ncEmber
        case .onTrack: .ncPrimary
        }
    }
    var tagColor: Color {
        switch self {
        case .met: .ncMoss
        case .low: .ncEmber
        case .onTrack: .ncSecondary
        }
    }
}

/// Name, status tag + percent, square bar coloured by status, value against goal.
struct NutrientRow: View {
    let name: String
    let current: Double
    let goal: Double
    let unit: String

    private var progress: Double { goal > 0 ? current / goal : 0 }
    private var pct: Int { Int((min(progress, 1) * 100).rounded()) }

    var body: some View {
        let status = IntakeStatus(progress: progress)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name).font(.ui(size: 15, weight: .bold)).foregroundColor(.ncPrimary)
                Spacer()
                Text("\(status.tag) · \(pct)%").font(.mono(11, .semibold)).tracking(1.1).foregroundColor(status.tagColor)
            }
            LineGauge(value: progress, tint: status.bar, height: 6)
            Text("\(Self.dec(current)) / \(Self.dec(goal)) \(unit.uppercased())")
                .font(.mono(12)).foregroundColor(.ncSecondary)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Hairline(opacity: 0.28) }
        .accessibilityElement(children: .combine)
    }

    /// 1 decimal below 10, whole numbers above, grouped above 100.
    static func dec(_ n: Double) -> String {
        n >= 100 ? Int(n.rounded()).formatted() : n >= 10 ? String(format: "%.0f", n) : String(format: "%.1f", n)
    }
}

// MARK: - Toast

/// App-wide confirmation shown at the top in tinted glass ("LOGGED — RIBEYE 250 G").
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()
    @Published private(set) var message: String?
    /// Positive moments (logged, welcome, target hit) carry the rune; errors and removals don't.
    @Published private(set) var branded = false
    private var hideTask: Task<Void, Never>?

    func show(_ text: String, branded: Bool = false) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            message = text.uppercased()
            self.branded = branded
        }
        if branded { BrandSound.play() }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { message = nil }
        }
    }
}

struct ToastOverlay: View {
    @ObservedObject var center = ToastCenter.shared
    var body: some View {
        VStack {
            if let message = center.message {
                HStack(spacing: 10) {
                    if center.branded {
                        AlgizMark().fill(Color.ncPrimary).frame(width: 11, height: 14).accessibilityHidden(true)
                    }
                    Text(message)
                        .font(.mono(12)).tracking(0.96)
                        .lineLimit(1)
                }
                    .foregroundColor(.ncPrimary)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .glass(.tinted)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Tab bar visibility

/// Screens set this to hide the floating tab bar while a sheet or overlay is up.
struct HidesTabBarKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    func hidesTabBar(_ hidden: Bool) -> some View { preference(key: HidesTabBarKey.self, value: hidden) }
}
