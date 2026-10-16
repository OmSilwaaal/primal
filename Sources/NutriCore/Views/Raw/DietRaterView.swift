import SwiftUI
import SwiftData

struct DietRaterView: View {
    @Query(sort: \MealEntry.date) private var allMeals: [MealEntry]
    @AppStorage(RawSettings.modeKey) private var modeRaw = DietMode.rawCarnivore.rawValue
    @State private var days = 7

    private var rating: DietRating { DietRater.rate(meals: allMeals, days: days) }
    private var mode: DietMode { DietMode(rawValue: modeRaw) ?? .rawCarnivore }

    var body: some View {
        let r = rating
        RawScreen(title: "Diet rater") {
            Picker("Window", selection: $days) {
                Text("7 days").tag(7); Text("14 days").tag(14); Text("30 days").tag(30)
            }
            .pickerStyle(.segmented)

            RawCard {
                VStack(alignment: .leading, spacing: 14) {
                    FieldLabel(text: "Where your diet sits")
                    Text(r.tier.title).font(.system(size: 28, weight: .bold)).foregroundColor(.ncPrimary)
                        .contentTransition(.opacity)
                    Text(r.tier.blurb).font(.system(size: 13)).foregroundColor(.ncSecondary)
                    SpectrumBar(position: r.position, active: r.tier != .insufficient)
                }
            }

            if r.tier != .insufficient {
                RawCard(title: "Where the calories come from", trailing: "\(Int(r.kcal)) kcal · \(r.mealCount) items") {
                    VStack(alignment: .leading, spacing: 12) {
                        CompositionBar(segments: [
                            ("Raw animal", r.rawPct, .ncError),
                            ("Cooked animal", r.cookedAnimalPct, .ncOrange),
                            ("Dairy & eggs", r.dairyEggPct, .ncSky),
                            ("Plant", r.plantPct, .ncGreen),
                        ])
                        HStack(spacing: 8) {
                            StatTile(title: "Raw", value: "\(Int(r.rawPct))%", color: .ncError)
                            StatTile(title: "Animal", value: "\(Int(r.animalPct))%", color: .ncPrimary)
                            StatTile(title: "Plant", value: "\(Int(r.plantPct))%", color: .ncGreen)
                        }
                        Text("Avg \(Int(r.avgCarbsG)) g carbs on logged days").font(.system(size: 12)).foregroundColor(.ncSecondary)
                    }
                }

                RawCard(title: "Against your goal", trailing: mode.label) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(comparison(r)).font(.system(size: 13)).foregroundColor(.ncPrimary)
                        if r.avgCarbsG > mode.carbCap {
                            Text("Average carbs (\(Int(r.avgCarbsG)) g) are above the usual \(Int(mode.carbCap)) g/day for this mode.")
                                .font(.system(size: 12)).foregroundColor(.ncOrange)
                        }
                    }
                }

                if !r.steps.isEmpty {
                    RawCard(title: "What moves the needle") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(r.steps, id: \.self) { Text("• \($0)").font(.system(size: 13)).foregroundColor(.ncSecondary) }
                        }
                    }
                }
            }

            RawCard(title: "How it's worked out") {
                Text("Foods tagged with a species count as meat, fish, organs or fat; untagged foods are matched by name. Raw, thawed and aged count fully raw, seared 75%, rare 50%, cooked 0%. Calories are weighted by what you log, so unlogged meals aren't counted.")
                    .font(.system(size: 12)).foregroundColor(.ncSecondary)
            }
            Disclaimer()
        }
    }

    private func comparison(_ r: DietRating) -> String {
        let targetTier: DietTier
        switch mode {
        case .rawCarnivore: targetTier = .rawCarnivore
        case .strictCarnivore: targetTier = .cookedCarnivore
        case .carnivoreDairyEggs: targetTier = .carnivoreDairyEggs
        case .animalBased: targetTier = .animalBased
        }
        if r.tier == targetTier { return "You're landing right where your diet mode says: \(r.tier.title)." }
        return "Your mode is \(mode.label), but the last \(days) days read as \(r.tier.title)."
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var color: Color = .ncPrimary
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundColor(.ncSecondary)
            Text(value).font(.system(size: 20, weight: .bold).monospacedDigit()).foregroundColor(color)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ncSurfaceContLow, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

struct SpectrumBar: View {
    let position: Double
    let active: Bool
    private let labels = ["Omnivore", "Animal-based", "Carnivore", "Raw"]
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(LinearGradient(colors: [.ncGreen.opacity(0.5), .ncSky.opacity(0.5), .ncOrange.opacity(0.6), .ncError.opacity(0.8)],
                                                  startPoint: .leading, endPoint: .trailing))
                        .frame(height: 10)
                    if active {
                        Circle().fill(Color.ncPrimary).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.ncBg, lineWidth: 3))
                            .offset(x: (geo.size.width - 22) * position)
                            .animation(.smooth(duration: 0.7), value: position)
                    }
                }
                .frame(height: 22)
            }
            .frame(height: 22)
            HStack {
                ForEach(labels.indices, id: \.self) { i in
                    Text(labels[i]).font(.system(size: 10, weight: .medium)).foregroundColor(.ncSecondary)
                    if i < labels.count - 1 { Spacer() }
                }
            }
        }
    }
}

struct CompositionBar: View {
    let segments: [(String, Double, Color)]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let total = max(segments.reduce(0) { $0 + $1.1 }, 0.001)
                HStack(spacing: 2) {
                    ForEach(segments.indices, id: \.self) { i in
                        let w = geo.size.width * segments[i].1 / total
                        if segments[i].1 > 0.5 {
                            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(segments[i].2).frame(width: max(4, w - 2))
                        }
                    }
                }
            }
            .frame(height: 12)
            FlowLayout(spacing: 12) {
                ForEach(segments.indices, id: \.self) { i in
                    HStack(spacing: 5) {
                        Circle().fill(segments[i].2).frame(width: 7, height: 7)
                        Text("\(segments[i].0) \(Int(segments[i].1))%").font(.system(size: 11)).foregroundColor(.ncSecondary)
                    }
                }
            }
        }
        .animation(.smooth, value: segments.map { $0.1 })
    }
}
