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
            HStack(spacing: 8) {
                ForEach([7, 14, 30], id: \.self) { d in
                    Chip(label: "\(d) days", selected: days == d) { days = d }
                }
            }

            RawCard(title: "Where your diet sits", index: "01") {
                VStack(alignment: .leading, spacing: 18) {
                    Text(r.tier.title).font(.serif(32)).foregroundColor(.ncPrimary)
                        .contentTransition(.opacity)
                    Text(r.tier.blurb).font(.ui(size: 15)).foregroundColor(.ncSecondary)
                    SpectrumBar(position: r.position, active: r.tier != .insufficient).padding(.top, 8)
                    if r.tier != .insufficient {
                        ShareCardButton(title: "Share my diet") {
                            DietTierCard(tier: r.tier.title, days: days, rawPct: r.rawPct, animalPct: r.animalPct)
                        }
                    }
                }
            }

            if r.tier != .insufficient {
                RawCard(title: "Calorie sources", trailing: "\(Int(r.kcal).formatted()) kcal", index: "02") {
                    VStack(alignment: .leading, spacing: 12) {
                        CompositionBar(segments: [
                            ("Raw animal", r.rawPct, .ncPrimary),
                            ("Cooked animal", r.cookedAnimalPct, .ncPrimary.opacity(0.55)),
                            ("Dairy & eggs", r.dairyEggPct, .ncPrimary.opacity(0.3)),
                            ("Plant", r.plantPct, .ncPrimary.opacity(0.15)),
                        ])
                        StatStrip(items: [
                            .init(label: "Raw", value: "\(Int(r.rawPct))%"),
                            .init(label: "Animal", value: "\(Int(r.animalPct))%"),
                            .init(label: "Plant", value: "\(Int(r.plantPct))%"),
                        ])
                        Text("Avg \(Int(r.avgCarbsG)) g carbs on logged days").font(.ui(size: 13)).foregroundColor(.ncSecondary)
                    }
                }

                RawCard(title: "Against your goal", trailing: mode.label, index: "03") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(comparison(r)).font(.ui(size: 13)).foregroundColor(.ncPrimary)
                        if r.avgCarbsG > mode.carbCap {
                            Text("Average carbs (\(Int(r.avgCarbsG)) g) are above the usual \(Int(mode.carbCap)) g/day for this mode.")
                                .font(.ui(size: 13)).foregroundColor(.ncOrange)
                        }
                    }
                }

                if !r.steps.isEmpty {
                    RawCard(title: "What moves the needle", index: "04") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(r.steps, id: \.self) { Text($0).font(.ui(size: 15)).foregroundColor(.ncPrimary).lineSpacing(3) }
                        }
                    }
                }
            }

            RawCard(title: "How it's worked out", index: "05") {
                Text("Foods tagged with a species count as meat, fish, organs or fat; untagged foods are matched by name. Raw, thawed and aged count fully raw, seared 75%, rare 50%, cooked 0%. Calories are weighted by what you log, so unlogged meals aren't counted.")
                    .font(.ui(size: 13)).foregroundColor(.ncSecondary)
            }
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title).serifCaps(10).foregroundColor(.ncSecondary).lineLimit(1)
            Text(value).font(.metric(22)).foregroundColor(color).lineLimit(1).minimumScaleFactor(0.55)
        }
        .padding(.leading, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { Rectangle().fill(Color.ncPrimary.opacity(0.14)).frame(width: 1) }
    }
}

/// Omnivore → Raw scale: a hairline track with four ticks and a square marker.
struct SpectrumBar: View {
    let position: Double
    let active: Bool
    private let labels = ["Omnivore", "Animal-based", "Carnivore", "Raw"]
    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.ncPrimary.opacity(0.22)).frame(height: 1).offset(y: 0)
                    ForEach(0..<4) { i in
                        Rectangle().fill(Color.ncPrimary.opacity(0.4)).frame(width: 1, height: 9)
                            .offset(x: (w - 1) * CGFloat(i) / 3)
                    }
                    Rectangle().fill(Color.ncPrimary).frame(width: max(0, w * position), height: 2)
                        .opacity(active ? 1 : 0)
                    if active {
                        Rectangle().fill(Color.ncPrimary).frame(width: 12, height: 12)
                            .offset(x: (w - 12) * position)
                            .animation(.smooth(duration: 0.7), value: position)
                    }
                }
                .frame(height: 14)
            }
            .frame(height: 14)
            HStack {
                ForEach(labels.indices, id: \.self) { i in
                    Text(labels[i]).serifCaps(9, tracking: 1.4).foregroundColor(.ncSecondary)
                    if i < labels.count - 1 { Spacer(minLength: 4) }
                }
            }
        }
    }
}

struct CompositionBar: View {
    let segments: [(String, Double, Color)]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geo in
                let total = max(segments.reduce(0) { $0 + $1.1 }, 0.001)
                HStack(spacing: 2) {
                    ForEach(segments.indices, id: \.self) { i in
                        let w = geo.size.width * segments[i].1 / total
                        if segments[i].1 > 0.5 {
                            Rectangle().fill(segments[i].2).frame(width: max(3, w - 2))
                        }
                    }
                }
            }
            .frame(height: 6)
            VStack(spacing: 8) {
                ForEach(segments.indices, id: \.self) { i in
                    HStack(spacing: 10) {
                        Rectangle().fill(segments[i].2).frame(width: 10, height: 10)
                        Text(segments[i].0).font(.ui(size: 14)).foregroundColor(.ncPrimary)
                        Spacer()
                        Text("\(Int(segments[i].1))%").font(.metric(14)).foregroundColor(.ncSecondary)
                    }
                }
            }
        }
        .animation(.smooth, value: segments.map { $0.1 })
    }
}
