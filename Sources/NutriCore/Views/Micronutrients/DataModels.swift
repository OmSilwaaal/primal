import SwiftUI
import SwiftData

// Shared by the Data screen's carousel, cards and detail sheet.

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

/// The wheel's cards, each with its own drawing and its own scene behind the whole screen. Seasonal eating is a
/// placeholder for now.
enum DataGroupKind: String, CaseIterable, Identifiable, Hashable {
    /// Its line drawing, faint in the card's bottom-right corner like the Home tiles'.
    var art: LineArt {
        switch self {
        case .macros: .wheat
        case .vitamins: .citrus
        case .minerals: .mountain
        case .raw: .rawCut
        case .seasonal: .seasonalSprig
        }
    }

    /// The photo behind the whole screen while this card is centred (blurred, like every backdrop).
    var scene: Backdrop {
        switch self {
        case .macros: .desert
        case .vitamins: .forest
        case .minerals: .fog
        case .raw: .night
        case .seasonal: .ocean
        }
    }

    case macros, vitamins, minerals, raw, seasonal
    var id: Self { self }

    var title: String {
        switch self {
        case .macros: "Macros"
        case .vitamins: "Vitamins"
        case .minerals: "Minerals"
        case .raw: "Raw"
        case .seasonal: "Seasonal"
        }
    }

    /// The group's colour: sand, Moss, lime-green, Ember.
    var color: Color {
        switch self {
        case .macros: .ncMoss                  // #A2CD8B
        case .vitamins: Color(hex: "#BEDD7A")
        case .minerals: .ncEmber               // #F37E61
        case .raw: Color(hex: "#C8584A")
        case .seasonal: .ncOrange              // sand #D2B98A
        }
    }

    /// The dark base under the colour.
    var base: Color {
        switch self {
        case .macros: Color(hex: "#0D1710")
        case .vitamins: Color(hex: "#111808")
        case .minerals: Color(hex: "#1D0E0A")
        case .raw: Color(hex: "#1A0B0A")
        case .seasonal: Color(hex: "#17120C")
        }
    }

    var group: NutrientGroup? {
        switch self {
        case .seasonal: nil
        case .macros: .macros
        case .vitamins: .vitamins
        case .minerals: .minerals
        case .raw: .raw
        }
    }
}

/// One pill on a card: a nutrient's short name (or, on Seasonal, the season); low ones are Ember.
struct PillModel: Identifiable, Hashable {
    let id: String
    let text: String
    let isLow: Bool
}

/// What a card and its sheet show for one group.
struct DataGroupSummary: Identifiable, Hashable {
    let kind: DataGroupKind
    /// 0–100, the repo's scoring: the average share of each item's target met, each capped at 100%.
    let score: Int
    /// The nutrients behind it (none yet for Seasonal).
    let items: [NutrientInfo]
    let pills: [PillModel]
    var id: DataGroupKind { kind }

    /// Seasonal eating has no data yet.
    var isComingSoon: Bool { kind == .seasonal }

    var met: Int { items.filter(\.isMet).count }
    var low: Int { items.filter(\.isDeficient).count }
    var onTrack: Int { items.count - met - low }

    static func == (a: Self, b: Self) -> Bool { a.kind == b.kind && a.score == b.score && a.items.count == b.items.count }
    func hash(into h: inout Hasher) { h.combine(kind) }

    static func score(_ list: [NutrientInfo]) -> Int {
        guard !list.isEmpty else { return 0 }
        return Int((list.map(\.progress).reduce(0, +) / Double(list.count) * 100).rounded())
    }

    /// Macros, Vitamins, Minerals, then Seasonal eating (coming soon; this season's name as its only pill).
    static func make(from nutrients: [NutrientInfo], season: String = Season(date: .now, latitude: nil).name) -> [DataGroupSummary] {
        let groups: [DataGroupSummary] = [DataGroupKind.macros, .vitamins, .minerals, .raw].map { kind in
            let items = nutrients.filter { $0.group == kind.group }
            return DataGroupSummary(kind: kind, score: score(items), items: items,
                                    pills: items.map { PillModel(id: $0.id, text: $0.short, isLow: $0.isDeficient) })
        }
        let seasonal = DataGroupSummary(kind: .seasonal, score: 0, items: [],
                                        pills: [PillModel(id: "season", text: season, isLow: false)])
        return groups + [seasonal]
    }
}

extension NutrientInfo {
    /// Share of the target, uncapped.
    var share: Double { goal > 0 ? current / goal : 0 }

    /// The short name on a card's pill.
    var short: String {
        switch id {
        case "cal": "Kcal"
        case "pro": "Prot"
        case "carb": "Carb"
        case "fat": "Fat"
        case "fib": "Fibr"
        case "va": "A"
        case "vc": "C"
        case "vd": "D"
        case "ve": "E"
        case "vk": "K"
        case "b1": "B1"
        case "b2": "B2"
        case "b3": "B3"
        case "b6": "B6"
        case "fol": "B9"
        case "b12": "B12"
        case "ca": "Ca"
        case "fe": "Fe"
        case "mg": "Mg"
        case "ph": "P"
        case "k": "K"
        case "zn": "Zn"
        case "se": "Se"
        case "cu": "Cu"
        case "mn": "Mn"
        case "raw": "Raw"
        case "org": "Organ"
        case "chol": "Chol"
        case "o3": "Ω-3"
        case "k2": "K2"
        case "iod": "I"
        default: String(name.prefix(4))
        }
    }
}

