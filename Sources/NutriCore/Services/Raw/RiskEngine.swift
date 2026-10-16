import Foundation

// MARK: - Tunable configuration
/// Every number the risk score uses lives here so it can be tuned without touching the logic.
/// The result is risk *information*, never a clearance that food is safe.
struct RiskConfig {
    /// Base risk (0…100) for a raw whole cut of each species.
    var baseWhole: [RawSpecies: Double] = [
        .beef: 12, .lamb: 14, .bison: 12, .pork: 55, .poultry: 70, .fish: 40, .shellfish: 55,
        .deer: 35, .elk: 35, .bear: 75, .rabbit: 50, .otherGame: 55,
    ]
    /// Base risk for ground/minced product (surface bacteria are mixed through).
    var baseGround: [RawSpecies: Double] = [
        .beef: 30, .lamb: 28, .bison: 30, .pork: 62, .poultry: 82, .fish: 48, .shellfish: 55,
        .deer: 45, .elk: 45, .bear: 80, .rabbit: 58, .otherGame: 62,
    ]
    /// Share of the base risk that is parasitic (and therefore reducible by an effective freeze).
    var parasiteShare: [RawSpecies: Double] = [
        .beef: 0.15, .lamb: 0.2, .bison: 0.15, .pork: 0.5, .poultry: 0.05, .fish: 0.7, .shellfish: 0.1,
        .deer: 0.3, .elk: 0.3, .bear: 0.7, .rabbit: 0.1, .otherGame: 0.3,
    ]
    var residualParasiteAfterFreeze = 0.15

    var organMultiplier = 1.25
    var brainMultiplier = 1.4
    var fatMultiplier = 0.4

    var prepMultiplier: [Prep: Double] = [
        .raw: 1.0, .frozenThawed: 1.0, .aged: 1.2, .seared: 0.8, .rare: 0.55, .cooked: 0.1,
    ]
    /// Searing only treats the surface, so it barely helps for ground product.
    var groundSearedMultiplier = 0.95
    var groundRareMultiplier = 0.9

    // Freshness (days relative to the sell-by date)
    var freshPackDays = 2.0
    var freshMultiplier = 0.9
    var unknownDatesMultiplier = 1.05
    var pastSellByPerDay = 0.15
    var pastSellByCap = 2.0

    // Cold chain
    var outOfFridgeWarnMin = 120.0
    var outOfFridgeHighMin = 240.0
    var outOfFridgeWarnMultiplier = 1.5
    var outOfFridgeHighMultiplier = 2.0
    var thawMultiplier: [ThawMethod: Double] = [
        .none: 1.0, .fridge: 1.0, .microwave: 1.0, .coldWater: 1.1, .counter: 1.4,
    ]

    var levelThresholds: [Double] = [20, 40, 65]   // lower | moderate | elevated | high

    static var `default`: RiskConfig { RiskConfig() }
}

enum RiskLevel: Int, Comparable {
    case lower, moderate, elevated, high
    static func < (a: RiskLevel, b: RiskLevel) -> Bool { a.rawValue < b.rawValue }
    var label: String {
        switch self {
        case .lower: "Lower risk"
        case .moderate: "Moderate risk"
        case .elevated: "Elevated risk"
        case .high: "High risk"
        }
    }
}

struct RiskFactor: Identifiable {
    let id = UUID()
    let label: String
    let detail: String
}

struct RiskAssessment {
    var score: Double
    var level: RiskLevel
    var pathogens: [Pathogen]
    var hardWarnings: [String]
    var notes: [String]
    var parasiteMitigated: Bool
    var mitigationNote: String
    var factors: [RiskFactor]
}

// MARK: - Freezing rules
enum FreezeRules {
    struct Result { let effective: Bool; let note: String }

