import SwiftUI
import SwiftData
import QuartzCore

/// The Data tab: a looping wheel of group cards (Macros, Vitamins, Minerals, Raw, Seasonal) on the app's shared photo
/// backdrop. One card faces you with its neighbours turned away on either side; swiping past the last card carries
/// straight on to the first. Under it, the centred group's counts, then the daily streak. Tapping the centred card
/// zooms it into its detail sheet. Everything comes from today's meals, the profile's targets and the repo's scoring.
struct MicronutrientsView: View {
    @Query private var meals: [MealEntry]
    @Query private var profiles: [UserProfile]
    @State private var centred: DataGroupKind? = .macros
    @State private var open: DataGroupSummary?
    @Namespace private var zoom

    init() {
        // Enough history for the streak.
        let start = Calendar.current.date(byAdding: .day, value: -60, to: Calendar.current.startOfDay(for: .now)) ?? .now
        _meals = Query(filter: #Predicate<MealEntry> { $0.date >= start })
    }

    private var goals: NutrientGoals { profiles.first.map(NutrientGoals.from) ?? .default }

    var body: some View {
        let today = meals.filter { Calendar.current.isDateInToday($0.date) }
        let season = SeasonalGuide.currentSeason
        let summaries = DataGroupSummary.make(from: buildNutrientList(from: today, goals: goals)
                                                  + buildRawList(from: today, isMale: profiles.first?.isMale ?? true),
                                              season: season.name,
                                              seasonal: SeasonalGuide.picks(for: season, meals: meals))
        let streak = StreakSummary.make(meals: meals, goal: goals.calories)
        DataScreen(summaries: summaries, streak: streak, meals: today, centred: $centred, open: $open, zoom: zoom)
            .hidesTabBar(open != nil)
    }
}

/// The screen itself, from values, so previews can show it with the design's numbers.
private struct DataScreen: View {
    let summaries: [DataGroupSummary]
    let streak: StreakSummary
    /// Today's meals, for each nutrient's breakdown by food in the detail sheet.
    var meals: [MealEntry] = []
    @Binding var centred: DataGroupKind?
    @Binding var open: DataGroupSummary?
    let zoom: Namespace.ID

    /// Its own header rather than the other tabs' plain title: the ᛉ beside today's date and season over
    /// "Nutrients" in the cards' display face.
    private var header: some View {
        let date = Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let season = Season(date: .now, latitude: nil).name
        return HStack(alignment: .center, spacing: 12) {
            AlgizMark().fill(Color.ncPrimary)
                .frame(width: 22, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(date) · \(season)")
                    .font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase)
                    .foregroundColor(Mono.label)
                Text("Nutrients").font(.display(30)).foregroundColor(Mono.text)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var current: DataGroupSummary? { summaries.first { $0.kind == centred } ?? summaries.first }

    var body: some View {
        GeometryReader { geo in
            // Nearly the full width: 335 × 452 on a 390 pt screen, with just the neighbours' edges either side.
            let cardWidth = min(380, geo.size.width * 0.86)
            let card = CGSize(width: cardWidth, height: cardWidth * 1.35)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                        .padding(.horizontal, Bento.margin)
                        .padding(.top, 8)

                    DataWheel(summaries: summaries, card: card, centred: $centred, zoom: zoom) { open = $0 }
                        .frame(width: geo.size.width, height: card.height + 40)

                    if let current {
                        Group {
                            if current.kind == .raw, let raw = current.items.first(where: { $0.id == "raw" }),
                               let organ = current.items.first(where: { $0.id == "org" }) {
                                Text("\(raw.goal > 0 ? Int((raw.current / raw.goal * 100).rounded()) : 0)% eaten raw · \(Int(organ.current)) g organ meat")
                                    .contentTransition(.numericText())
                            } else if current.isSeasonal {
                                Text("\(current.seasonalEaten) of \(current.seasonal.count) in season · last \(SeasonalGuide.window) days")
                                    .contentTransition(.numericText())
                            } else {
                                Text("\(current.met) met · \(current.onTrack) on track · \(current.low) low")
                                    .contentTransition(.numericText())
                            }
                        }
                        .font(.mono(12, .semibold)).tracking(0.9).textCase(.uppercase)
                        .foregroundColor(Mono.label)
                        .accessibilityLabel(current.kind == .raw ? "Raw: today's raw share and organ meat"
                            : current.isSeasonal
                            ? "Seasonal: \(current.seasonalEaten) of \(current.seasonal.count) in-season foods eaten in the last \(SeasonalGuide.window) days"
                            : "\(current.kind.title): \(current.met) met, \(current.onTrack) on track, \(current.low) low")
                    }

                    StreakCard(streak: streak)
                        .padding(.horizontal, Bento.margin)
                        .padding(.top, 6)
                }
                .padding(.bottom, 130)   // clear of the tab bar
            }
        }
        .sheet(item: $open) { summary in
            GroupDetailSheet(summary: summary, meals: meals)
                .zoomsFrom(id: summary.kind, in: zoom)
        }
    }
}

// MARK: - Wheel

/// The cards on an endless drum. `position` is a continuous index that never wraps, so every animation — a drag,
/// its momentum, a snap, a tap on a neighbour — interpolates smoothly; each card's place is found from it modulo
/// the count, which is what lets the end carry straight on to the start.
struct DataWheel: View {
    let summaries: [DataGroupSummary]
    let card: CGSize
    @Binding var centred: DataGroupKind?
    let zoom: Namespace.ID
    let onOpen: (DataGroupSummary) -> Void

