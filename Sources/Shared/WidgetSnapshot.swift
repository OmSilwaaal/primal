import Foundation

/// Today's numbers, written by the app and read by the widgets through the shared App Group. The widget never
/// opens the app's database; it only reads this small snapshot.
struct WidgetSnapshot: Codable, Equatable {
    static let appGroup = "group.com.omsilwal.NutriCorePrimal"
    private static let key = "widgetSnapshot"

    var day: Date
    var calories: Double
    var calorieGoal: Double
    var waterLitres: Double
    var waterGoalLitres: Double
    var sunMinutes: Double
    var sunGoalMinutes: Double

    var caloriesLeft: Double { max(0, calorieGoal - calories) }
    var progress: Double { calorieGoal > 0 ? min(1, calories / calorieGoal) : 0 }

    /// An empty day, for the widget gallery and before the app has run.
    static let placeholder = WidgetSnapshot(day: .now, calories: 1190, calorieGoal: 2000, waterLitres: 1.4,
                                            waterGoalLitres: 3.5, sunMinutes: 18, sunGoalMinutes: 30)

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return nil }
        // Yesterday's numbers would be wrong today: start the new day at zero.
        guard Calendar.current.isDateInToday(snap.day) else {
            return WidgetSnapshot(day: .now, calories: 0, calorieGoal: snap.calorieGoal, waterLitres: 0,
                                  waterGoalLitres: snap.waterGoalLitres, sunMinutes: 0, sunGoalMinutes: snap.sunGoalMinutes)
        }
        return snap
    }

    /// Saves the snapshot; returns true if it changed (so the caller knows to reload widget timelines).
    @discardableResult
    func save() -> Bool {
        guard let defaults = UserDefaults(suiteName: Self.appGroup) else { return false }
        if Self.load() == self { return false }
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
        return true
    }
}
