import Foundation
import SwiftData

// MARK: - Supabase Profile Payload
struct SupabaseProfile: Codable {
    let id: String // The user's auth UUID
    let name: String
    let ageGroup: String
    let sex: String
    let pregnancyStatus: String
    let location: String
    let weightKg: Double
    let heightCm: Double
    let activityLevel: String
    let dietType: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ageGroup = "age_group"
        case sex
        case pregnancyStatus = "pregnancy_status"
        case location
        case weightKg = "weight_kg"
        case heightCm = "height_cm"
        case activityLevel = "activity_level"
        case dietType = "diet_type"
    }
}

// MARK: - User Profile (one instance, persisted)
@Model
final class UserProfile {
    var name: String = ""
    var age: Int = 25
    var ageGroup: String = "18-35" // "Under 18" | "18-35" | "36-50" | "Over 50"
    var sex: String = "Male"       // "Male" | "Female"
    var pregnancyStatus: String = "None" // "None" | "Pregnant" | "Postpartum"
    var location: String = ""
    var weightKg: Double = 70.0
    var goalWeightKg: Double = 70.0
    var heightCm: Double = 170.0
    var activityLevel: String = "moderate"  // sedentary|light|moderate|active|veryActive
    var dietType: String = "Carnivore"
    var lastLogDate: Date = Date.distantPast

    init() {}

    var isMale: Bool { sex.lowercased() == "male" }

    // MARK: - Mifflin-St Jeor TDEE
    var dailyCalorieGoal: Double {
        let bmr: Double
        if isMale {
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
