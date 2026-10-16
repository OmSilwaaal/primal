import Foundation
import SwiftData

/// A purchased pack/cut of meat. Meals reference it by `batchId` so risk, freezer history and cost carry over.
@Model
final class SourceBatch {
    var id: UUID = UUID()
    var label: String = ""             // "Ribeye – Smith Farm"
    var species: String = RawSpecies.beef.rawValue
    var cutCategory: String = CutCategory.muscle.rawValue
    var organType: String = ""
    var isGround: Bool = false
    var supplierName: String = ""
    var rearing: String = Rearing.unknown.rawValue
    var lotNumber: String = ""
    var purchaseDate: Date = Date()
    var packDate: Date? = nil
    var sellByDate: Date? = nil
    var totalWeightG: Double = 0
    var pricePerLb: Double = 0
    var notes: String = ""

    // Freezer log
    var frozenAt: Date? = nil
    var freezerTempC: Double = -18
    var thawedAt: Date? = nil
    var thawMethod: String = ThawMethod.none.rawValue

    var recallFlag: String = ""        // set by RecallService when a match is found
    var createdAt: Date = Date()

    init() {}

    var speciesEnum: RawSpecies { RawSpecies(rawValue: species) ?? .beef }

    /// Hours spent frozen so far (until thawed, or now).
    var frozenHours: Double {
        guard let frozenAt else { return 0 }
        return max(0, (thawedAt ?? Date()).timeIntervalSince(frozenAt) / 3600)
    }
    var isCurrentlyFrozen: Bool { frozenAt != nil && thawedAt == nil }
}

@Model
final class Supplier {
    var id: UUID = UUID()
    var name: String = ""
    var rating: Int = 0               // 0 = unrated, 1…5
    var notes: String = ""
    var createdAt: Date = Date()
    init() {}
}

@Model
final class SymptomLog {
    var id: UUID = UUID()
    var date: Date = Date()
    var kind: String = GISymptom.nausea.rawValue
    var severity: Int = 2             // 1…5
    var notes: String = ""
    init() {}
}

@Model
final class BiomarkerReading {
    var id: UUID = UUID()
    var date: Date = Date()
    var kind: String = BiomarkerKind.ldl.rawValue
    var value: Double = 0
    var source: String = "manual"     // manual | health
    init() {}
    var kindEnum: BiomarkerKind? { BiomarkerKind(rawValue: kind) }
}

/// One daily check-in covering subjective outcomes.
@Model
final class OutcomeLog {
    var id: UUID = UUID()
    var date: Date = Date()           // normalised to start of day
    var energy: Int = 0               // 1…5, 0 = not set
    var mood: Int = 0
    var focus: Int = 0
    var sleep: Int = 0
    var satiety: Int = 0
    var cravings: Int = 0
    var bristol: Int = 0              // 1…7, 0 = not set
    var training: Int = 0             // performance 1…5
    var recovery: Int = 0
    var ketoFlu: String = ""          // comma separated KetoFluSymptom raw values
    var customSymptoms: String = ""
    var notes: String = ""
    init() {}

    var ketoFluList: [KetoFluSymptom] {
        ketoFlu.split(separator: ",").compactMap { KetoFluSymptom(rawValue: String($0)) }
    }
}

@Model
final class SunSession {
    var id: UUID = UUID()
    var start: Date = Date()
    var minutes: Double = 0
    var exposure: String = "partial"  // minimal | partial | most
    var uvIndex: Double = 0
    var source: String = "manual"     // manual | timer
    var notes: String = ""
    init() {}
}