    @State private var physics = WheelPhysics()
    @State private var dragStart: Double?
    @State private var lastDragEnd = Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var count: Int { summaries.count }
    private var step: CGFloat { card.width * 0.62 }   // how far a drag moves to turn the wheel by one card
    private var index: Int { count == 0 ? 0 : ((Int(position.rounded()) % count) + count) % count }
    private var position: Double { physics.position }

    var body: some View {
        WheelStage(position: position, count: count, card: card, still: reduceMotion) { i in
            CarouselCard(summary: summaries[i], size: card) { tapped(i) }
                .zoomSource(id: summaries[i].kind, in: zoom)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(drag)
        .onAppear {
            if let k = centred, let i = summaries.firstIndex(where: { $0.kind == k }) { physics.jump(to: Double(i)) }
            SceneMixer.shared.scenes = summaries.map(\.kind.scene)
            physics.onFrame = { SceneMixer.shared.position = $0 }   // the scene rides the same motion, frame by frame
            SceneMixer.shared.position = physics.position
        }
        .onDisappear { physics.stop() }
        .onChange(of: index) { _, new in
            Haptics.selection()
            if summaries.indices.contains(new) { centred = summaries[new].kind }
        }
        .accessibilityElement(children: .contain)
        .accessibilityScrollAction { edge in
            turn(by: edge == .leading ? -1 : 1)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                // Grabbing mid-glide starts from where the cards are now, not from where they were heading.
                let start = dragStart ?? physics.grab()
                if dragStart == nil { dragStart = start }
                physics.follow(start - Double(value.translation.width / step))
            }
            .onEnded { value in
                let start = dragStart ?? physics.position
                dragStart = nil
                lastDragEnd = .now
                let here = start - Double(value.translation.width / step)
                // The finger's speed at release (cards per second), so the settle continues the same motion.
                let velocity = -Double(value.velocity.width / step)
                physics.release(to: Self.target(from: start, to: here, velocity: velocity), velocity: velocity,
                                instant: reduceMotion)
            }
    }

    /// Where a swipe lands: always one card at most, like turning a page — the cards are nearly the screen's width,
    /// so skipping two on a quick flick feels like a jump. A flick (over 0.8 cards a second) or a drag past a third of
    /// a card goes to the neighbour in that direction; anything less springs back.
    static func target(from start: Double, to here: Double, velocity: Double) -> Double {
        let origin = start.rounded()
        let moved = here - origin
        if abs(velocity) > 0.8 { return origin + (velocity > 0 ? 1 : -1) }
        if abs(moved) > 0.33 { return origin + (moved > 0 ? 1 : -1) }
        return origin
    }

    /// The centred card opens; a neighbour turns the wheel to itself. Taps right after a swipe are the swipe's.
    private func tapped(_ i: Int) {
        guard Date.now.timeIntervalSince(lastDragEnd) > 0.25, dragStart == nil else { return }
        let rel = WheelStage<EmptyView>.wrap(Double(i) - position, count)
        if abs(rel) < 0.5 { onOpen(summaries[i]) } else { turn(by: rel.rounded()) }
    }

    private func turn(by cards: Double) {
        physics.release(to: physics.target.rounded() + cards, velocity: physics.velocity, instant: reduceMotion)
    }
}

/// The wheel's motion, run frame by frame on the display's own clock: a critically damped spring towards the card
/// it should settle on. Because it owns both position and velocity, a release continues at the finger's speed and a
/// grab mid-glide starts exactly where the cards are — neither of which SwiftUI's animations can do.
@MainActor @Observable
final class WheelPhysics {
    private(set) var position: Double = 0
    @ObservationIgnored private(set) var velocity: Double = 0
    @ObservationIgnored private(set) var target: Double = 0
    /// Called every frame with the new position (the backdrop's scene crossfade follows it).
    @ObservationIgnored var onFrame: ((Double) -> Void)?
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var last: CFTimeInterval = 0
    @ObservationIgnored private var dragging = false
    @ObservationIgnored private var samples: [(t: CFTimeInterval, p: Double)] = []