    /// Whether the logged freeze is effective against the parasites relevant to that species.
    /// Returns `effective == false` with an explanation whenever freezing is not a reliable mitigation.
    static func evaluate(species: RawSpecies, tempC: Double, hours: Double) -> Result {
        switch species {
        case .fish:
            let ok = (tempC <= -35 && hours >= 15) || (tempC <= -20 && hours >= 168)
            return Result(effective: ok, note: ok
                ? "Meets FDA parasite-destruction freezing (−20 °C ≥ 7 days, or −35 °C ≥ 15 h). Bacteria and Vibrio are not affected."
                : "Needs −20 °C for 7 days, or −35 °C for 15 hours, to address Anisakis.")
        case .pork:
            let ok = (tempC <= -15 && hours >= 480) || (tempC <= -23 && hours >= 240) || (tempC <= -29 && hours >= 144)
            return Result(effective: ok, note: ok
                ? "Meets USDA freezing guidance for Trichinella in cuts under 6 in. Bacteria such as Yersinia and Salmonella are not affected."
                : "USDA guidance for Trichinella: −15 °C 20 days, −23 °C 10 days or −29 °C 6 days (cuts under 6 in thick).")
        case .beef, .lamb, .bison:
            let ok = tempC <= -20 && hours >= 168
            return Result(effective: ok, note: ok
                ? "−20 °C for 7+ days reduces tapeworm cysts and Toxoplasma. Bacteria such as E. coli are not affected."
                : "−20 °C for 7+ days reduces parasite cysts.")
        case .bear:
            return Result(effective: false, note: "Trichinella in bear (and walrus) is freeze-resistant. Freezing does NOT make it safe.")
        case .deer, .elk:
            return Result(effective: false, note: "Freezing does not address chronic wasting disease or freeze-resistant Trichinella strains.")
        case .rabbit:
            return Result(effective: false, note: "Tularemia bacteria survive freezing.")
        case .otherGame:
            return Result(effective: false, note: "Freeze-resistant Trichinella strains exist in wild game; freezing is not a reliable mitigation.")
        case .poultry:
            return Result(effective: false, note: "Salmonella and Campylobacter survive freezing.")
        case .shellfish:
            return Result(effective: false, note: "Vibrio and norovirus survive freezing.")
        }
    }
}

// MARK: - Scoring
enum RiskEngine {
    static var config = RiskConfig.default