extension NutrientInfo: Hashable {
    public static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.current == b.current && a.goal == b.goal }
    public func hash(into h: inout Hasher) { h.combine(id) }
}

/// The daily streak: days in a row with intake in range of the calorie goal (85–110%), and the last seven days.
struct StreakSummary {
    let days: Int
    /// Oldest first, ending today.
    let week: [Bool]

    static func make(meals: [MealEntry], goal: Double) -> StreakSummary {
        let cal = Calendar.current
        var byDay: [Date: Double] = [:]
        for m in meals { byDay[cal.startOfDay(for: m.date), default: 0] += m.calories }
        let today = cal.startOfDay(for: .now)
        func inRange(_ d: Date) -> Bool { DayGoal(kcal: byDay[d] ?? 0, goal: goal) == .onTarget }
        let week = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }.map(inRange)
        // Count back from today, or from yesterday while today isn't in range yet.
        var day = inRange(today) ? today : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
        var n = 0
        while inRange(day), n < 365 {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return StreakSummary(days: n, week: week)
    }
}

extension View {
    /// The card a sheet zooms out of (iOS 18+).
    @ViewBuilder func zoomSource(id: some Hashable, in ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) { matchedTransitionSource(id: id, in: ns) } else { self }
    }

    /// Zooms a sheet out of its source card (iOS 18+, not under Reduce Motion); a standard sheet otherwise.
    @ViewBuilder func zoomsFrom(id: some Hashable, in ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *), !UIAccessibility.isReduceMotionEnabled {
            navigationTransition(.zoom(sourceID: id, in: ns))
        } else {
            self
        }
    }
}

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


/// Synthetic summaries matching the design (Macros 77, Vitamins 80, Minerals 68; Vitamin D 34%,
/// Copper 44% and Magnesium 48% low; a 5-of-7 streak), for the card and sheet previews.
enum DataPreview {
    private static func item(_ id: String, _ name: String, _ unit: String, _ group: NutrientGroup, _ pct: Double,
                             goal: Double = 100) -> NutrientInfo {
        NutrientInfo(id: id, name: name, unit: unit, icon: "circle", group: group, current: goal * pct / 100, goal: goal)
    }

    static let macros = [
        item("cal", "Calories", "kcal", .macros, 82, goal: 2400), item("pro", "Protein", "g", .macros, 66, goal: 140),
        item("carb", "Carbs", "g", .macros, 71, goal: 280), item("fat", "Fat", "g", .macros, 92, goal: 80),
        item("fib", "Fiber", "g", .macros, 74, goal: 38),
    ]
    static let vitamins = [
        item("va", "Vitamin A", "mcg", .vitamins, 92, goal: 900), item("vc", "Vitamin C", "mg", .vitamins, 95, goal: 90),
        item("vd", "Vitamin D", "mcg", .vitamins, 34, goal: 15), item("ve", "Vitamin E", "mg", .vitamins, 70, goal: 15),
        item("vk", "Vitamin K", "mcg", .vitamins, 88, goal: 120), item("b1", "Thiamin (B1)", "mg", .vitamins, 90, goal: 1.2),
        item("b2", "Riboflavin (B2)", "mg", .vitamins, 85, goal: 1.3), item("b3", "Niacin (B3)", "mg", .vitamins, 78, goal: 16),
        item("b6", "Vitamin B6", "mg", .vitamins, 72, goal: 1.3), item("fol", "Folate", "mcg", .vitamins, 82, goal: 400),
        item("b12", "Vitamin B12", "mcg", .vitamins, 94, goal: 2.4),
    ]
    static let minerals = [
        item("ca", "Calcium", "mg", .minerals, 72, goal: 1000), item("fe", "Iron", "mg", .minerals, 90, goal: 8),
        item("mg", "Magnesium", "mg", .minerals, 48, goal: 420), item("ph", "Phosphorus", "mg", .minerals, 85, goal: 700),
        item("k", "Potassium", "mg", .minerals, 60, goal: 3400), item("zn", "Zinc", "mg", .minerals, 70, goal: 11),
        item("se", "Selenium", "mcg", .minerals, 75, goal: 55), item("cu", "Copper", "mg", .minerals, 44, goal: 0.9),
        item("mn", "Manganese", "mg", .minerals, 68, goal: 2.3),
    ]

    static var summaries: [DataGroupSummary] { DataGroupSummary.make(from: macros + vitamins + minerals, season: "Fall") }

    static let streak = StreakSummary(days: 5, week: [false, false, true, true, true, true, true])
}
#endif