    /// Spring stiffness (rad/s): about half a second to settle on the next card, with no overshoot.
    private let omega = 10.0

    func jump(to value: Double) {
        stopLink()
        position = value; target = value; velocity = 0
        onFrame?(value)
    }

    /// Takes hold of the wheel where it is now; returns that position.
    func grab() -> Double {
        dragging = true
        target = position
        velocity = 0
        samples = []
        stopLink()
        return position
    }

    /// While the finger is down the wheel goes exactly where the finger puts it.
    func follow(_ value: Double) {
        let now = CACurrentMediaTime()
        samples.append((now, value))
        samples.removeAll { now - $0.t > 0.1 }
        position = value
        onFrame?(value)
    }

    func release(to newTarget: Double, velocity v: Double, instant: Bool = false) {
        let wasDragging = dragging
        dragging = false
        target = newTarget
        if instant { jump(to: newTarget); return }
        // After a drag, the measured speed over its last 0.1 s is steadier than one gesture event's.
        if wasDragging, samples.count >= 2, let a = samples.first, let b = samples.last, b.t - a.t > 0.008 {
            velocity = (b.p - a.p) / (b.t - a.t)
        } else {
            velocity = v
        }
        samples = []
        startLink()
    }

    func stop() { stopLink() }

    private func startLink() {
        guard link == nil else { return }
        let link = CADisplayLink(target: WheelLinkProxy(self), selector: #selector(WheelLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        last = 0
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    fileprivate func tick(_ link: CADisplayLink) {
        guard !dragging else { stopLink(); return }
        let now = link.targetTimestamp
        let dt = last == 0 ? 1.0 / 120 : min(1.0 / 30, max(1.0 / 240, now - last))
        last = now
        if advance(by: dt) { stopLink() }
    }

    /// Moves the spring on by `dt` seconds; true once it has settled on the target.
    @discardableResult
    func advance(by dt: Double) -> Bool {
        // Critically damped spring (a = ω²(target − x) − 2ωv), in small steps so it's exact at any frame rate.
        let steps = max(1, Int((dt * 240).rounded(.up)))
        let h = dt / Double(steps)
        var p = position, v = velocity
        for _ in 0..<steps {
            let a = omega * omega * (target - p) - 2 * omega * v
            v += a * h
            p += v * h
        }
        let settled = abs(target - p) < 0.0005 && abs(v) < 0.005
        if settled { p = target; v = 0 }
        velocity = v
        position = p
        onFrame?(p)
        return settled
    }
}

/// CADisplayLink retains its target; this keeps it from retaining the wheel.
private final class WheelLinkProxy {
    weak var physics: WheelPhysics?
    init(_ physics: WheelPhysics) { self.physics = physics }
    @MainActor @objc func tick(_ link: CADisplayLink) { physics?.tick(link) }
}

/// Lays the cards out for a given position: the centred card full size, and on each side a smaller neighbour
/// tucked behind it so only its outer edge shows. Turning, a card slides out from behind, passes beside the
/// centre card at its widest and settles in front, like a card drawn from a deck. Animatable on `position`, so
/// SwiftUI interpolates the position itself and recomputes every card per frame — not each card's offset,
/// which would sweep the long way round when a card wraps from one side to the other.
private struct WheelStage<Card: View>: View, Animatable {
    var position: Double
    let count: Int
    let card: CGSize
    let still: Bool
    @ViewBuilder let content: (Int) -> Card

    /// Neighbours' size against the centred card, as in the reference: about three quarters.
    private let sideScale = 0.77
    /// How much of a neighbour shows past the centred card's edge.
    private let peek: Double = 14

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    /// `value` folded into −count/2 ..< count/2.
    static func wrap(_ value: Double, _ count: Int) -> Double {
        guard count > 0 else { return 0 }
        let n = Double(count)
        var r = value.truncatingRemainder(dividingBy: n)
        if r >= n / 2 { r -= n }
        if r < -n / 2 { r += n }
        return r
    }

    private struct Place { var rel, x, scale, opacity: Double }

    private func place(_ i: Int) -> Place {
        let w = Double(card.width)
        // A neighbour's centre, so its outer edge sits `peek` past the centred card's.
        let side = w * (1 - sideScale) / 2 + peek
        // How far a moving card swings out at the halfway point, so the two passing cards clear each other
        // when they swap which one is in front.
        let swing = w * 0.3
        let rel = Self.wrap(Double(i) - position, count)
        let a = abs(rel), sign: Double = rel < 0 ? -1 : 1
        if still { return Place(rel: rel, x: rel * (w + 16), scale: 1, opacity: a < 0.5 ? 1 : 0) }
        let x = a <= 1 ? sign * (side * a + swing * sin(.pi * a))
                       : sign * (side + (a - 1) * side * 0.4)   // further cards tuck in behind and fade
        let scale = 1 - (1 - sideScale) * min(a, 1) - 0.1 * max(0, min(a - 1, 1))
        return Place(rel: rel, x: x, scale: scale, opacity: a <= 1 ? 1 : max(0, 1 - (a - 1) * 2.5))
    }

    var body: some View {
        let places = (0..<count).map(place)
        let radius = 58 * card.width / 270
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let p = places[i], a = abs(p.rel)
                // Cards in front of this one: their shapes are cut out of it, so the frosted glass of a card
                // never shows the card tucked behind it — only the edge that peeks out is drawn.
                let front = places.indices.filter { abs(places[$0].rel) < a && places[$0].opacity > 0.01 }
                content(i)
                    .scaleEffect(p.scale)
                    .brightness(-0.06 * min(a, 1))
                    .opacity(p.opacity)
                    .offset(x: p.x)
                    .mask {
                        ZStack {
                            Rectangle().padding(-400)
                            ForEach(front, id: \.self) { j in
                                RoundedRectangle(cornerRadius: radius * places[j].scale, style: .continuous)
                                    .frame(width: card.width * places[j].scale, height: card.height * places[j].scale)
                                    .offset(x: places[j].x)
                                    .blendMode(.destinationOut)
                            }
                        }
                        .compositingGroup()
                    }
                    .zIndex(-a)
                    .allowsHitTesting(a < 1.2)
                    .accessibilityHidden(a > 0.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
private struct DataScreenPreview: View {
    @State private var centred: DataGroupKind? = .macros
    @State private var open: DataGroupSummary?
    @Namespace private var zoom
    var body: some View {
        DataScreen(summaries: DataPreview.summaries, streak: DataPreview.streak, centred: $centred, open: $open, zoom: zoom)
    }
}

#Preview("Data · design numbers") {
    DataScreenPreview().preferredColorScheme(.dark)
}

#Preview("Data · sample store") {
    MicronutrientsView()
        .modelContainer(VitalisPreviewData.container)
        .preferredColorScheme(.dark)
}
#endif
