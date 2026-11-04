import SwiftUI
import SwiftData

/// The Data tab: a swipeable carousel of four group cards (Overall, Macros, Vitamins, Minerals) on a near-black dot
/// grid with a soft Moss glow. One card sits centred with its neighbours peeking in, smaller; under it, the centred
/// group's Met / On track / Low counts and page dots; then the daily streak. Tapping a card zooms it into its
/// detail sheet. Everything comes from today's logged meals, the profile's targets and the repo's scoring.
struct MicronutrientsView: View {
    @Query private var meals: [MealEntry]
    @Query private var profiles: [UserProfile]
    @State private var centred: DataGroupKind? = .overall
    @State private var open: DataGroupSummary?
    @Namespace private var zoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var current: DataGroupSummary? { summaries.first { $0.kind == (centred ?? .overall) } ?? summaries.first }

    var body: some View {
        GeometryReader { geo in
            // 270 × 400 on a 390 pt screen, scaled to the phone.
            let cardWidth = min(270, geo.size.width * 0.69)
            let card = CGSize(width: cardWidth, height: cardWidth * 400 / 270)
            ZStack {
                DataBackdrop()
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        Text("Data").font(.display(22)).foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 8)

                        carousel(card: card, width: geo.size.width)

                        if let current {
                            Text("\(current.met) met · \(current.onTrack) on track · \(current.low) low")
                                .font(.mono(12, .semibold)).tracking(0.9).textCase(.uppercase)
                                .foregroundColor(Mono.label)
                                .contentTransition(.numericText())
                                .accessibilityLabel("\(current.kind.title): \(current.met) met, \(current.onTrack) on track, \(current.low) low")
                        }
                        dots

                        StreakCard(streak: streak)
                            .padding(.horizontal, Bento.margin)
                            .padding(.top, 6)
                    }
                    .padding(.bottom, 130)   // clear of the tab bar
                }
            }
        }
        .sheet(item: $open) { summary in
            GroupDetailSheet(summary: summary)
                .zoomsFrom(id: summary.kind, in: zoom)
        }
        .onChange(of: centred) { _, _ in Haptics.selection() }
    }

    // MARK: Carousel

    private func carousel(card: CGSize, width: CGFloat) -> some View {
        let still = reduceMotion   // captured, so the transition closure doesn't read view state
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(summaries) { summary in
                    CarouselCard(summary: summary, size: card) { open = summary }
                        .zoomSource(id: summary.kind, in: zoom)
                        .id(summary.kind)
                        // The centred card full size; neighbours smaller, a touch fainter, pushed towards the edge.
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            let d = min(1, abs(phase.value))
                            return content
                                .scaleEffect(still ? 1 : 1 - 0.2 * d)
                                .opacity(1 - 0.1 * d)
                                .offset(x: still ? 0 : phase.value * 18)
                        }
                        // Cards further away than the neighbours fade out.
                        .visualEffect { content, proxy in
                            let centre = proxy.frame(in: .scrollView(axis: .horizontal)).midX
                            let off = abs(centre - width / 2) / max(1, card.width + 14)
                            return content.opacity(off <= 1.2 ? 1 : max(0, 1 - (off - 1.2) * 2.5))
                        }
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 30)   // room for the cards' coloured shadows
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $centred)
        .safeAreaPadding(.horizontal, max(0, (width - card.width) / 2))
        .scrollClipDisabled()
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.8), value: centred)
    }

    // MARK: Dots

    private var dots: some View {
        HStack(spacing: 0) {
            ForEach(summaries) { summary in
                let on = summary.kind == (centred ?? .overall)
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.8)) { centred = summary.kind }
                } label: {
                    Capsule().fill(Color.white.opacity(on ? 1 : 0.4))
                        .frame(width: on ? 18 : 6, height: 6)
                        .frame(width: 30, height: 44)   // generous hit area
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(summary.kind.title)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: centred)
    }
}

/// Near-black with a faint 18 pt dot grid and a very soft Moss glow behind the cards.
private struct DataBackdrop: View {
    var body: some View {
        ZStack {
            Color(hex: "#08090A")
            Canvas { ctx, size in
                let step: CGFloat = 18
                var y: CGFloat = step / 2
                while y < size.height {
                    var x: CGFloat = step / 2
                    while x < size.width {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 0.5, y: y - 0.5, width: 1, height: 1)),
                                 with: .color(.white.opacity(0.1)))
                        x += step
                    }
                    y += step
                }
            }
            RadialGradient(colors: [Color.ncMoss.opacity(0.16), .clear], center: UnitPoint(x: 0.5, y: 0.34),
                           startRadius: 0, endRadius: 320)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

#if DEBUG
private struct DataScreenPreview: View {
    @State private var centred: DataGroupKind? = .overall
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
