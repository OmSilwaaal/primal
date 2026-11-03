import SwiftUI
import SwiftData

/// The Data tab: one nutrient group at a time (Macros, Vitamins, Minerals). A header with an info button, the
/// group's score now with its status word, a 7-day trend line, a stepper to move between groups (or a sideways
/// swipe), and a thick-glass sheet underneath with Met / On track / Low counts and every nutrient in the group,
/// lowest first. A group's score is the average share of each item's daily target met, each capped at 100%.
/// Status always shows as a word: Met is 90% or more, On track 50–89%, Low under 50%.
struct MicronutrientsView: View {
    @Query private var meals: [MealEntry]
    @Query private var profiles: [UserProfile]
    @State private var group: NutrientGroup = .macros
    /// +1 when the last change moved forward through the groups, for the slide direction.
    @State private var forward = true
    @State private var showInfo = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let groups = NutrientGroup.allCases

    init() {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .now
        _meals = Query(filter: #Predicate<MealEntry> { $0.date >= start })
    }

    private var goals: NutrientGoals { profiles.first.map(NutrientGoals.from) ?? .default }

    /// The last seven days, oldest first, ending today.
    private var days: [Date] {
        let cal = Calendar.current, today = cal.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    private func items(on day: Date) -> [NutrientInfo] {
        let cal = Calendar.current
        let dayMeals = meals.filter { cal.isDate($0.date, inSameDayAs: day) }
        return buildNutrientList(from: dayMeals, goals: goals).filter { $0.group == group }
    }

    /// 0–100: the average of each item's share of its target, capped at 100% each.
    private static func score(_ list: [NutrientInfo]) -> Double {
        guard !list.isEmpty else { return 0 }
        return list.map(\.progress).reduce(0, +) / Double(list.count) * 100
    }

    var body: some View {
        let series = days.map { Self.score(items(on: $0)) }
        let today = items(on: days.last ?? .now)
        let now = series.last ?? 0
        let rising = now >= (series.dropLast().last ?? 0)

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                header
                ScoreRow(score: now, rising: rising, group: group)
                TrendChart(series: series)
                    .id(group)
                    .transition(slide)
                GroupStepper(group: group, groups: Self.groups, onStep: step)
            }
            .padding(.horizontal, Bento.margin)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 24).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) > 44 else { return }
                step(value.translation.width < 0 ? 1 : -1)
            })

            GroupSheet(group: group, items: today)
                .id(group)
                .transition(.opacity)
        }
        .sheet(isPresented: $showInfo) { ScoreInfoSheet() }
    }

    private var slide: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                              removal: .opacity)
    }

    /// Moves to the previous (−1) or next (+1) group, if there is one.
    private func step(_ by: Int) {
        guard let i = Self.groups.firstIndex(of: group) else { return }
        let next = i + by
        guard Self.groups.indices.contains(next) else { return }
        Haptics.selection()
        forward = by > 0
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.88)) {
            group = Self.groups[next]
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Data").font(.display(36)).foregroundColor(Mono.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { showInfo = true } label: { Image(systemName: "info") }
                .buttonStyle(.bentoRound)
                .accessibilityLabel("How the score works")
        }
    }
}

// MARK: - Status

/// Met is 90% or more of a target, On track 50–89%, Low under 50%.
enum NutrientStatus {
    case met, onTrack, low

    init(percent: Double) {
        self = percent >= 90 ? .met : percent >= 50 ? .onTrack : .low
    }

    var word: String {
        switch self {
        case .met: "Met"
        case .onTrack: "On track"
        case .low: "Low"
        }
    }

    var color: Color {
        switch self {
        case .met: .ncMoss
        case .onTrack: .ncPrimary
        case .low: .ncEmber
        }
    }
}

private extension NutrientGroup {
    var title: String {
        switch self {
        case .macros: "Macros"
        case .vitamins: "Vitamins"
        case .minerals: "Minerals"
        }
    }
}

// MARK: - Score

/// "NOW ———— ON TRACK", then the score large with a small triangle for the direction since yesterday.
private struct ScoreRow: View {
    let score: Double
    let rising: Bool
    let group: NutrientGroup

    var body: some View {
        let status = NutrientStatus(percent: score)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Now").font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase).foregroundColor(Mono.label)
                Rectangle().fill(Color.ncPrimary.opacity(0.25)).frame(height: 1)
                Text(status.word).font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase)
                    .foregroundColor(status.color)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(Int(score.rounded()))").font(.display(56)).foregroundColor(Mono.text)
                    .contentTransition(.numericText())
                    .animation(.smooth, value: Int(score.rounded()))
                Image(systemName: rising ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 11)).foregroundColor(rising ? .ncMoss : .ncEmber)
                    .accessibilityHidden(true)
                Text("\(group.title) score · 7 days").font(.ui(size: 13)).foregroundColor(Mono.label)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.title) score")
        .accessibilityValue("\(Int(score.rounded())), \(status.word), \(rising ? "up" : "down") since yesterday")
    }
}

// MARK: - Trend chart

