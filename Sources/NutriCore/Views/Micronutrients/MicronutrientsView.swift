import SwiftUI
import SwiftData

/// The Data tab, Nutrients list view: every tracked nutrient against its daily target, for today or as a daily
/// average over the last week, on the app's shared photo backdrop. A header with a Today / Week switch, a row of datasets, a summary tile (diet score,
/// a status bar, a legend and what needs attention), All / Low / Met filters, then one glass card per group
/// (Macros, Vitamins, Minerals) with a row per nutrient. Low is under 50% of the target, Met is 90% or more
/// (`NutrientInfo.isDeficient` / `isMet`); status always shows as a word, never colour alone.
struct MicronutrientsView: View {
    enum Range: Hashable { case today, week }
    enum Filter: Hashable { case all, low, met }
    enum Dataset: String, CaseIterable, Identifiable {
        case nutrients = "Nutrients", biomarkers = "Biomarkers", diet = "Diet", sun = "Sun", timing = "Timing"
        var id: Self { self }
    }

    @Query private var meals: [MealEntry]
    @Query private var profiles: [UserProfile]
    @State private var range: Range = .today
    @State private var filter: Filter = .all
    @State private var dataset: Dataset = .nutrients

    init() {
        // Two weeks back: the shown period plus the one before it, for the score's change.
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -13, to: cal.startOfDay(for: .now)) ?? .now
        _meals = Query(filter: #Predicate<MealEntry> { $0.date >= start })
    }

    private var goals: NutrientGoals { profiles.first.map(NutrientGoals.from) ?? .default }

    /// Meals in the shown period (`back` = 0) or the one before it (`back` = 1): a day for Today, 7 days for Week.
    private func periodMeals(back: Int) -> [MealEntry] {
        let cal = Calendar.current
        let length = range == .today ? 1 : 7
        let today = cal.startOfDay(for: .now)
        guard let end = cal.date(byAdding: .day, value: 1 - back * length, to: today),
              let start = cal.date(byAdding: .day, value: -length, to: end) else { return [] }
        return meals.filter { $0.date >= start && $0.date < end }
    }

    /// Today's totals, or the daily average over the week's logged days (so days before you started don't drag
    /// it down).
    private func nutrients(in meals: [MealEntry]) -> [NutrientInfo] {
        let cal = Calendar.current
        let days = range == .today ? 1 : Double(max(1, Set(meals.map { cal.startOfDay(for: $0.date) }).count))
        return buildNutrientList(from: meals, goals: goals)
            .map { NutrientInfo(id: $0.id, name: $0.name, unit: $0.unit, icon: $0.icon, group: $0.group,
                                current: $0.current / days, goal: $0.goal) }
    }

    /// 0–100: the average share of each target met, each capped at 100%.
    private static func score(_ list: [NutrientInfo]) -> Int {
        guard !list.isEmpty else { return 0 }
        return Int((list.map(\.progress).reduce(0, +) / Double(list.count) * 100).rounded())
    }

    var body: some View {
        let current = periodMeals(back: 0)
        let previous = periodMeals(back: 1)
        let all = nutrients(in: current)
        let score = Self.score(all)
        let change: Int? = previous.isEmpty || current.isEmpty ? nil : score - Self.score(nutrients(in: previous))

        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                header(tracked: all.count)
                    .padding(.top, 8)

                datasetChips

                if dataset == .nutrients {
                    SummaryTile(nutrients: all, score: score, change: change, range: range, hasMeals: !current.isEmpty)
                    filterChips(all)
                    ForEach(NutrientGroup.allCases, id: \.self) { group in
                        let rows = all.filter { $0.group == group }
                        if !rows.isEmpty { GroupCard(group: group, rows: rows, filter: filter) }
                    }
                    Text("Daily targets follow NIH dietary reference intakes for your age and sex."
                         + (range == .week ? " Week shows the daily average over days you logged." : ""))
                        .font(.ui(size: 12)).lineSpacing(3).foregroundColor(Color.ncPrimary.opacity(0.6))
                        .padding(.top, 4).padding(.horizontal, 4)
                } else {
                    comingSoon
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
            .animation(.smooth(duration: 0.3), value: range)
            .animation(.smooth(duration: 0.25), value: filter)
            .animation(.smooth(duration: 0.25), value: dataset)
        }
        .glassLightFollowsScroll()
    }

