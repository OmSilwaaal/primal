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
                        Text("\(Int(range.lowerBound))% – \(Int(range.upperBound))%").font(.system(size: 15, weight: .semibold)).foregroundColor(.ncPrimary)
                        Spacer()
                        Button("Reset to \(mode.label)") { fatMin = 0; fatMax = 0 }
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.ncIndigo)
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
                            HStack { Tag(text: n, color: .ncOrange); Text("under half the reference on most logged days").font(.system(size: 13)).foregroundColor(.ncSecondary) }
                        }
                    }
                }
            }

            RawCard(title: "Weekly nutrient gaps", trailing: gaps.loggedDays > 0 ? "avg of \(gaps.loggedDays) logged day(s)" : nil) {
                if gaps.loggedDays == 0 {
                    Text("Log a few meals to see how your week compares.").font(.system(size: 13)).foregroundColor(.ncSecondary)
                } else {
                    VStack(spacing: 12) {
                        ForEach(gaps.gaps.sorted { $0.pct < $1.pct }) { g in
                            VStack(spacing: 5) {
                                HStack {
                                    Text(g.name).font(.system(size: 13, weight: .medium)).foregroundColor(.ncPrimary)
                                    Spacer()
                                    Text("\(fmt(g.avg)) / \(fmt(g.target)) \(g.unit)").font(.system(size: 12).monospacedDigit()).foregroundColor(.ncSecondary)
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
        HStack { Text(title).font(.system(size: 13)).foregroundColor(.ncSecondary); Spacer()
            Text(value).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundColor(.ncPrimary) }
    }
    private func fmt(_ v: Double) -> String { v >= 100 ? String(Int(v)) : String(format: "%.1f", v) }
}

struct FatProteinGauge: View {
    let todayPct: Double?
    let weekPct: Double?
    let range: ClosedRange<Double>

    var body: some View {
        RawCard(title: "Fat : protein by calories", trailing: "Target \(Int(range.lowerBound))–\(Int(range.upperBound))% fat") {
            VStack(alignment: .leading, spacing: 14) {
                gauge("Today", todayPct)
                gauge("7-day average", weekPct)
            }
        }
    }

    private func gauge(_ title: String, _ pct: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(.ncSecondary)
                Spacer()
                if let pct {
                    Text("\(Int(pct))% fat · \(100 - Int(pct))% protein+carb")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(color(pct))
                } else {
                    Text("No data").font(.system(size: 13)).foregroundColor(.ncSecondary)
                }
            }
            BandGauge(value: (pct ?? 0) / 100, band: (range.lowerBound / 100)...(range.upperBound / 100),
                      color: pct.map(color) ?? .ncSecondary, height: 10)
        }
    }

    private func color(_ p: Double) -> Color { range.contains(p) ? .ncGreen : (p < range.lowerBound ? .ncSky : .ncOrange) }
}

struct LiverBudgetCard: View {
    let budget: LiverBudget
    var body: some View {
        let status = budget.status
        RawCard(title: "Liver budget", trailing: status == .over ? "Over" : status == .approaching ? "Approaching" : "Within range",
                trailingColor: status == .over ? .ncError : status == .approaching ? .ncOrange : .ncGreen) {
            VStack(alignment: .leading, spacing: 14) {
                meter("Preformed vitamin A", "\(Int(budget.avgVitaminA)) / \(Int(LiverBudget.vitaminAUL)) mcg RAE per day", budget.vitaminAPct)
                meter("Copper", String(format: "%.1f / %.0f mg per day", budget.avgCopper, LiverBudget.copperUL), budget.copperPct)
                Text(budget.remainingVitaminAWeek > 0
                     ? "About \(Int(budget.beefLiverGramsLeft)) g of beef liver of room left this week before the 7-day average reaches the vitamin A upper limit."
                     : "This week's vitamin A has reached the reference upper limit. Averages over the week are what counts.")
                    .font(.system(size: 13)).foregroundColor(.ncSecondary)
                Text("Adult UL values (3,000 mcg RAE vitamin A, 10 mg copper per day) are general references, averaged over 7 days.")
                    .font(.system(size: 12)).foregroundColor(.ncSecondary)
            }
        }
    }

    private func meter(_ title: String, _ detail: String, _ pct: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(.ncPrimary); Spacer()
                Text("\(Int(pct * 100))%").font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundColor(pct >= 1 ? .ncError : pct >= 0.8 ? .ncOrange : .ncPrimary) }
            BandGauge(value: pct, color: pct >= 1 ? .ncError : pct >= 0.8 ? .ncOrange : .ncGreen)
            Text(detail).font(.system(size: 12)).foregroundColor(.ncSecondary)
        }
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
                            Text(s.organ.label).font(.system(size: 16, weight: .bold)).foregroundColor(.ncPrimary)
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
                        .font(.system(size: 13)).foregroundColor(.ncSecondary)
                        BandGauge(value: s.weekGrams / s.capGrams, color: s.overCap ? .ncError : .ncPrimary, height: 6)
                        Text("\(Int(s.weekGrams)) g this week of \(Int(s.capGrams)) g cap").font(.system(size: 12)).foregroundColor(.ncSecondary)
                    }
                }
            }
            Disclaimer(text: "Caps and gaps are general starting points (liver is also limited by the vitamin A and copper budget), not medical advice.")
        }
    }
}
