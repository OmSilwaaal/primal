import Foundation
import CoreLocation

/// One food that's at its best in a season, and why.
struct SeasonalFood: Identifiable, Hashable {
    let id: String
    let name: String
    /// One line on why now.
    let why: String
    /// What it's richest in.
    let nutrients: [String]
    /// Words in a logged food's name that count as eating it ("salmon" in "Fish, salmon, Atlantic, wild, raw").
    let words: Set<String>
}

/// A seasonal food and whether you've had it lately.
struct SeasonalPick: Identifiable, Hashable {
    let food: SeasonalFood
    let eaten: Bool
    var id: String { food.id }
}

/// What to eat with the seasons: six foods per season, animal-first and whole, for a temperate climate. The season
/// comes from the date and, when the phone knows roughly where it is, the hemisphere (July is winter in Sydney).
/// General guidance, not local harvest data.
enum SeasonalGuide {
    /// How far back a logged food counts as "had it lately".
    static let window = 14

    /// The phone's last known latitude, if location is allowed (no new fix is requested).
    static var latitude: Double? { CLLocationManager().location?.coordinate.latitude }

    static var currentSeason: Season { Season(date: .now, latitude: latitude) }

    static func picks(for season: Season, meals: [MealEntry], now: Date = .now) -> [SeasonalPick] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -window, to: Calendar.current.startOfDay(for: now)) ?? now
        let recent = meals.filter { $0.date >= cutoff }.map { words(in: $0.foodName) }
        return foods(for: season.kind).map { food in
            SeasonalPick(food: food, eaten: recent.contains { !$0.isDisjoint(with: food.words) })
        }
    }

    static func words(in name: String) -> Set<String> {
        Set(name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
    }

    private static func food(_ id: String, _ name: String, _ why: String, _ nutrients: [String], _ words: [String]) -> SeasonalFood {
        SeasonalFood(id: id, name: name, why: why, nutrients: nutrients, words: Set(words))
    }

    static func foods(for kind: Season.Kind) -> [SeasonalFood] {
        switch kind {
        case .spring: [
            food("lamb", "Spring lamb", "Grass-finished lambs come to market as the pasture returns.",
                 ["B12", "Zinc", "Iron"], ["lamb", "lambs"]),
            food("eggs", "Pasture eggs", "Hens lay most as the days lengthen; yolks deepen on fresh grass.",
                 ["Choline", "Vitamin A", "Vitamin D"], ["egg", "eggs", "yolk", "yolks"]),
            food("milk", "Raw milk and cream", "The spring flush: cows on new grass give the richest milk of the year.",
                 ["Calcium", "Vitamin K2", "Vitamin A"], ["milk", "cream", "kefir"]),
            food("chinook", "Wild salmon", "Spring chinook runs begin; the fattiest wild fish of the year.",
                 ["Omega-3", "Vitamin D", "Selenium"], ["salmon"]),
            food("asparagus", "Asparagus", "Among the first vegetables up after winter.",
                 ["Folate", "Vitamin K"], ["asparagus"]),
            food("strawberries", "Strawberries", "Late spring's first fruit.",
                 ["Vitamin C", "Manganese"], ["strawberry", "strawberries"]),
        ]
        case .summer: [
            food("beef", "Grass-fed beef", "Cattle on peak pasture carry more omega-3 and carotene in their fat.",
                 ["Iron", "Zinc", "B12"], ["beef", "steak", "ribeye", "sirloin", "tenderloin", "brisket"]),
            food("butter", "Summer butter", "Deep-yellow butter from summer grass has the year's most vitamin A and K2.",
                 ["Vitamin A", "Vitamin K2"], ["butter", "ghee"]),
            food("sockeye", "Sockeye salmon", "The big sockeye and coho runs; omega-3 at its peak.",
                 ["Omega-3", "Vitamin D", "B12"], ["salmon"]),
            food("berries", "Berries", "Blueberries, raspberries and blackberries ripen.",
                 ["Vitamin C", "Manganese", "Fibre"],
                 ["blueberry", "blueberries", "raspberry", "raspberries", "blackberry", "blackberries"]),
            food("stonefruit", "Stone fruit", "Peaches, cherries and apricots at their sweetest.",
                 ["Vitamin C", "Potassium"], ["peach", "peaches", "cherry", "cherries", "apricot", "apricots", "plum", "plums"]),
            food("honey", "Raw honey", "Hives are harvested from midsummer.",
                 ["Quick energy"], ["honey"]),
        ]
        case .autumn: [
            food("venison", "Venison and game", "Hunting season: lean, wild-fed meat.",
                 ["Iron", "B12", "Zinc"], ["venison", "deer", "elk", "bison", "boar", "moose"]),
            food("organs", "Liver and organs", "Traditionally the harvest season, eaten nose to tail.",
                 ["Vitamin A", "B12", "Copper", "Folate"], ["liver", "heart", "kidney", "kidneys", "sweetbread", "sweetbreads"]),
            food("oysters", "Oysters", "Back in season as the water cools, the months with an R.",
                 ["Zinc", "B12", "Copper"], ["oyster", "oysters"]),
            food("pork", "Pastured pork", "The traditional autumn pig harvest.",
                 ["Thiamin", "Selenium"], ["pork", "bacon", "ham"]),
            food("apples", "Apples and pears", "The orchard harvest.",
                 ["Vitamin C", "Fibre"], ["apple", "apples", "pear", "pears"]),
            food("squash", "Squash and pumpkin", "Harvested now and stored through the winter.",
                 ["Vitamin A", "Potassium"], ["squash", "pumpkin"]),
        ]
        case .winter: [
            food("shellfish", "Oysters and mussels", "Cold-water shellfish are at their plumpest.",
                 ["Zinc", "B12", "Iron"], ["oyster", "oysters", "mussel", "mussels", "clam", "clams", "scallop", "scallops"]),
            food("broth", "Bone broth", "Bones and joints simmered for collagen and minerals.",
                 ["Glycine", "Collagen"], ["broth", "stock"]),
            food("tallow", "Suet and tallow", "Hard fats for the cold months: slow, steady energy.",
                 ["Energy", "Vitamin E"], ["suet", "tallow", "lard"]),
            food("oilyfish", "Sardines and herring", "Oily winter fish, for vitamin D when the sun is low.",
                 ["Vitamin D", "Omega-3", "Calcium"], ["sardine", "sardines", "herring", "mackerel", "anchovy", "anchovies"]),
            food("citrus", "Citrus", "Oranges, grapefruit and mandarins peak in winter.",
                 ["Vitamin C", "Folate"], ["orange", "oranges", "grapefruit", "lemon", "lemons", "mandarin", "mandarins", "tangerine"]),
            food("ferments", "Sauerkraut and kimchi", "Made at harvest, they carry live cultures into winter.",
                 ["Probiotics", "Vitamin C", "Vitamin K2"], ["sauerkraut", "kimchi"]),
        ]
        }
    }
}
