import Foundation
import SwiftData

@Model
final class DailyHydration {
    var id: UUID = UUID()
    var date: Date = Date()
    var waterOunces: Double = 0.0
    var addedSodiumMg: Double = 0.0
    var addedPotassiumMg: Double = 0.0
    var addedMagnesiumMg: Double = 0.0
    
    init() {}
}
