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

    private var current: DataGroupSummary? { summaries.first { $0.kind == centred } ?? summaries.first }

    var body: some View {
        GeometryReader { geo in
            // 270 × 400 on a 390 pt screen, scaled to the phone.
            let cardWidth = min(270, geo.size.width * 0.69)
            let card = CGSize(width: cardWidth, height: cardWidth * 400 / 270)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    // The same title as Home's "Today" and the other tabs.
                    Text("Data").font(.bentoTitle).foregroundColor(Mono.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Bento.margin)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 8)

                    DataWheel(summaries: summaries, card: card, centred: $centred, zoom: zoom) { open = $0 }
                        .frame(width: geo.size.width, height: card.height + 60)

                    if let current {
                        Group {
                            if current.isComingSoon {
                                Text("Seasonal eating guides are on the way")
                            } else {
                                Text("\(current.met) met · \(current.onTrack) on track · \(current.low) low")
                                    .contentTransition(.numericText())
                            }
                        }
                        .font(.outermost(15)).foregroundColor(Mono.label)
                        .grained()
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
        // A whisper of grain over the whole page, so it shares the cards' printed texture.
        .overlay { GrainLayer(opacity: 0.05, blend: .overlay).ignoresSafeArea().allowsHitTesting(false) }
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
    private var step: CGFloat { card.width * 0.78 }   // how far one card turns the wheel
    private var index: Int { count == 0 ? 0 : ((Int(position.rounded()) % count) + count) % count }

    var body: some View {
        WheelStage(position: position, count: count, step: step, still: reduceMotion) { i in
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
        reduceMotion ? .easeOut(duration: 0.2) : .interpolatingSpring(mass: 1, stiffness: 170, damping: 24)
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

/// Lays the cards round the drum for a given position. Animatable on `position`, so SwiftUI interpolates the
/// position itself and recomputes every card per frame — not each card's offset, which would sweep the long way
/// round when a card wraps from one side to the other.
private struct WheelStage<Card: View>: View, Animatable {
    var position: Double
    let count: Int
    let step: CGFloat
    let still: Bool
    @ViewBuilder let content: (Int) -> Card

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

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let rel = Self.wrap(Double(i) - position, count)
                let d = min(abs(rel), 2)
                // Past one card away, a card tucks behind its neighbour and fades, so only one peeks on each side.
                let x = still ? rel * Double(step) * 1.1
                              : (abs(rel) <= 1 ? rel : (rel > 0 ? 1 : -1) * (1 + (abs(rel) - 1) * 0.35)) * Double(step)
                content(i)
                    .scaleEffect(still ? 1 : 1 - 0.14 * min(d, 1.4))
                    .rotation3DEffect(.degrees(still ? 0 : -rel * 22), axis: (0, 1, 0), anchor: .center, perspective: 0.55)
                    .brightness(-0.12 * min(d, 1))
                    .opacity(d <= 1.2 ? 1 : max(0, 1 - (d - 1.2) * 2))
                    .offset(x: x)
                    .zIndex(-abs(rel))
                    .allowsHitTesting(d < 1.3)
                    .accessibilityHidden(d > 0.5)
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
