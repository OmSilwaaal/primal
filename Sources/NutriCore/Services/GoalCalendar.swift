import EventKit
import Foundation

/// Puts goals in Apple Calendar: each one an all-day event on the days it's due, repeating the way the goal does,
/// in a "Vitalis" calendar of its own so they're easy to show, hide or delete together. Removing a goal removes its
/// events. Needs full calendar access (to find and remove the events it added).
@MainActor
enum GoalCalendar {
    private static let store = EKEventStore()
    private static let calendarKey = "goalCalendarIdentifier"

    enum Failure: LocalizedError {
        case denied, noCalendar
        var errorDescription: String? {
            switch self {
            case .denied: "Calendar access is off for Vitalis. Turn it on in Settings › Privacy & Security › Calendars."
            case .noCalendar: "Couldn't find a calendar to add goals to."
            }
        }
    }

    /// Asks once; true when Vitalis may add and remove events.
    static func requestAccess() async -> Bool {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Adds the goal's events (replacing any it already had) and remembers the event on the goal.
    static func add(_ goal: Goal) async throws {
        guard await requestAccess() else { throw Failure.denied }
        remove(goal)
        let event = EKEvent(eventStore: store)
        event.calendar = try vitalisCalendar()
        event.title = goal.title
        event.notes = "A Vitalis goal · \(goal.scheduleText)"
        event.isAllDay = true
        event.startDate = firstDay(of: goal)
        event.endDate = event.startDate
        if let rule = recurrence(for: goal) { event.recurrenceRules = [rule] }
        try store.save(event, span: .futureEvents, commit: true)
        goal.calendarEventID = event.eventIdentifier ?? ""
    }

    /// Removes the goal's events from Calendar, if it had any.
    static func remove(_ goal: Goal) {
        guard !goal.calendarEventID.isEmpty, EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let event = store.event(withIdentifier: goal.calendarEventID) else { return }
        try? store.remove(event, span: .futureEvents, commit: true)
        goal.calendarEventID = ""
    }

    /// The first day the goal is actually due (a weekday goal may start before its first chosen weekday).
    static func firstDay(of goal: Goal) -> Date {
        let cal = Calendar.current
        var day = goal.start
        for _ in 0..<7 where !goal.isDue(on: day) {
            day = cal.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return day
    }

    /// How the goal repeats, in Calendar's terms: nil for a one-off; daily; or weekly on its weekdays; until its end.
    static func recurrence(for goal: Goal) -> EKRecurrenceRule? {
        guard !goal.isOneOff else { return nil }
        let end = goal.end.map { EKRecurrenceEnd(end: Calendar.current.date(byAdding: .hour, value: 23, to: $0) ?? $0) }
        if goal.weekdays.isEmpty || goal.weekdays.count == 7 {
            return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: end)
        }
        let days = goal.weekdays.compactMap { EKWeekday(rawValue: $0) }.map { EKRecurrenceDayOfWeek($0) }
        return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, daysOfTheWeek: days, daysOfTheMonth: nil,
                                monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: end)
    }

    /// The "Vitalis" calendar: found by its saved identifier, else made in the same account as the default calendar.
    private static func vitalisCalendar() throws -> EKCalendar {
        if let id = UserDefaults.standard.string(forKey: calendarKey), let found = store.calendar(withIdentifier: id) {
            return found
        }
        guard let fallback = store.defaultCalendarForNewEvents else { throw Failure.noCalendar }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Vitalis"
        calendar.cgColor = CGColor(red: 0.84, green: 0.95, blue: 0.35, alpha: 1)   // the brand lime
        calendar.source = fallback.source
        do {
            try store.saveCalendar(calendar, commit: true)
            UserDefaults.standard.set(calendar.calendarIdentifier, forKey: calendarKey)
            return calendar
        } catch {
            return fallback   // some accounts don't allow new calendars: use the default one instead
        }
    }
}
