import Foundation

// MARK: - Species
enum RawSpecies: String, CaseIterable, Identifiable, Codable {
    case beef, lamb, bison, pork, poultry, fish, shellfish
    case deer, elk, bear, rabbit, otherGame

    var id: String { rawValue }
    var label: String {
        switch self {
        case .beef: "Beef"
        case .lamb: "Lamb"
        case .bison: "Bison"
        case .pork: "Pork"
        case .poultry: "Poultry"
        case .fish: "Fish"
        case .shellfish: "Shellfish"
        case .deer: "Deer"
        case .elk: "Elk"
        case .bear: "Bear"
        case .rabbit: "Rabbit"
        case .otherGame: "Other game"
        }
    }
    var icon: String {
        switch self {
        case .fish: "fish"
        case .shellfish: "water.waves"
        case .poultry: "bird"
        case .rabbit: "hare"
        case .deer, .elk, .bear, .otherGame: "leaf"
        default: "fork.knife"
        }
    }
    var isGame: Bool { [.deer, .elk, .bear, .rabbit, .otherGame].contains(self) }
    /// Ruminant red meats share most reference nutrition and risk behaviour.
    var isRedMeat: Bool { [.beef, .lamb, .bison, .pork, .deer, .elk, .bear].contains(self) }

    static var mainGroup: [RawSpecies] { [.beef, .lamb, .bison, .pork, .poultry, .fish, .shellfish] }
    static var gameGroup: [RawSpecies] { [.deer, .elk, .bear, .rabbit, .otherGame] }

    /// Species of an entry, tolerant of free-text/legacy rows.
    static func from(_ raw: String) -> RawSpecies? { RawSpecies(rawValue: raw) }
}

enum CutCategory: String, CaseIterable, Identifiable {
    case muscle, organ, fat
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum Organ: String, CaseIterable, Identifiable {
    case liver, heart, kidney, spleen, brain, marrow
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum FatType: String, CaseIterable, Identifiable {
    case suet, tallow
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum Prep: String, CaseIterable, Identifiable {
    case raw, frozenThawed, aged, seared, rare, cooked
    var id: String { rawValue }
    var label: String {
        switch self {
        case .raw: "Raw"
        case .frozenThawed: "Frozen → thawed"
        case .aged: "Fermented / aged"
        case .seared: "Seared"
        case .rare: "Rare"
        case .cooked: "Cooked"
        }
    }
    /// How "raw" this preparation counts toward the raw score (0…1).
    var rawness: Double {
        switch self {
        case .raw, .frozenThawed, .aged: 1
        case .seared: 0.75
        case .rare: 0.5
        case .cooked: 0
        }
    }
}

enum Rearing: String, CaseIterable, Identifiable {
    case unknown, grassFed, grainFinished, pastureRaised, wild, farmed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .unknown: "Unknown"
        case .grassFed: "Grass-fed"
        case .grainFinished: "Grain-finished"
        case .pastureRaised: "Pasture-raised"
        case .wild: "Wild"
        case .farmed: "Farmed"
        }
    }
}

enum ThawMethod: String, CaseIterable, Identifiable {
    case none, fridge, coldWater, counter, microwave
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "Not thawed"
        case .fridge: "Fridge"
        case .coldWater: "Cold water"
        case .counter: "Counter"
        case .microwave: "Microwave"
        }
    }
}

// MARK: - Diet mode
enum DietMode: String, CaseIterable, Identifiable {
    case rawCarnivore, strictCarnivore, carnivoreDairyEggs, animalBased
    var id: String { rawValue }
    var label: String {
        switch self {
        case .rawCarnivore: "Raw carnivore"
        case .strictCarnivore: "Strict carnivore"
        case .carnivoreDairyEggs: "Carnivore + dairy & eggs"
        case .animalBased: "Animal-based"
        }
    }
    var blurb: String {
        switch self {
        case .rawCarnivore: "Meat, organs and fat, mostly uncooked."
        case .strictCarnivore: "Meat, organs and fat only."
        case .carnivoreDairyEggs: "Animal foods plus dairy and eggs."
        case .animalBased: "Mostly animal foods with fruit and honey."
        }
    }
    /// Default fat share of calories (min, max) as a general reference.
    var fatRange: ClosedRange<Double> {
        switch self {
        case .animalBased: 50...70
        default: 65...80
        }
    }
    /// Carb ceiling in grams per day used for the "off-mode" hint.
    var carbCap: Double {
        switch self {
        case .animalBased: 150
        case .carnivoreDairyEggs: 30
        default: 10
        }
    }
}

