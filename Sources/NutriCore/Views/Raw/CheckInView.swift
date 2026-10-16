import SwiftUI
import SwiftData

struct CheckInView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \OutcomeLog.date, order: .reverse) private var logs: [OutcomeLog]
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @Query private var hydration: [DailyHydration]
    @AppStorage(RawSettings.startKey) private var startInterval = 0.0

    @State private var log: OutcomeLog?

    private var dayCount: Int? {
        startInterval > 0 ? (Calendar.current.dateComponents([.day], from: Date(timeIntervalSince1970: startInterval), to: Date()).day ?? 0) + 1 : nil
    }

    var body: some View {
        RawScreen(title: "Daily check-in") {
            adaptationCard

            if let log {
                RawCard(title: "How do you feel?", trailing: "Today") {
                    VStack(spacing: 18) {
                        ScalePicker(title: "Energy", value: bind(log, \.energy))
                        ScalePicker(title: "Mood", value: bind(log, \.mood))
                        ScalePicker(title: "Focus", value: bind(log, \.focus))
                        ScalePicker(title: "Sleep quality", lowLabel: "Poor", highLabel: "Great", value: bind(log, \.sleep))
                        ScalePicker(title: "Satiety", lowLabel: "Hungry", highLabel: "Full", value: bind(log, \.satiety))
                        ScalePicker(title: "Cravings", lowLabel: "None", highLabel: "Strong", value: bind(log, \.cravings))
                    }
                }
                RawCard(title: "Digestion (Bristol scale)") {
                    VStack(alignment: .leading, spacing: 10) {
                        FlowLayout(spacing: 8) {
                            ForEach(1...7, id: \.self) { n in
                                Chip(label: "\(n)", selected: log.bristol == n) { log.bristol = log.bristol == n ? 0 : n; save() }
                            }
                        }
                        Text(bristolText(log.bristol)).font(.system(size: 13)).foregroundColor(.ncSecondary)
                    }
                }
                RawCard(title: "Training") {
                    VStack(spacing: 18) {
                        ScalePicker(title: "Performance", value: bind(log, \.training))
                        ScalePicker(title: "Recovery", value: bind(log, \.recovery))
                    }
                }
                RawCard(title: "Adaptation symptoms") {
                    VStack(alignment: .leading, spacing: 10) {
                        FlowLayout(spacing: 8) {
                            ForEach(KetoFluSymptom.allCases) { s in
                                Chip(label: s.label, selected: log.ketoFluList.contains(s)) { toggle(s, in: log) }
                            }
                        }
                        RawField(title: "Other symptoms (skin, joints…)", text: Binding(get: { log.customSymptoms }, set: { log.customSymptoms = $0; save() }))
                    }
                }
            }
            Disclaimer(text: "Self-tracking for your own patterns. Not a diagnosis; see a clinician for symptoms that worry you.")
        }
        .onAppear(perform: loadToday)
    }

    @ViewBuilder private var adaptationCard: some View {
        RawCard(title: "Adaptation tracker", trailing: dayCount.map { "Day \($0)" }) {
            VStack(alignment: .leading, spacing: 10) {
                if let d = dayCount {
                    Text(d <= 14 ? "Early days. Headaches, cramps and fatigue are commonly reported in the first weeks and are often linked to fluid and electrolyte intake."
                                 : "You're past the first two weeks.")
                        .font(.system(size: 13)).foregroundColor(.ncSecondary)
                    if let msg = electrolyteLink { Text(msg).font(.system(size: 13, weight: .medium)).foregroundColor(.ncPrimary) }
                } else {
                    Text("Set your diet start date in Diet mode to count adaptation days.").font(.system(size: 13)).foregroundColor(.ncSecondary)
                }
            }
        }
    }

    /// Compares sodium intake (food + added) on days with and without keto-flu symptoms.
    private var electrolyteLink: String? {
        let cal = Calendar.current
        func sodium(_ day: Date) -> Double {
            meals.filter { cal.isDate($0.date, inSameDayAs: day) }.totalSodium + hydration.filter { cal.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.addedSodiumMg }
        }
        let sym = logs.filter { !$0.ketoFluList.isEmpty }, clear = logs.filter { $0.ketoFluList.isEmpty && $0.energy > 0 }
        guard sym.count >= 2, clear.count >= 2 else { return nil }
        let a = sym.map { sodium($0.date) }.reduce(0, +) / Double(sym.count)
        let b = clear.map { sodium($0.date) }.reduce(0, +) / Double(clear.count)
        return "Sodium averages \(Int(a)) mg on symptom days vs \(Int(b)) mg on clear days."
    }

    private func loadToday() {
        if let existing = logs.first(where: { Calendar.current.isDateInToday($0.date) }) { log = existing; return }
        let l = OutcomeLog(); l.date = Calendar.current.startOfDay(for: Date())
        context.insert(l); try? context.save(); log = l
    }
    private func bind(_ l: OutcomeLog, _ kp: ReferenceWritableKeyPath<OutcomeLog, Int>) -> Binding<Int> {
        Binding(get: { l[keyPath: kp] }, set: { l[keyPath: kp] = $0; save() })
    }
    private func toggle(_ s: KetoFluSymptom, in l: OutcomeLog) {
        var cur = l.ketoFluList
        if let i = cur.firstIndex(of: s) { cur.remove(at: i) } else { cur.append(s) }
        l.ketoFlu = cur.map(\.rawValue).joined(separator: ",")
        save()
    }
    private func save() { try? context.save() }
    private func bristolText(_ n: Int) -> String {
        switch n {
        case 1: "Type 1 — separate hard lumps"
        case 2: "Type 2 — lumpy and sausage-like"
        case 3: "Type 3 — sausage with cracks"
        case 4: "Type 4 — smooth, soft sausage"
        case 5: "Type 5 — soft blobs"
        case 6: "Type 6 — mushy, fluffy pieces"
        case 7: "Type 7 — entirely liquid"
        default: "Tap the type that matches. Types 3–4 are generally considered typical."
        }
    }
}

struct InsightsView: View {
    @Query private var meals: [MealEntry]
    @Query private var outcomes: [OutcomeLog]
    @Query private var sun: [SunSession]
    @Query private var hydration: [DailyHydration]

    var body: some View {
        let insights = InsightsEngine.compute(meals: meals, outcomes: outcomes, sun: sun, hydration: hydration)
        RawScreen(title: "Insights") {
            if insights.isEmpty {
                RawCard(title: "Still learning") {
                    Text("Log food and a daily check-in for a couple of weeks. Patterns appear once there are at least 3 days on each side of a comparison.")
                        .font(.system(size: 13)).foregroundColor(.ncSecondary)
                    Text("\(outcomes.filter { $0.energy > 0 }.count) check-ins so far").font(.system(size: 13, weight: .semibold)).foregroundColor(.ncPrimary)
                }
            }
            ForEach(insights.prefix(12)) { i in
                RawCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: i.diff > 0 ? "arrow.up.right" : "arrow.down.right")
                                .foregroundColor(i.diff > 0 ? .ncGreen : .ncOrange)
                            Text(i.text).font(.serif(18)).foregroundColor(.ncPrimary)
                        }
                        Text("\(i.withDays) vs \(i.withoutDays) days").font(.system(size: 12)).foregroundColor(.ncSecondary)
                    }
                }
            }
            Disclaimer(text: "These are patterns in your own logs, not proof that one thing caused another.")
        }
    }
}