/// The last seven daily scores as a smooth Paper line on faint graph paper, dots on past days and a white knob
/// with the rune at today. A fixed 30–105 scale keeps the line calm.
private struct TrendChart: View {
    let series: [Double]
    private let lower = 30.0, upper = 105.0
    private let knob: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            // Room on every side for the 44 pt knob, wherever the line ends.
            let inset = knob / 2 + 4
            let w = geo.size.width - inset * 2, h = geo.size.height - inset * 2
            let points = series.enumerated().map { i, v -> CGPoint in
                let x = inset + w * CGFloat(i) / CGFloat(max(1, series.count - 1))
                let t = (min(max(v, lower), upper) - lower) / (upper - lower)
                return CGPoint(x: x, y: inset + h * (1 - t))
            }
            ZStack(alignment: .topLeading) {
                // Graph paper.
                Path { p in
                    let step: CGFloat = 18
                    var x: CGFloat = 0
                    while x <= geo.size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: geo.size.height)); x += step }
                    var y: CGFloat = 0
                    while y <= geo.size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)); y += step }
                }
                .stroke(Color.ncPrimary.opacity(0.05), lineWidth: 1)

                SmoothLine(points: points)
                    .stroke(Color.ncPrimary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                ForEach(Array(points.dropLast().enumerated()), id: \.offset) { _, p in
                    Circle().fill(Color.ncPrimary).frame(width: 7, height: 7).position(p)
                }
                if let last = points.last {
                    ZStack {
                        Circle().fill(Color.ncPrimary)
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                        AlgizMark().fill(Color.ncOnPrimary).frame(width: 13, height: 17)
                    }
                    .frame(width: knob, height: knob)
                    .position(last)
                }
            }
        }
        .frame(height: 140)
        .padding(.horizontal, 6)
        .clipShape(RoundedRectangle(cornerRadius: Bento.radius, style: .continuous))
        .glassSheen(in: RoundedRectangle(cornerRadius: Bento.radius, style: .continuous), strength: 0.8)
        .glass(.tinted, in: RoundedRectangle(cornerRadius: Bento.radius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last 7 days")
        .accessibilityValue(series.map { "\(Int($0.rounded()))" }.joined(separator: ", "))
    }
}

/// A Catmull-Rom curve through the points, so the line bends smoothly through every day.
struct SmoothLine: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        guard points.count > 1 else { return p }
        for i in 0..<(points.count - 1) {
            let p0 = points[max(0, i - 1)], p1 = points[i], p2 = points[i + 1], p3 = points[min(points.count - 1, i + 2)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
        return p
    }
}

// MARK: - Stepper

/// Previous (glass) and Next (solid white), 68 pt, with the group's name and three page dots between them.
private struct GroupStepper: View {
    let group: NutrientGroup
    let groups: [NutrientGroup]
    let onStep: (Int) -> Void

    var body: some View {
        let i = groups.firstIndex(of: group) ?? 0
        HStack(spacing: 12) {
            Button { onStep(-1) } label: { Image(systemName: "arrow.left") }
                .buttonStyle(BentoRoundButtonStyle(size: 68))
                .disabled(i == 0)
                .opacity(i == 0 ? 0.35 : 1)
                .accessibilityLabel("Previous group")

            VStack(spacing: 8) {
                Text(group.title).font(.ui(size: 17, weight: .semibold)).foregroundColor(Mono.text)
                    .contentTransition(.opacity)
                HStack(spacing: 6) {
                    ForEach(groups.indices, id: \.self) { j in
                        Circle().fill(Color.ncPrimary.opacity(j == i ? 1 : 0.25)).frame(width: 6, height: 6)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(group.title), group \(i + 1) of \(groups.count)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onStep(1)
                case .decrement: onStep(-1)
                @unknown default: break
                }
            }

            Button { onStep(1) } label: {
                Image(systemName: "arrow.right").font(.ui(size: 20, weight: .semibold)).foregroundColor(Mono.onWhite)
                    .frame(width: 68, height: 68)
                    .background(Circle().fill(Mono.text))
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.92))
            .disabled(i == groups.count - 1)
            .opacity(i == groups.count - 1 ? 0.35 : 1)
            .accessibilityLabel("Next group")
        }
    }
}

// MARK: - Sheet

/// The group in full: name and TODAY, Met / On track / Low counts, then every item lowest first, in a thick-glass
/// sheet that runs to the bottom of the screen and scrolls on its own.
private struct GroupSheet: View {
    let group: NutrientGroup
    let items: [NutrientInfo]

    private func percent(_ n: NutrientInfo) -> Double { n.goal > 0 ? n.current / n.goal * 100 : 0 }

    var body: some View {
        let sorted = items.sorted { percent($0) < percent($1) }
        let statuses = items.map { NutrientStatus(percent: percent($0)) }
        let shape = UnevenRoundedRectangle(topLeadingRadius: 44, topTrailingRadius: 44, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Color.white.opacity(0.3)).frame(width: 40, height: 5)
                .frame(maxWidth: .infinity).padding(.top, 10).padding(.bottom, 14)
                .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline) {
                Text(group.title).font(.ui(size: 22, weight: .bold)).foregroundColor(Mono.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Today").font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase).foregroundColor(Mono.label)
            }
            .padding(.horizontal, 22)

            HStack(spacing: 0) {
                count(.met, statuses.filter { $0 == .met }.count)
                count(.onTrack, statuses.filter { $0 == .onTrack }.count)
                count(.low, statuses.filter { $0 == .low }.count)
            }
            .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 12)

