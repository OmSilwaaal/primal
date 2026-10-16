import SwiftUI
import SwiftData

/// The Raw tab: diet position, food safety and the carnivore-specific tools in one place.
struct RawHubView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @Query private var batches: [SourceBatch]
    @Query private var profiles: [UserProfile]
    @AppStorage(RawSettings.modeKey) private var modeRaw = DietMode.rawCarnivore.rawValue
    @AppStorage(RawSettings.disclaimerKey) private var accepted = false
    @AppStorage(RawSettings.fatMinKey) private var fatMin = 0.0
    @AppStorage(RawSettings.fatMaxKey) private var fatMax = 0.0
    @State private var showLog = false

    private var mode: DietMode { DietMode(rawValue: modeRaw) ?? .rawCarnivore }
    private var fatRange: ClosedRange<Double> { (fatMin > 0 && fatMax > fatMin) ? fatMin...fatMax : mode.fatRange }
    private var goals: NutrientGoals { profiles.first.map(NutrientGoals.from) ?? NutrientGoals.default }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ncBg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Raw").font(.system(size: 22, weight: .bold)).tracking(-0.5).foregroundColor(.ncPrimary)
                            Tag(text: mode.label, color: .ncIndigo)
                            Spacer()
                        }
                        .padding(.top, 12)

                        if !accepted { disclaimerGate }

                        Button { showLog = true } label: { Label("Log raw food", systemImage: "plus") }
                            .buttonStyle(.primal)

                        dietCard
                        safetyCard
                        FatProteinGauge(todayPct: NutrientAnalyzer.fatCaloriePct(meals.filter { Calendar.current.isDateInToday($0.date) }),
                                        weekPct: NutrientAnalyzer.fatCaloriePct(NutrientAnalyzer.window(meals, days: 7)), range: fatRange)
                        LiverBudgetCard(budget: NutrientAnalyzer.liverBudget(meals))
                        timingCard

                        VStack(spacing: 8) {
                            link(NutrientsView(), "chart.bar.doc.horizontal", "Nutrients", "Gaps, omega ratio, purines, organ budget")
                            link(SafetyView(), "shield.lefthalf.filled", "Food safety", "Batches, freezer log, recalls", badge: flagged > 0 ? "\(flagged) recall" : nil)
                            link(CheckInView(), "face.smiling", "Daily check-in", "Energy, mood, digestion, adaptation")
                            link(BiomarkersView(), "drop.fill", "Biomarkers", "Labs, Health import, doctor export")
                            link(InsightsView(), "sparkles", "Insights", "What your own data says")
                            link(OrganRotationView(), "calendar", "Organ rotation", "Gaps and weekly caps")
                            link(SourcingView(), "dollarsign.circle", "Sourcing & cost", "Spend, suppliers, butchers nearby")
                            link(DietModeView(), "slider.horizontal.3", "Diet mode", mode.label)
                        }

                        Disclaimer(text: "Primal provides risk information, not medical advice and never a clearance that food is safe. Eating raw or undercooked animal products can cause serious illness, especially for children, older adults, pregnant people and anyone immunocompromised.")
                        Spacer().frame(height: 100)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showLog) { NavigationStack { RawLogView() } }
        }
    }

    private var flagged: Int { batches.filter { !$0.recallFlag.isEmpty }.count }

    private func link<D: View>(_ dest: D, _ icon: String, _ title: String, _ detail: String, badge: String? = nil) -> some View {
        NavigationLink { dest } label: { NavRow(icon: icon, title: title, detail: detail, badge: badge, badgeColor: .ncError) }
            .buttonStyle(SmoothButtonStyle())
    }

    private var disclaimerGate: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.ncOrange)
                Text("Read before you start").font(.system(size: 15, weight: .bold)).foregroundColor(.ncPrimary)
            }
            Text("Raw and undercooked animal foods can carry bacteria, parasites and prions. Primal scores risk from what you log, but a low score is never a promise that food is safe. Raw poultry, wild game and ground meat carry the highest risk. This is not medical advice.")
                .font(.system(size: 13)).foregroundColor(.ncSecondary)
            Button("I understand") { withAnimation(.snappy) { accepted = true } }.buttonStyle(.primal)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ncOrange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.ncOrange.opacity(0.35), lineWidth: 1))
    }

    private var dietCard: some View {
        let r = DietRater.rate(meals: meals, days: 7)
        return NavigationLink { DietRaterView() } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    FieldLabel(text: "Diet rater · 7 days")
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundColor(.ncOutline)
                }
                Text(r.tier.title).font(.system(size: 24, weight: .bold)).foregroundColor(.ncPrimary)
                SpectrumBar(position: r.position, active: r.tier != .insufficient)
                if r.tier != .insufficient {
                    HStack(spacing: 8) {
                        StatTile(title: "Raw", value: "\(Int(r.rawPct))%", color: .ncError)
                        StatTile(title: "Animal", value: "\(Int(r.animalPct))%")
                        StatTile(title: "Plant", value: "\(Int(r.plantPct))%", color: .ncGreen)
                    }
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).glassCard()
        }
        .buttonStyle(SmoothButtonStyle())
    }

    private var safetyCard: some View {
        let recent = meals.filter { $0.date >= Calendar.current.date(byAdding: .day, value: -3, to: Date())! && $0.riskScore > 0 }
        let worst = recent.max { $0.riskScore < $1.riskScore }
        let frozen = batches.filter(\.isCurrentlyFrozen).count
        return NavigationLink { SafetyView() } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    FieldLabel(text: "Food safety · 3 days")
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundColor(.ncOutline)
                }
                if let worst {
                    let level = levelFor(worst.riskScore)
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(worst.riskScore))").font(.system(size: 34, weight: .bold).monospacedDigit()).foregroundColor(.ncPrimary)
                        Text("highest risk score").font(.system(size: 12)).foregroundColor(.ncSecondary)
                        Spacer()
                        Tag(text: level.label, color: level.color)
                    }
                    BandGauge(value: worst.riskScore / 100, color: level.color)
                    Text(worst.foodName).font(.system(size: 12)).foregroundColor(.ncSecondary).lineLimit(1)
                } else {
                    Text("No raw items logged in the last 3 days.").font(.system(size: 13)).foregroundColor(.ncSecondary)
                }
                HStack(spacing: 8) {
                    if flagged > 0 { Tag(text: "\(flagged) possible recall", color: .ncError) }
                    Tag(text: "\(frozen) frozen batch\(frozen == 1 ? "" : "es")", color: .ncSky)
                    Tag(text: "\(batches.count) batches")
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).glassCard()
        }
        .buttonStyle(SmoothButtonStyle())
    }

    private var timingCard: some View {
        RawCard(title: "Meal timing") {
            if let t = NutrientAnalyzer.timing(meals) {
                HStack(spacing: 8) {
                    StatTile(title: "Pattern", value: t.pattern)
                    StatTile(title: "Meals/day", value: String(format: "%.1f", t.mealsPerDay))
                    StatTile(title: "Eating window", value: String(format: "%.1f h", t.windowHours))
                }
            } else {
                Text("Log meals to see how many sittings you have per day.").font(.system(size: 13)).foregroundColor(.ncSecondary)
            }
        }
    }

    private func levelFor(_ s: Double) -> RiskLevel {
        let t = RiskEngine.config.levelThresholds
        return s < t[0] ? .lower : s < t[1] ? .moderate : s < t[2] ? .elevated : .high
    }
}