    static func assess(species: RawSpecies, category: CutCategory, organ: String, ground: Bool, prep: Prep,
                       batch: SourceBatch?, outOfFridgeMin: Double, thaw: ThawMethod, now: Date = Date()) -> RiskAssessment {
        let c = config
        var factors: [RiskFactor] = []
        var warnings: [String] = []
        var notes: [String] = []

        let base = (ground ? c.baseGround[species] : c.baseWhole[species]) ?? 40
        factors.append(RiskFactor(label: ground ? "Ground \(species.label.lowercased())" : "\(species.label) whole cut",
                                  detail: "Base \(Int(base))"))

        // Split into parasite / bacterial parts so an effective freeze only removes the parasite part.
        let pShare = c.parasiteShare[species] ?? 0.2
        var parasite = base * pShare
        let bacterial = base * (1 - pShare)

        // Freezer
        var mitigated = false
        var mitigationNote = ""
        if let b = batch, b.frozenAt != nil {
            let rule = FreezeRules.evaluate(species: species, tempC: b.freezerTempC, hours: b.frozenHours)
            mitigated = rule.effective
            mitigationNote = rule.note
            if mitigated {
                parasite *= c.residualParasiteAfterFreeze
                factors.append(RiskFactor(label: "Freezer log", detail: "Parasite share reduced"))
            } else {
                factors.append(RiskFactor(label: "Freezer log", detail: "No credit — \(rule.note)"))
            }
        } else if prep == .frozenThawed {
            mitigationNote = "No freezer history recorded, so no freezing credit is applied."
        }

        var score = bacterial + parasite

        // Cut type
        if category == .organ {
            score *= organ == Organ.brain.rawValue ? c.brainMultiplier : c.organMultiplier
            factors.append(RiskFactor(label: "Organ meat", detail: "×\(organ == Organ.brain.rawValue ? c.brainMultiplier : c.organMultiplier)"))
        } else if category == .fat {
            score *= c.fatMultiplier
            factors.append(RiskFactor(label: "Rendered/trimmed fat", detail: "×\(c.fatMultiplier)"))
        }

        // Preparation
        var pm = c.prepMultiplier[prep] ?? 1
        if ground && prep == .seared { pm = c.groundSearedMultiplier }
        if ground && prep == .rare { pm = c.groundRareMultiplier }
        if pm != 1 { factors.append(RiskFactor(label: prep.label, detail: "×\(String(format: "%.2f", pm))")) }
        score *= pm

        // Freshness
        var fm = c.unknownDatesMultiplier
        if let b = batch {
            if let sellBy = b.sellByDate {
                let daysPast = now.timeIntervalSince(sellBy) / 86400
                if daysPast > 0 {
                    fm = min(1 + c.pastSellByPerDay * daysPast, c.pastSellByCap)
                    notes.append("Past its sell-by date by \(Int(daysPast.rounded(.up))) day(s).")
                    factors.append(RiskFactor(label: "Past sell-by", detail: "×\(String(format: "%.2f", fm))"))
                } else if let pack = b.packDate, now.timeIntervalSince(pack) / 86400 <= c.freshPackDays {
                    fm = c.freshMultiplier
                    factors.append(RiskFactor(label: "Freshly packed", detail: "×\(c.freshMultiplier)"))
                } else {
                    fm = 1
                }
            } else if let pack = b.packDate {
                fm = now.timeIntervalSince(pack) / 86400 <= c.freshPackDays ? c.freshMultiplier : 1
            }
        }
        score *= fm

        // Cold chain
        if outOfFridgeMin >= c.outOfFridgeHighMin {
            score *= c.outOfFridgeHighMultiplier
            notes.append("Out of the fridge over \(Int(c.outOfFridgeHighMin / 60)) hours.")
            factors.append(RiskFactor(label: "Cold chain", detail: "×\(c.outOfFridgeHighMultiplier)"))
        } else if outOfFridgeMin >= c.outOfFridgeWarnMin {
            score *= c.outOfFridgeWarnMultiplier
            notes.append("Out of the fridge over 2 hours.")
            factors.append(RiskFactor(label: "Cold chain", detail: "×\(c.outOfFridgeWarnMultiplier)"))
        }
        let tm = c.thawMultiplier[thaw] ?? 1
        if tm != 1 {
            score *= tm
            factors.append(RiskFactor(label: "Thawed on \(thaw.label.lowercased())", detail: "×\(tm)"))
        }

        // Species hard warnings
        if prep.rawness > 0.4 {
            switch species {
            case .poultry:
                warnings.append("Raw poultry carries Salmonella and Campylobacter. Public health agencies advise against eating it raw.")
            case .bear:
                warnings.append("Bear (and walrus) Trichinella is freeze-resistant — freezing does NOT make it safe.")
            case .deer, .elk:
                warnings.append("Deer and elk can carry chronic wasting disease; test animals where required. Freezing does not remove prions.")
            case .rabbit:
                warnings.append("Wild rabbit can carry tularemia, which survives freezing.")
            case .otherGame:
                warnings.append("Wild game may carry freeze-resistant Trichinella strains.")
            case .pork:
                if !mitigated { warnings.append("Raw pork can carry Trichinella, Toxoplasma and Yersinia.") }
            case .shellfish:
                notes.append("Raw shellfish can carry Vibrio; risk rises in warm months.")
            case .fish:
                if !mitigated { notes.append("Raw fish can carry Anisakis; see the freezer log for parasite-destruction guidance.") }
            default:
                if ground { notes.append("Ground beef can carry E. coli O157:H7 through the whole product.") }
            }
            if category == .organ, species == .pork {
                notes.append("Raw pork liver is associated with hepatitis E.")
            }
            if category == .organ, species == .poultry {
                notes.append("Poultry liver commonly carries Campylobacter.")
            }
        }

        let final = max(0, min(100, score))
        let t = c.levelThresholds
        let level: RiskLevel = final < t[0] ? .lower : final < t[1] ? .moderate : final < t[2] ? .elevated : .high

        return RiskAssessment(
            score: final, level: level,
            pathogens: Pathogens.forSpecies(species, ground: ground),
            hardWarnings: warnings, notes: notes,
            parasiteMitigated: mitigated, mitigationNote: mitigationNote, factors: factors)
    }

