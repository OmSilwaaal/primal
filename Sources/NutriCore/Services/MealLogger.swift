import Foundation
import SwiftData

/// Single path for saving a meal so every entry point (search, barcode, AI scan) behaves the same.
@MainActor
enum MealLogger {
    static func log(_ entry: MealEntry, in context: ModelContext) {
        context.insert(entry)
        do {
            try context.save()
        } catch {
            print("Failed to save meal: \(error)")
        }
        SocialService.shared.publish(entry)
        HealthKitManager.shared.saveDietaryEnergy(calories: entry.calories, date: entry.date)
        HealthKitManager.shared.saveDietaryProtein(grams: entry.protein, date: entry.date)
    }

    static func delete(_ entry: MealEntry, in context: ModelContext) {
        let id = entry.id
        context.delete(entry)
        try? context.save()
        SocialService.shared.unpublish(mealId: id)
    }
}
