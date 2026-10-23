import SwiftUI
import SwiftData

/// The Raw tab: diet position, food safety and the carnivore-specific tools in one place.
struct RawHubView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @Query private var batches: [SourceBatch]
    @AppStorage(RawSettings.modeKey) private var modeRaw = DietMode.rawCarnivore.rawValue
    @AppStorage(RawSettings.fatMinKey) private var fatMin = 0.0
    @AppStorage(RawSettings.fatMaxKey) private var fatMax = 0.0
    @State private var showLog = false

    private var mode: DietMode { DietMode(rawValue: modeRaw) ?? .rawCarnivore }
    private var fatRange: ClosedRange<Double> { (fatMin > 0 && fatMax > fatMin) ? fatMin...fatMax : mode.fatRange }
    private var flagged: Int { batches.filter { !$0.recallFlag.isEmpty }.count }

    var body: some View {
        Group {
            ZStack {
                AppBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Space.section) {
                        VStack(alignment: .leading, spacing: 24) {
                            PageHeader(title: "Raw", caption: mode.label)
                            Button { showLog = true } label: { Label("Log raw food", systemImage: "plus") }
                                .buttonStyle(.vitalis)
                        }

                        positionSection
                        safetySection
                        FatProteinGauge(todayPct: NutrientAnalyzer.fatCaloriePct(meals.filter { Calendar.current.isDateInToday($0.date) }),
                                        weekPct: NutrientAnalyzer.fatCaloriePct(NutrientAnalyzer.window(meals, days: 7)),
                                        range: fatRange, index: "03")
                        LiverBudgetCard(budget: NutrientAnalyzer.liverBudget(meals), index: "04")
                        timingSection

                        RawCard(title: "Index", index: "06") {
                            VStack(spacing: 0) {
                                link(NutrientsView(), "A", "Nutrients", "Gaps, omega ratio, purines")
                                link(SafetyView(), "B", "Food safety", "Batches, freezer log, recalls", badge: flagged > 0 ? "\(flagged) recall" : nil)
                                link(CheckInView(), "C", "Daily check-in", "Energy, mood, digestion")
                                link(BiomarkersView(), "D", "Biomarkers", "Labs, Health import, export")
                                link(InsightsView(), "E", "Insights", "What your own data says")
                                link(OrganRotationView(), "F", "Organ rotation", "Gaps and weekly caps")
                                link(SourcingView(), "G", "Sourcing & cost", "Spend, suppliers, butchers")
                                link(DietModeView(), "H", "Diet mode", mode.label)
                            }
                        }

                    }
                    .padding(.horizontal, Space.margin)
                    .padding(.top, 12)
                    .padding(.bottom, 140)
                }
            }
            .sheet(isPresented: $showLog) { NavigationStack { RawLogView() } }
        }
    }

    private func link<D: View>(_ dest: D, _ index: String, _ title: String, _ detail: String, badge: String? = nil) -> some View {
        NavigationLink { dest } label: {
            NavRow(icon: "", title: title, detail: detail, badge: badge, badgeColor: .ncError, index: index)
        }
        .buttonStyle(.plain)
    }


    private var positionSection: some View {
        let r = DietRater.rate(meals: meals, days: 7)
        return RawCard(title: "Position", trailing: "7 days", index: "01") {
            VStack(alignment: .leading, spacing: 24) {
                NavigationLink { DietRaterView() } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(r.tier.title).font(.serif(30)).foregroundColor(.ncPrimary).multilineTextAlignment(.leading)
                            Text(r.tier.blurb).font(.ui(size: 14)).foregroundColor(.ncSecondary).multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.ui(size: 14)).foregroundColor(.ncSecondary)
                    }
                }
                .buttonStyle(.plain)
                SpectrumBar(position: r.position, active: r.tier != .insufficient)
                if r.tier != .insufficient {
                    StatStrip(items: [
                        .init(label: "Raw", value: "\(Int(r.rawPct))%"),
                        .init(label: "Animal", value: "\(Int(r.animalPct))%"),
                        .init(label: "Plant", value: "\(Int(r.plantPct))%"),
                    ])
                }
            }
        }
    }

    private var safetySection: some View {
        let recent = meals.filter { $0.date >= Calendar.current.date(byAdding: .day, value: -3, to: Date())! && $0.riskScore > 0 }
        let worst = recent.max { $0.riskScore < $1.riskScore }
        let frozen = batches.filter(\.isCurrentlyFrozen).count
        return RawCard(title: "Food safety", trailing: "3 days", index: "02") {
            NavigationLink { SafetyView() } label: {
                VStack(alignment: .leading, spacing: 18) {
                    if let worst {
                        let level = levelFor(worst.riskScore)
                        HStack(alignment: .firstTextBaseline) {
                            Metric(value: "\(Int(worst.riskScore))", unit: "/ 100", caption: "Highest risk — \(worst.foodName)", size: 52)
                            Spacer()
                            Tag(text: level.label, color: level.color)
                        }
                        LineGauge(value: worst.riskScore / 100, tint: level.color)
                    } else {
                        Text("No raw items logged in the last three days.").font(.serif(16)).italic().foregroundColor(.ncSecondary)
                    }
                    HStack(spacing: 8) {
                        if flagged > 0 { Tag(text: "\(flagged) possible recall", color: .ncError) }
                        Tag(text: "\(frozen) frozen")
                        Tag(text: "\(batches.count) batches")
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.ui(size: 14)).foregroundColor(.ncSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var timingSection: some View {
        RawCard(title: "Meal timing", trailing: "7 days", index: "05") {
            if let t = NutrientAnalyzer.timing(meals) {
                StatStrip(items: [
                    .init(label: "Pattern", value: t.pattern),
                    .init(label: "Meals / day", value: String(format: "%.1f", t.mealsPerDay)),
                    .init(label: "Window", value: String(format: "%.1fh", t.windowHours)),
                ])
            } else {
                Text("Log meals to see how many sittings you have each day.").font(.serif(16)).italic().foregroundColor(.ncSecondary)
            }
        }
    }

    private func levelFor(_ s: Double) -> RiskLevel {
        let t = RiskEngine.config.levelThresholds
        return s < t[0] ? .lower : s < t[1] ? .moderate : s < t[2] ? .elevated : .high
    }
}
