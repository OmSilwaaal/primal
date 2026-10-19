import SwiftUI
import SwiftData

/// The Data tab: every tracked vitamin and mineral against today's goal, lowest first.
struct MicronutrientsView: View {
    enum Filter: Hashable { case all, low, met }

    @Query private var meals: [MealEntry]
    @Query private var profiles: [UserProfile]
    @State private var filter: Filter = .all

    init() {
        let start = Calendar.current.startOfDay(for: .now)
        _meals = Query(filter: #Predicate<MealEntry> { $0.date >= start })
    }

    private var goals: NutrientGoals { profiles.first.map(NutrientGoals.from) ?? .default }

    private var todaysMeals: [MealEntry] {
        meals.filter { Calendar.current.isDateInToday($0.date) }
    }

    /// Vitamins and minerals, sorted low → on track → met, then by percentage.
    private var nutrients: [NutrientInfo] {
        buildNutrientList(from: todaysMeals, goals: goals)
            .filter { $0.group != .macros }
            .sorted {
                let a = IntakeStatus(progress: $0.progress), b = IntakeStatus(progress: $1.progress)
                return a != b ? a < b : $0.progress < $1.progress
            }
    }

    private func keep(_ n: NutrientInfo) -> Bool {
        switch filter {
        case .all: true
        case .low: n.isDeficient
        case .met: n.isMet
        }
    }

    var body: some View {
        let all = nutrients
        let vitamins = all.filter { $0.group == .vitamins && keep($0) }
        let minerals = all.filter { $0.group == .minerals && keep($0) }

        ZStack {
            AppBackdrop()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Today · \(all.count) tracked").monoLabel()
                        Text("Micronutrients").font(.system(size: 30, weight: .bold)).tracking(0.3).foregroundColor(.ncPrimary)
                    }
                    .padding(.horizontal, Space.margin)
                    .padding(.top, 12)

                    HStack(spacing: 0) {
                        count(all.filter(\.isMet).count, "Met ≥90%", .ncMoss)
                        count(all.filter { !$0.isMet && !$0.isDeficient }.count, "On track", .ncPrimary)
                        count(all.filter(\.isDeficient).count, "Low <50%", .ncEmber)
                    }
                    .padding(.top, 20)

                    GlassSegmented(options: [(.all, "All"), (.low, "Low"), (.met, "Met")], selection: $filter, capsule: true)
                        .padding(.horizontal, Space.margin)
                        .padding(.top, 20).padding(.bottom, 8)

                    if !vitamins.isEmpty { group("Vitamins", vitamins).padding(.top, 20) }
                    if !minerals.isEmpty { group("Minerals", minerals).padding(.top, 28) }
                    if vitamins.isEmpty && minerals.isEmpty {
                        Text(filter == .met ? "Nothing at goal yet today." : "Nothing below half of goal.")
                            .font(.system(size: 15)).foregroundColor(.ncSecondary)
                            .padding(.horizontal, Space.margin).padding(.top, 28)
                    }

                    Text("Daily goals follow NIH dietary reference intakes for your age and sex.")
                        .font(.system(size: 12)).lineSpacing(3).foregroundColor(.ncSecondary)
                        .padding(Space.margin)
                }
                .padding(.bottom, 120)
                .animation(.easeOut(duration: 0.25), value: filter)
            }
        }
    }

    private func count(_ n: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n)").font(.display(48)).tracking(-1.92).foregroundColor(color)
                .contentTransition(.numericText())
            Text(label.uppercased()).font(.mono(11)).tracking(1.32).foregroundColor(.ncSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.margin).padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private func group(_ title: String, _ items: [NutrientInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).monoLabel().padding(.horizontal, Space.margin)
            VStack(spacing: 0) {
                Rule()
                ForEach(items) { n in
                    NutrientRow(name: n.name, current: n.current, goal: n.goal, unit: n.unit)
                }
            }
            .padding(.horizontal, Space.margin)
        }
    }
}
