import Foundation

enum MealVisibility: String, Codable, CaseIterable, Identifiable {
    case everyone, friends, nobody
    var id: String { rawValue }
    var title: String {
        switch self {
        case .everyone: return "Everyone"
        case .friends: return "Friends only"
        case .nobody: return "Nobody"
        }
    }
}

/// Full profile row (the owner's own, or a friend's / public one).
struct PublicProfile: Codable, Identifiable, Equatable {
    var userId: UUID
    var username: String
    var displayName: String
    var bio: String
    var avatarUrl: String?
    var isPrivate: Bool
    var mealVisibility: MealVisibility

    var id: UUID { userId }
    var name: String { displayName.isEmpty ? "@\(username)" : displayName }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id", username, bio
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case isPrivate = "is_private"
        case mealVisibility = "meal_visibility"
    }
}

/// Minimal card that search/RPC returns, safe to show for private profiles.
struct BasicProfile: Codable, Identifiable, Equatable, Hashable {
    var userId: UUID
    var username: String
    var displayName: String
    var avatarUrl: String?
    var isPrivate: Bool

    var id: UUID { userId }
    var name: String { displayName.isEmpty ? "@\(username)" : displayName }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id", username
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case isPrivate = "is_private"
    }
}

struct Friendship: Codable, Identifiable, Equatable {
    var id: UUID
    var requesterId: UUID
    var addresseeId: UUID
    var status: String

    enum CodingKeys: String, CodingKey {
        case id, status
        case requesterId = "requester_id"
        case addresseeId = "addressee_id"
    }

    func other(than me: UUID) -> UUID { requesterId == me ? addresseeId : requesterId }
}

struct FriendRequest: Identifiable {
    let friendship: Friendship
    let profile: BasicProfile
    var id: UUID { friendship.id }
}

struct SharedMeal: Codable, Identifiable, Equatable {
    var id: UUID
    var userId: UUID
    var foodName: String
    var calories: Double
    var protein: Double
    var carbohydrates: Double
    var totalFat: Double
    var servingSize: Double
    var source: String
    var eatenAt: Date

    enum CodingKeys: String, CodingKey {
        case id, calories, protein, carbohydrates, source
        case userId = "user_id"
        case foodName = "food_name"
        case totalFat = "total_fat"
        case servingSize = "serving_size"
        case eatenAt = "eaten_at"
    }

    init(_ meal: MealEntry, userId: UUID) {
        id = meal.id
        self.userId = userId
        foodName = meal.foodName
        calories = meal.calories
        protein = meal.protein
        carbohydrates = meal.carbohydrates
        totalFat = meal.totalFat
        servingSize = meal.servingSize
        source = meal.source
        eatenAt = meal.date
    }
}

/// One day of a friend's eating.
struct DaySummary {
    let meals: [SharedMeal]
    var calories: Double { meals.reduce(0) { $0 + $1.calories } }
    var protein: Double { meals.reduce(0) { $0 + $1.protein } }
    var carbs: Double { meals.reduce(0) { $0 + $1.carbohydrates } }
    var fat: Double { meals.reduce(0) { $0 + $1.totalFat } }
}
