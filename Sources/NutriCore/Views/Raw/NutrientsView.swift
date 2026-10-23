import SwiftUI
import SwiftData

struct NutrientsView: View {
    @Query(sort: \MealEntry.date) private var allMeals: [MealEntry]
    @Query private var profiles: [UserProfile]
    @AppStorage(RawSettings.modeKey) private var modeRaw = DietMode.rawCarnivore.rawValue
    @AppStorage(RawSettings.fatMinKey) private var fatMin = 0.0
    @AppStorage(RawSettings.fatMaxKey) private var fatMax = 0.0

    private var mode: DietMode { DietMode(rawValue: modeRaw) ?? .rawCarnivore }
    private var range: ClosedRange<Double> {
        (fatMin > 0 && fatMax > fatMin) ? fatMin...fatMax : mode.fatRange
    }
    private var goals: NutrientGoals { profiles.first.map(NutrientGoals.from) ?? NutrientGoals.default }
    private var week: [MealEntry] { NutrientAnalyzer.window(allMeals, days: 7) }
    private var today: [MealEntry] { allMeals.filter { Calendar.current.isDateInToday($0.date) } }

    var body: some View {
        let budget = NutrientAnalyzer.liverBudget(allMeals)
        let low = NutrientAnalyzer.chronicLow(allMeals, goals: goals)
        let gaps = NutrientAnalyzer.gaps(allMeals, goals: goals, male: profiles.first?.isMale ?? true)

        RawScreen(title: "Nutrients") {
            FatProteinGauge(todayPct: NutrientAnalyzer.fatCaloriePct(today), weekPct: NutrientAnalyzer.fatCaloriePct(week), range: range)

            RawCard {
                VStack(alignment: .leading, spacing: 10) {
                    FieldLabel(text: "Your fat target (% of calories)")
                    HStack {
                        Text("\(Int(range.lowerBound))% – \(Int(range.upperBound))%").font(.ui(size: 15, weight: .semibold)).foregroundColor(.ncPrimary)
                        Spacer()
                        Button("Reset to \(mode.label)") { fatMin = 0; fatMax = 0 }
                            .font(.ui(size: 13, weight: .semibold)).foregroundColor(.ncIndigo)
                    }
                    Slider(value: Binding(get: { range.lowerBound }, set: { fatMin = min($0, range.upperBound - 5); if fatMax == 0 { fatMax = range.upperBound } }),
                           in: 30...85, step: 1).tint(.ncIndigo)
                    Slider(value: Binding(get: { range.upperBound }, set: { fatMax = max($0, range.lowerBound + 5); if fatMin == 0 { fatMin = range.lowerBound } }),
                           in: 35...95, step: 1).tint(.ncIndigo)
                }
            }

            LiverBudgetCard(budget: budget)

            if !low.isEmpty {
                RawCard(title: "Running low") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(low, id: \.self) { n in
                            HStack { Tag(text: n, color: .ncOrange); Text("under half the reference on most logged days").font(.ui(size: 13)).foregroundColor(.ncSecondary) }
                        }
                    }
                }
            }

            RawCard(title: "Weekly nutrient gaps", trailing: gaps.loggedDays > 0 ? "avg of \(gaps.loggedDays) logged day(s)" : nil) {
                if gaps.loggedDays == 0 {
                    Text("Log a few meals to see how your week compares.").font(.ui(size: 13)).foregroundColor(.ncSecondary)
                } else {
                    VStack(spacing: 12) {
                        ForEach(gaps.gaps.sorted { $0.pct < $1.pct }) { g in
                            VStack(spacing: 5) {
                                HStack {
                                    Text(g.name).font(.ui(size: 13, weight: .medium)).foregroundColor(.ncPrimary)
                                    Spacer()
                                    Text("\(fmt(g.avg)) / \(fmt(g.target)) \(g.unit)").font(.ui(size: 12).monospacedDigit()).foregroundColor(.ncSecondary)
                                }
                                BandGauge(value: g.pct, color: g.pct < 0.5 ? .ncOrange : g.pct < 0.8 ? .ncSky : .ncGreen, height: 6)
                            }
                        }
                    }
                }
            }

            RawCard(title: "Other markers (7-day average)") {
                let d = Double(max(1, Set(week.map { Calendar.current.startOfDay(for: $0.date) }).count))
                VStack(spacing: 10) {
                    row("Omega-6 : omega-3", NutrientAnalyzer.omegaRatio(week).map { String(format: "%.1f : 1", $0) } ?? "—")
                    row("Heme iron", String(format: "%.1f mg/day", week.totalHemeIron / d))
                    row("Vitamin K2", "\(Int(week.totalVitaminK2 / d)) mcg/day")
                    row("Choline", "\(Int(week.totalCholine / d)) mg/day")
                    row("Cholesterol", "\(Int(week.totalCholesterol / d)) mg/day")
                    row("Estimated purine load", "\(Int(week.totalPurines / d)) mg/day")
                    row("Sodium", "\(Int(week.totalSodium / d)) mg/day")
                    row("Potassium", "\(Int(week.totalPotassium / d)) mg/day")
                    row("Magnesium", "\(Int(week.totalMagnesium / d)) mg/day")
                }
            }

            NavigationLink { OrganRotationView() } label: {
                NavRow(icon: "calendar", title: "Organ rotation", detail: "Gaps, weekly caps and what's due")
            }.buttonStyle(.plain)

