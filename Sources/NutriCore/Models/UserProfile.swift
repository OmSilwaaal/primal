import Foundation
import SwiftData

// MARK: - User Profile (one instance, persisted)
@Model
final class UserProfile {
    var name: String = "PLAYER 1"
    var age: Int = 25
    var sex: String = "male"          // "male" | "female"
    var weightKg: Double = 70.0
    var heightCm: Double = 170.0
    var activityLevel: String = "moderate"  // sedentary|light|moderate|active|veryActive
    var lastLogDate: Date = Date.distantPast

    init() {}

    // MARK: - Mifflin-St Jeor TDEE
    var dailyCalorieGoal: Double {
        let bmr: Double
        if sex == "male" {
            bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * Double(age)) + 5
        } else {
            bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * Double(age)) - 161
        }
        let multiplier: Double
        switch activityLevel {
        case "sedentary":  multiplier = 1.2
        case "light":      multiplier = 1.375
        case "moderate":   multiplier = 1.55
        case "active":     multiplier = 1.725
        case "veryActive": multiplier = 1.9
        default:           multiplier = 1.55
        }
        return max(1200, bmr * multiplier)
    }
}

// MARK: - Activity level display
extension String {
    var activityDisplayName: String {
        switch self {
        case "sedentary":  return "Sedentary"
        case "light":      return "Light (1-3x/week)"
        case "moderate":   return "Moderate (3-5x/week)"
        case "active":     return "Active (6-7x/week)"
        case "veryActive": return "Very Active"
        default: return self
        }
    }
}