// MARK: - Biomarkers
enum BiomarkerGroup: String, CaseIterable, Identifiable {
    case lipids, metabolic, blood, organs, body
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lipids: "Lipids"
        case .metabolic: "Glucose & ketones"
        case .blood: "Vitamins & minerals"
        case .organs: "Liver, kidney, thyroid"
        case .body: "Body"
        }
    }
}

enum BiomarkerKind: String, CaseIterable, Identifiable {
    case ldl, apoB, hdl, triglycerides
    case fastingGlucose, hba1c, fastingInsulin, bloodBHB, breathKetones
    case uricAcid, ferritin, ironSaturation, b12, vitaminD, hsCRP
    case creatinine, egfr, bun, alt, ast, tsh, sodium, potassium
    case weight, waist, bodyFat, systolic, diastolic, restingHR, hrv

    var id: String { rawValue }
    var label: String {
        switch self {
        case .ldl: "LDL-C"
        case .apoB: "ApoB"
        case .hdl: "HDL-C"
        case .triglycerides: "Triglycerides"
        case .fastingGlucose: "Fasting glucose"
        case .hba1c: "HbA1c"
        case .fastingInsulin: "Fasting insulin"
        case .bloodBHB: "Blood BHB"
        case .breathKetones: "Breath ketones"
        case .uricAcid: "Uric acid"
        case .ferritin: "Ferritin"
        case .ironSaturation: "Iron saturation"
        case .b12: "Vitamin B12"
        case .vitaminD: "Vitamin D (25-OH)"
        case .hsCRP: "hs-CRP"
        case .creatinine: "Creatinine"
        case .egfr: "eGFR"
        case .bun: "BUN"
        case .alt: "ALT"
        case .ast: "AST"
        case .tsh: "TSH"
        case .sodium: "Sodium (serum)"
        case .potassium: "Potassium (serum)"
        case .weight: "Weight"
        case .waist: "Waist"
        case .bodyFat: "Body fat"
        case .systolic: "BP systolic"
        case .diastolic: "BP diastolic"
        case .restingHR: "Resting HR"
        case .hrv: "HRV"
        }
    }
    var unit: String {
        switch self {
        case .ldl, .hdl, .triglycerides, .fastingGlucose, .creatinine, .bun: "mg/dL"
        case .apoB: "mg/dL"
        case .hba1c, .bodyFat, .ironSaturation: "%"
        case .fastingInsulin: "µIU/mL"
        case .bloodBHB: "mmol/L"
        case .breathKetones: "ppm"
        case .uricAcid: "mg/dL"
        case .ferritin: "ng/mL"
        case .b12: "pg/mL"
        case .vitaminD: "ng/mL"
        case .hsCRP: "mg/L"
        case .egfr: "mL/min"
        case .alt, .ast: "U/L"
        case .tsh: "mIU/L"
        case .sodium, .potassium: "mmol/L"
        case .weight: "kg"
        case .waist: "cm"
        case .systolic, .diastolic: "mmHg"
        case .restingHR: "bpm"
        case .hrv: "ms"
        }
    }
    var group: BiomarkerGroup {
        switch self {
        case .ldl, .apoB, .hdl, .triglycerides: .lipids
        case .fastingGlucose, .hba1c, .fastingInsulin, .bloodBHB, .breathKetones: .metabolic
        case .uricAcid, .ferritin, .ironSaturation, .b12, .vitaminD, .hsCRP: .blood
        case .creatinine, .egfr, .bun, .alt, .ast, .tsh, .sodium, .potassium: .organs
        case .weight, .waist, .bodyFat, .systolic, .diastolic, .restingHR, .hrv: .body
        }
    }
    /// General reference interval as printed on typical lab reports. Not a diagnosis.
    var reference: ClosedRange<Double>? {
        switch self {
        case .ldl: 0...130
        case .apoB: 0...100
        case .hdl: 40...100
        case .triglycerides: 0...150
        case .fastingGlucose: 70...99
        case .hba1c: 4...5.6
        case .fastingInsulin: 2...20
        case .bloodBHB: 0...0.5
        case .uricAcid: 3.5...7.2
        case .ferritin: 30...300
        case .ironSaturation: 20...50
        case .b12: 200...900
        case .vitaminD: 30...100
        case .hsCRP: 0...3
        case .creatinine: 0.6...1.3
        case .egfr: 90...140
        case .bun: 7...20
        case .alt: 7...55
        case .ast: 8...48
        case .tsh: 0.4...4.0
        case .sodium: 135...145
        case .potassium: 3.5...5.2
        case .systolic: 90...129
        case .diastolic: 60...84
        case .restingHR: 50...90
        default: nil
        }
    }
}