            Disclaimer(text: "Targets are general RDA/UL reference values, not personalised medical advice. Purine and heme iron are estimates. Talk to a clinician about your own limits.")
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title).font(.ui(size: 13)).foregroundColor(.ncSecondary); Spacer()
            Text(value).font(.ui(size: 13, weight: .semibold).monospacedDigit()).foregroundColor(.ncPrimary) }
    }
    private func fmt(_ v: Double) -> String { v >= 100 ? String(Int(v)) : String(format: "%.1f", v) }
}

struct FatProteinGauge: View {
    let todayPct: Double?
    let weekPct: Double?
    let range: ClosedRange<Double>
    var index: String? = nil

    var body: some View {
        RawCard(title: "Fat ratio", trailing: "Target \(Int(range.lowerBound))–\(Int(range.upperBound))%", index: index) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 0) {
                    column("Today", todayPct)
                    Rectangle().fill(Color.ncPrimary.opacity(0.14)).frame(width: 1).padding(.horizontal, 16)
                    column("7-day average", weekPct)
                }
                Text("Share of calories from fat. The shaded band is your target range.")
                    .font(.ui(size: 13)).foregroundColor(.ncSecondary)
            }
        }
    }

    private func column(_ title: String, _ pct: Double?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).serifCaps(10).foregroundColor(.ncSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(pct.map { "\(Int($0))" } ?? "—").font(.metric(34)).foregroundColor(.ncPrimary)
                Text("% fat").font(.serif(13)).foregroundColor(.ncSecondary)
            }
            LineGauge(value: (pct ?? 0) / 100, band: (range.lowerBound / 100)...(range.upperBound / 100),
                      tint: pct.map { range.contains($0) ? Color.ncPrimary : Color.ncOrange } ?? .ncSecondary)
            Text(pct.map { range.contains($0) ? "In range" : ($0 < range.lowerBound ? "Below range" : "Above range") } ?? "No data")
                .font(.ui(size: 13)).foregroundColor(.ncSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LiverBudgetCard: View {
    let budget: LiverBudget
    var index: String? = nil
    var body: some View {
        let status = budget.status
        RawCard(title: "Liver budget", trailing: status == .over ? "Over" : status == .approaching ? "Approaching" : "Within range",
                trailingColor: status == .over ? .ncError : status == .approaching ? .ncOrange : .ncSecondary, index: index) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 0) {
                    meter("Vitamin A", "\(Int(budget.avgVitaminA).formatted()) of 3,000 mcg", budget.vitaminAPct)
                    Rectangle().fill(Color.ncPrimary.opacity(0.14)).frame(width: 1).padding(.horizontal, 16)
                    meter("Copper", String(format: "%.1f of 10 mg", budget.avgCopper), budget.copperPct)
                }
                Text(budget.remainingVitaminAWeek > 0
                     ? "Room for about \(Int(budget.beefLiverGramsLeft)) g of beef liver this week before the 7-day vitamin A average reaches the upper limit."
                     : "This week's vitamin A average has reached the reference upper limit.")
                    .font(.ui(size: 14)).foregroundColor(.ncPrimary).lineSpacing(2)
                Text("Daily averages over 7 days against general adult upper limits.")
                    .font(.ui(size: 12)).foregroundColor(.ncSecondary)
            }
        }
    }

    private func meter(_ title: String, _ detail: String, _ pct: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).serifCaps(10).foregroundColor(.ncSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(pct * 100))").font(.metric(34)).foregroundColor(pct >= 1 ? .ncError : .ncPrimary)
                Text("%").font(.serif(13)).foregroundColor(.ncSecondary)
            }
            LineGauge(value: pct, tint: pct >= 1 ? .ncError : pct >= 0.8 ? .ncOrange : .ncPrimary)
            Text(detail).font(.ui(size: 13)).foregroundColor(.ncSecondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OrganRotationView: View {
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    var body: some View {
        let status = NutrientAnalyzer.organStatus(meals)
        RawScreen(title: "Organ rotation") {
            ForEach(status) { s in
                RawCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(s.organ.label).font(.serif(24)).foregroundColor(.ncPrimary)
                            Spacer()
                            if s.overCap { Tag(text: "Over weekly cap", color: .ncError) }
                            else if s.due { Tag(text: s.lastEaten == nil ? "Never logged" : "Due", color: .ncSky) }
                            else { Tag(text: "On track", color: .ncGreen) }
                        }
                        HStack {
                            Text(s.daysSince.map { $0 == 0 ? "Last eaten today" : "\($0) day(s) since last" } ?? "Not logged yet")
                            Spacer()
                            Text("Every ~\(s.targetGapDays) days")
                        }
                        .font(.ui(size: 13)).foregroundColor(.ncSecondary)
                        BandGauge(value: s.weekGrams / s.capGrams, color: s.overCap ? .ncError : .ncPrimary, height: 6)
                        Text("\(Int(s.weekGrams)) g this week of \(Int(s.capGrams)) g cap").font(.ui(size: 12)).foregroundColor(.ncSecondary)
                    }
                }
            }
            Disclaimer(text: "Caps and gaps are general starting points (liver is also limited by the vitamin A and copper budget), not medical advice.")
        }
    }
}