    // MARK: Header

    private func header(tracked: Int) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(range == .today ? "Today" : "This week") · \(tracked) tracked")
                    .font(.mono(11)).tracking(11 * 0.08).textCase(.uppercase)
                    .foregroundColor(Color.ncPrimary.opacity(0.78))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text("Data").font(.ui(size: 34, weight: .bold)).tracking(-34 * 0.03)
                    .foregroundColor(.ncPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RangeSwitch(selection: $range)
        }
    }

    // MARK: Chips

    /// Datasets, scrolling sideways out to the screen edges so it reads as a row that continues.
    private var datasetChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Dataset.allCases) { set in
                    DataChip(selected: dataset == set) {
                        Text(set.rawValue)
                    } action: {
                        dataset = set
                    }
                }
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.horizontal, -16)
    }

    private func filterChips(_ all: [NutrientInfo]) -> some View {
        let low = all.filter(\.isDeficient).count, met = all.filter(\.isMet).count
        return HStack(spacing: 8) {
            DataChip(selected: filter == .all) { Text("All \(all.count)") } action: { filter = .all }
            DataChip(selected: filter == .low) {
                HStack(spacing: 6) { Circle().fill(Color.ncEmber).frame(width: 8, height: 8); Text("Low \(low)") }
            } action: { filter = filter == .low ? .all : .low }
            DataChip(selected: filter == .met) {
                HStack(spacing: 6) { Circle().fill(Color.ncMoss).frame(width: 8, height: 8); Text("Met \(met)") }
            } action: { filter = filter == .met ? .all : .met }
            Spacer(minLength: 0)
        }
    }

    /// The other datasets aren't on this tab yet.
    private var comingSoon: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dataset.rawValue).font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase)
                .foregroundColor(.ncPrimary)
            Text("\(dataset.rawValue) isn't shown here yet. Nutrients has today's full breakdown.")
                .font(.ui(size: 15)).foregroundColor(Color.ncPrimary.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16).padding(.horizontal, 20)
        .dataGlass(radius: 30)
    }
}

// MARK: - Glass surface

private extension View {
    /// Tinted glass with the moving light on its rim.
    func dataGlass(radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self.glassSheen(in: shape, strength: 0.8).glass(.tinted, in: shape)
    }
}

// MARK: - Controls

