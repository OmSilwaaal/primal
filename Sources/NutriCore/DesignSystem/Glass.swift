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

private struct GlassModifier<S: InsettableShape>: ViewModifier {
    let style: GlassStyle
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if style == .clear, !reduceTransparency, contrast != .increased, #available(iOS 26.0, *) {
            // Clear controls are real, see-through Liquid Glass on iOS 26.
            content.glassEffect(.clear, in: shape)
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
    func glass<S: InsettableShape>(_ style: GlassStyle = .clear, in shape: S) -> some View {
        modifier(GlassModifier(style: style, shape: shape))
    }
    func glass(_ style: GlassStyle = .clear) -> some View {
        modifier(GlassModifier(style: style, shape: Rectangle()))
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
                .glassSheen(in: shape)
                .background(shape.fill(Color.white.opacity(0.04)))
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.08)),
                        lineWidth: 1)
                }
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
            .glass(.clear)
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
            .glass(.clear, in: Circle())
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