            Rectangle().fill(Color.ncPrimary.opacity(0.15)).frame(height: 1).padding(.horizontal, 22)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { i, n in
                        row(n)
                            .overlay(alignment: .top) {
                                if i > 0 { Rectangle().fill(Color.ncPrimary.opacity(0.1)).frame(height: 1) }
                            }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 130)   // the last row clears the floating tab bar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glass(.thick, in: shape)
        .ignoresSafeArea(edges: .bottom)
    }

    private func count(_ s: NutrientStatus, _ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(s.color).frame(width: 8, height: 8)
                Text("\(n)").font(.display(26)).foregroundColor(Mono.text)
                    .contentTransition(.numericText())
            }
            Text(s.word).font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase).foregroundColor(Mono.label)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func row(_ n: NutrientInfo) -> some View {
        let pct = percent(n)
        let status = NutrientStatus(percent: pct)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(n.name).font(.ui(size: 15, weight: .semibold)).foregroundColor(Mono.text).lineLimit(1)
                Text(status.word).font(.mono(11, .semibold)).tracking(0.66).textCase(.uppercase)
                    .foregroundColor(status.color)
                    .lineLimit(1).fixedSize()
                Spacer(minLength: 8)
                Text("\(Int(pct.rounded()))%").font(.display(17)).foregroundColor(Mono.text).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ncPrimary.opacity(0.15))
                    Capsule().fill(status.color).frame(width: geo.size.width * min(max(pct / 100, 0), 1))
                }
            }
            .frame(height: 5)
            Text("\(NutrientRow.dec(n.current)) / \(NutrientRow.dec(n.goal)) \(n.unit)")
                .font(.mono(11)).textCase(.uppercase).foregroundColor(Mono.label)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(n.name)
        .accessibilityValue("\(Int(pct.rounded())) percent, \(status.word), \(NutrientRow.dec(n.current)) of \(NutrientRow.dec(n.goal)) \(n.unit)")
    }
}

// MARK: - Info

private struct ScoreInfoSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How the score works").font(.ui(size: 22, weight: .bold)).foregroundColor(Mono.text)
            Text("Each group's score is the average of how much of every item's daily target you've met, with each item counting up to 100%. Going over one target doesn't make up for being short on another.")
                .font(.bentoBody).foregroundColor(Mono.label).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                legend(.met, "90% or more of the target")
                legend(.onTrack, "50 to 89%")
                legend(.low, "Under 50%")
            }
            Text("The line shows the last seven days. Targets follow NIH dietary reference intakes for your age and sex, and energy comes from your weight, height, age and activity.")
                .font(.ui(size: 12)).foregroundColor(Mono.label).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(22)
        .presentationDetents([.medium])
        .glassSheetBackground()
        .presentationCornerRadius(Bento.radius)
    }

    private func legend(_ s: NutrientStatus, _ text: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(s.color).frame(width: 8, height: 8)
            Text(s.word).font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase).foregroundColor(s.color)
                .frame(width: 84, alignment: .leading)
            Text(text).font(.ui(size: 14)).foregroundColor(Mono.text)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#if DEBUG
/// An in-memory store with a profile and a week of meals, for previews.
@MainActor
enum VitalisPreviewData {
    static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: MealEntry.self, UserProfile.self, BiomarkerReading.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        let profile = UserProfile()
        profile.name = "Om"
        ctx.insert(profile)
        let cal = Calendar.current
        for back in 0..<7 {
            let day = cal.date(byAdding: .day, value: -back, to: .now) ?? .now
            let meal = MealEntry()
            meal.date = day
            meal.foodName = "Ribeye"
            let k = 0.6 + Double((back * 37) % 50) / 100
            meal.calories = 2000 * k; meal.protein = 120 * k; meal.carbohydrates = 80 * k
            meal.totalFat = 110 * k; meal.fiber = 12 * k
            meal.vitaminA = 600 * k; meal.vitaminC = 20 * k; meal.vitaminD = 6 * k; meal.vitaminB12 = 6 * k
            meal.iron = 9 * k; meal.zinc = 12 * k; meal.magnesium = 180 * k; meal.potassium = 2400 * k
            ctx.insert(meal)
            let weight = BiomarkerReading()
            weight.date = day
            weight.kind = BiomarkerKind.weight.rawValue
            weight.value = 74 + Double(back) * 0.3
            ctx.insert(weight)
        }
        return container
    }()
}

#Preview("Data") {
    MicronutrientsView()
        .background { AppBackdrop().ignoresSafeArea() }
        .modelContainer(VitalisPreviewData.container)
        .preferredColorScheme(.dark)
}
#endif