/// TODAY | WEEK on a glass capsule; the selected segment is a Paper capsule with dark text.
private struct RangeSwitch: View {
    @Binding var selection: MicronutrientsView.Range
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            segment(.today, "Today")
            segment(.week, "Week")
        }
        .padding(4)
        .glass(.clear, in: Capsule())
    }

    private func segment(_ value: MicronutrientsView.Range, _ label: String) -> some View {
        let on = selection == value
        return Button {
            guard !on else { return }
            Haptics.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = value }
        } label: {
            Text(label).font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase)
                .foregroundColor(on ? .ncOnPrimary : .ncPrimary)
                .padding(.horizontal, 14)
                .frame(minWidth: 64, minHeight: 36)
                .background { if on { Capsule().fill(Color.ncPrimary).matchedGeometryEffect(id: "pill", in: pill) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Mono caps capsule. Unselected: white 8% with a white 16% hairline; selected: Paper with dark text. The visible
/// capsule is 34 pt tall inside a 44 pt tap target.
private struct DataChip<Label: View>: View {
    let selected: Bool
    @ViewBuilder let label: () -> Label
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            withAnimation(.smooth(duration: 0.25)) { action() }
        } label: {
            label()
                .font(.mono(11, .medium)).tracking(0.88).textCase(.uppercase)
                .foregroundColor(selected ? .ncOnPrimary : .ncPrimary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background {
                    Capsule().fill(selected ? Color.ncPrimary : Color.white.opacity(0.08))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(selected ? 0 : 0.16), lineWidth: 1))
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Summary

private enum Status {
    case met, onTrack, low
    init(_ n: NutrientInfo) { self = n.isMet ? .met : n.isDeficient ? .low : .onTrack }
}

/// Diet score and how it moved, a status bar of met / on track / low, the legend, and the Low nutrients by name.
private struct SummaryTile: View {
    let nutrients: [NutrientInfo]
    let score: Int
    let change: Int?
    let range: MicronutrientsView.Range
    let hasMeals: Bool

    private var met: Int { nutrients.filter(\.isMet).count }
    private var low: [NutrientInfo] { nutrients.filter(\.isDeficient) }
    private var onTrack: Int { nutrients.count - met - low.count }

    /// The Low nutrients by name; past five, the rest as a count so the tile stays short on an empty day.
    private var attention: String {
        guard !low.isEmpty else { return "Nothing is low" }
        let names = low.prefix(5).map(\.name).joined(separator: ", ")
        return low.count > 5 ? "\(names) and \(low.count - 5) more" : names
    }

    private var changeText: String {
        let since = range == .today ? "on yesterday" : "this week"
        guard hasMeals else { return range == .today ? "Log a meal to start" : "Nothing logged this week" }
        guard let change else { return range == .today ? "First day logged" : "First week logged" }
        if change == 0 { return range == .today ? "Same as yesterday" : "Same as last week" }
        return "\(change > 0 ? "Up" : "Down") \(abs(change)) \(since)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Text("\(score)").font(.display(56)).foregroundColor(.ncPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Diet score").font(.mono(11)).tracking(0.88).textCase(.uppercase)
                        .foregroundColor(Color.ncPrimary.opacity(0.78))
                    Text(changeText).font(.ui(size: 14, weight: .semibold)).foregroundColor(.ncPrimary)
                }
                Spacer(minLength: 0)
            }
            .overlay(alignment: .topTrailing) {
                // The app's rune, quietly signing the score.
                AlgizMark().fill(Color.ncPrimary.opacity(0.22)).frame(width: 12, height: 16)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)

            StatusBar(met: met, onTrack: onTrack, low: low.count)

            HStack(spacing: 14) {
                legend(.ncMoss, "\(met) met")
                legend(Color.ncPrimary.opacity(0.85), "\(onTrack) on track")
                legend(.ncEmber, "\(low.count) low")
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 4) {
                Text("Needs attention").font(.mono(11)).tracking(0.88).textCase(.uppercase)
                    .foregroundColor(Color.ncPrimary.opacity(0.78))
                Text(attention)
                    .font(.ui(size: 13)).foregroundColor(.ncPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16).padding(.horizontal, 20)
        .lineArt(.sprig, placement: .init(alignment: .bottomTrailing, size: 150, offset: CGSize(width: 30, height: 40)),
                 radius: 30)
        .dataGlass(radius: 30)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.mono(11)).tracking(0.88).textCase(.uppercase).foregroundColor(.ncPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

/// 10 pt bar of fully rounded segments, 3 pt apart, each as wide as its share: Met, On track, Low.
private struct StatusBar: View {
    let met: Int
    let onTrack: Int
    let low: Int

    var body: some View {
        let parts = [(met, Color.ncMoss), (onTrack, Color.ncPrimary.opacity(0.85)), (low, Color.ncEmber)]
            .filter { $0.0 > 0 }
        let total = max(1, parts.reduce(0) { $0 + $1.0 })
        GeometryReader { geo in
            let room = geo.size.width - CGFloat(max(0, parts.count - 1)) * 3
            HStack(spacing: 3) {
                ForEach(parts.indices, id: \.self) { i in
                    Capsule().fill(parts[i].1)
                        .frame(width: max(10, room * CGFloat(parts[i].0) / CGFloat(total)))
                }
            }
        }
        .frame(height: 10)
        .background { if parts.isEmpty { Capsule().fill(Color.ncPrimary.opacity(0.18)) } }
        .accessibilityElement()
        .accessibilityLabel("\(met) met, \(onTrack) on track, \(low) low")
    }
}

// MARK: - Group card

/// One group (Macros, Vitamins, Minerals): header with counts, a rule, then a row per nutrient. Rows that don't
/// match the Low / Met filter dim.
private struct GroupCard: View {
    let group: NutrientGroup
    let rows: [NutrientInfo]
    let filter: MicronutrientsView.Filter

    /// Each group gets its own drawing, tucked into the top-right corner.
    private var art: LineArt {
        switch group {
        case .macros: .leaf
        case .vitamins: .sun
        case .minerals: .water
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.rawValue).font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase)
                    .foregroundColor(.ncPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("\(rows.count) tracked · \(rows.filter(\.isMet).count) met")
                    .font(.mono(11)).tracking(0.88).textCase(.uppercase)
                    .foregroundColor(Color.ncPrimary.opacity(0.78))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.ncPrimary.opacity(0.2)).frame(height: 1) }

            ForEach(Array(rows.enumerated()), id: \.element.id) { i, n in
                NutrientListRow(n: n)
                    .opacity(matches(n) ? 1 : 0.35)
                    .overlay(alignment: .top) {
                        if i > 0 { Rectangle().fill(Color.ncPrimary.opacity(0.12)).frame(height: 1) }
                    }
            }
        }
        .padding(.top, 14).padding(.horizontal, 18).padding(.bottom, 6)
        .lineArt(art, placement: .init(alignment: .topTrailing, size: 150, offset: CGSize(width: 36, height: -30)),
                 radius: 28)
        .dataGlass(radius: 28)
    }

    private func matches(_ n: NutrientInfo) -> Bool {
        switch filter {
        case .all: true
        case .low: n.isDeficient
        case .met: n.isMet
        }
    }
}