    /// Convenience for an already-logged meal.
    static func assess(_ meal: MealEntry, batch: SourceBatch?) -> RiskAssessment? {
        guard let species = RawSpecies(rawValue: meal.species) else { return nil }
        return assess(species: species, category: CutCategory(rawValue: meal.cutCategory) ?? .muscle,
                      organ: meal.organType, ground: meal.isGround, prep: Prep(rawValue: meal.prep) ?? .raw,
                      batch: batch, outOfFridgeMin: meal.outOfFridgeMin,
                      thaw: ThawMethod(rawValue: meal.thawMethod) ?? .none, now: meal.date)
    }
}

// MARK: - Symptom → meal correlation
struct CulpritCandidate: Identifiable {
    let id: String
    let title: String
    let lotNumber: String
    let batchId: UUID?
    let meals: [MealEntry]
    let pathogens: [Pathogen]
    let score: Double            // 0…100 relative suspicion
}

enum SymptomCorrelator {
    /// Walks back from the symptom time and scores every tagged meal whose pathogen
    /// incubation window contains the gap. Meals sharing a batch are grouped.
    static func culprits(for symptom: SymptomLog, meals: [MealEntry], batches: [SourceBatch]) -> [CulpritCandidate] {
        var groups: [String: (meals: [MealEntry], path: Set<Pathogen>, score: Double)] = [:]

        for meal in meals where meal.date < symptom.date {
            guard let species = RawSpecies(rawValue: meal.species) else { continue }
            let hours = symptom.date.timeIntervalSince(meal.date) / 3600
            let pathogens = Pathogens.forSpecies(species, ground: meal.isGround)
            let matching = pathogens.filter { hours >= $0.minHours && hours <= $0.maxHours }
            guard !matching.isEmpty else { continue }

            // Core of the window counts fully, the tails count less.
            let fit = matching.map { p -> Double in
                let mid = (p.minHours + p.maxHours) / 2
                return hours <= mid ? 1.0 : 0.6
            }.max() ?? 0.6
            let risk = meal.riskScore > 0 ? meal.riskScore : 30
            let prepRaw = Prep(rawValue: meal.prep)?.rawness ?? 1
            let suspicion = risk * fit * (prepRaw > 0 ? 1.0 : 0.15)

            let key = meal.batchId?.uuidString ?? meal.id.uuidString
            var g = groups[key] ?? ([], [], 0)
            g.meals.append(meal)
            matching.forEach { g.path.insert($0) }
            g.score = max(g.score, suspicion) + (g.meals.count > 1 ? 4 : 0)
            groups[key] = g
        }

        return groups.map { key, g in
            let batch = g.meals.first?.batchId.flatMap { id in batches.first { $0.id == id } }
            let name = batch?.label.isEmpty == false ? batch!.label : (g.meals.first?.foodName ?? "Meal")
            return CulpritCandidate(id: key, title: name, lotNumber: batch?.lotNumber ?? "", batchId: batch?.id,
                                    meals: g.meals.sorted { $0.date < $1.date },
                                    pathogens: g.path.sorted { $0.minHours < $1.minHours },
                                    score: min(100, g.score))
        }
        .sorted { $0.score > $1.score }
    }
}