// MARK: - Symptoms
enum GISymptom: String, CaseIterable, Identifiable {
    case nausea, vomiting, diarrhea, cramps, bloating, fever, headache, fatigue
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var isKetoFlu: Bool { [.headache, .fatigue].contains(self) }
}

enum KetoFluSymptom: String, CaseIterable, Identifiable {
    case headache, cramps, fatigue, dizziness, brainFog
    var id: String { rawValue }
    var label: String { self == .brainFog ? "Brain fog" : rawValue.capitalized }
}

// MARK: - Pathogens
struct Pathogen: Identifiable, Hashable {
    let name: String
    let minHours: Double
    let maxHours: Double
    var id: String { name }
    var windowLabel: String {
        func fmt(_ h: Double) -> String { h < 48 ? "\(Int(h))h" : "\(Int((h / 24).rounded()))d" }
        return "\(fmt(minHours))–\(fmt(maxHours))"
    }
}

enum Pathogens {
    static let salmonella = Pathogen(name: "Salmonella", minHours: 6, maxHours: 72)
    static let campylobacter = Pathogen(name: "Campylobacter", minHours: 48, maxHours: 240)
    static let ecoli = Pathogen(name: "E. coli O157:H7", minHours: 24, maxHours: 240)
    static let trichinella = Pathogen(name: "Trichinella", minHours: 24, maxHours: 336)
    static let toxoplasma = Pathogen(name: "Toxoplasma", minHours: 120, maxHours: 552)
    static let yersinia = Pathogen(name: "Yersinia", minHours: 96, maxHours: 168)
    static let anisakis = Pathogen(name: "Anisakis", minHours: 1, maxHours: 336)
    static let vibrio = Pathogen(name: "Vibrio", minHours: 4, maxHours: 96)
    static let norovirus = Pathogen(name: "Norovirus", minHours: 12, maxHours: 48)
    static let tularemia = Pathogen(name: "Tularemia", minHours: 72, maxHours: 336)
    static let listeria = Pathogen(name: "Listeria", minHours: 24, maxHours: 720)

    static func forSpecies(_ s: RawSpecies, ground: Bool) -> [Pathogen] {
        switch s {
        case .poultry: return [salmonella, campylobacter]
        case .beef, .bison: return ground ? [ecoli, salmonella] : [salmonella, ecoli]
        case .lamb: return [salmonella, ecoli, toxoplasma]
        case .pork: return [trichinella, toxoplasma, yersinia, salmonella]
        case .fish: return [anisakis, vibrio, salmonella]
        case .shellfish: return [vibrio, norovirus]
        case .deer, .elk: return [trichinella, ecoli, toxoplasma]
        case .bear: return [trichinella, toxoplasma]
        case .rabbit: return [tularemia, salmonella]
        case .otherGame: return [trichinella, salmonella]
        }
    }
}