/// Name, a LOW / MET pill when it applies, amount against target; then the bar and the percent.
private struct NutrientListRow: View {
    let n: NutrientInfo

    private var raw: Double { n.goal > 0 ? n.current / n.goal : 0 }
    private var status: Status { Status(n) }
    private var fill: Color {
        switch status {
        case .met: .ncMoss
        case .low: .ncEmber
        case .onTrack: .ncPrimary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(n.name).font(.ui(size: 14, weight: .semibold)).foregroundColor(.ncPrimary).lineLimit(1)
                switch status {
                case .met: pill("Met", .ncMoss)
                case .low: pill("Low", .ncEmber)
                case .onTrack: EmptyView()
                }
                Spacer(minLength: 8)
                Text("\(NutrientRow.dec(n.current)) / \(NutrientRow.dec(n.goal)) \(n.unit)")
                    .font(.mono(11)).textCase(.uppercase).foregroundColor(.ncPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.ncPrimary.opacity(0.18))
                        Capsule().fill(fill).frame(width: geo.size.width * min(max(raw, 0), 1))
                    }
                }
                .frame(height: 5)
                Text("\(Int((raw * 100).rounded()))%").font(.display(13)).foregroundColor(.ncPrimary)
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(n.name)
        .accessibilityValue("\(Int((raw * 100).rounded())) percent, \(NutrientRow.dec(n.current)) of \(NutrientRow.dec(n.goal)) \(n.unit)"
                            + (status == .met ? ", met" : status == .low ? ", low" : ""))
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text).font(.mono(9, .semibold)).tracking(0.72).textCase(.uppercase)
            .foregroundColor(.ncOnPrimary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color))
            .fixedSize()
    }
}
