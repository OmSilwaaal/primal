import SwiftUI
import SwiftData

/// The Data tab: a looping wheel of group cards (Macros, Vitamins, Minerals, Seasonal) on the app's shared photo
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
        let summaries = DataGroupSummary.make(from: buildNutrientList(from: today, goals: goals))
        let streak = StreakSummary.make(meals: meals, goal: goals.calories)
        DataScreen(summaries: summaries, streak: streak, centred: $centred, open: $open, zoom: zoom)
            .hidesTabBar(open != nil)
    }
}

/// The screen itself, from values, so previews can show it with the design's numbers.
private struct DataScreen: View {
    let summaries: [DataGroupSummary]
    let streak: StreakSummary
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
            // 304 × 440 on a 390 pt screen, scaled to the phone.
            let cardWidth = min(330, geo.size.width * 0.78)
            let card = CGSize(width: cardWidth, height: cardWidth * 1.45)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                        .padding(.horizontal, Bento.margin)
                        .padding(.top, 8)

                    DataWheel(summaries: summaries, card: card, centred: $centred, zoom: zoom) { open = $0 }
                        .frame(width: geo.size.width, height: card.height + 40)

                    if let current {
                        Group {
                            if current.isComingSoon {
                                Text("Seasonal eating guides are on the way")
                            } else {
                                Text("\(current.met) met · \(current.onTrack) on track · \(current.low) low")
                                    .contentTransition(.numericText())
                            }
                        }
                        .font(.mono(12, .semibold)).tracking(0.9).textCase(.uppercase)
                        .foregroundColor(Mono.label)
                        .accessibilityLabel(current.isComingSoon ? "Seasonal: coming soon"
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
            GroupDetailSheet(summary: summary)
                .zoomsFrom(id: summary.kind, in: zoom)
        }
    }
}

// MARK: - Wheel

/// The cards on an endless drum. `position` is a continuous index that never wraps, so every animation — a drag,
/// its momentum, a snap, a tap on a neighbour — interpolates smoothly; each card's place is found from it modulo
/// the count, which is what lets the end carry straight on to the start.
private struct DataWheel: View {
    let summaries: [DataGroupSummary]
    let card: CGSize
    @Binding var centred: DataGroupKind?
    let zoom: Namespace.ID
    let onOpen: (DataGroupSummary) -> Void

    @State private var position: Double = 0
    @State private var dragStart: Double?
    @State private var lastDragEnd = Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var count: Int { summaries.count }
    private var step: CGFloat { card.width * 0.62 }   // how far a drag moves to turn the wheel by one card
    private var index: Int { count == 0 ? 0 : ((Int(position.rounded()) % count) + count) % count }

    var body: some View {
        WheelStage(position: position, count: count, card: card, still: reduceMotion) { i in
            CarouselCard(summary: summaries[i], size: card) { tapped(i) }
                .zoomSource(id: summaries[i].kind, in: zoom)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(drag)
        .onAppear {
            if let k = centred, let i = summaries.firstIndex(where: { $0.kind == k }) { position = Double(i) }
        }
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
                let start = dragStart ?? position
                if dragStart == nil { dragStart = start }
                position = start - Double(value.translation.width / step)
            }
            .onEnded { value in
                let start = dragStart ?? position
                dragStart = nil
                lastDragEnd = .now
                // Throw: carry on by the predicted distance, at most one and a half cards, then settle on one.
                let thrown = Double((value.predictedEndTranslation.width - value.translation.width) / step)
                let target = (start - Double(value.translation.width / step) - max(-1.5, min(1.5, thrown))).rounded()
                withAnimation(settle) { position = target }
            }
    }

    private var settle: Animation? {
        // Long and critically damped: the card glides out from behind and settles without a bounce.
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.6, dampingFraction: 0.92)
    }

    /// The centred card opens; a neighbour turns the wheel to itself. Taps right after a swipe are the swipe's.
    private func tapped(_ i: Int) {
        guard Date.now.timeIntervalSince(lastDragEnd) > 0.25, dragStart == nil else { return }
        let rel = WheelStage<EmptyView>.wrap(Double(i) - position, count)
        if abs(rel) < 0.5 { onOpen(summaries[i]) } else { turn(by: rel.rounded()) }
    }

    private func turn(by cards: Double) {
        withAnimation(settle) { position = position.rounded() + cards }
    }
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
    private let peek: Double = 24

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
