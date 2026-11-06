import Foundation
import SwiftData

/// A goal you set yourself on the Goals page ("Organ meat", "Morning sun"), shown on the calendar on each day it's
/// due and ticked off day by day. Three schedules: once on a date, every day, or on chosen weekdays — the last two
/// from a start date, optionally until an end date.
@Model
final class Goal {
    var id: UUID = UUID()
    var title: String = ""
    /// SF Symbol.
    var icon: String = "target"
    /// First day it's due (start of day).
    var start: Date = Date()
    /// Last day it's due (start of day); nil runs on. A one-off goal has `end == start`.
    var end: Date? = nil
    /// Calendar weekday numbers (1 = Sunday … 7 = Saturday) it's due on; empty means every day.
    var weekdays: [Int] = []
    /// Days it was done (start of day).
    var doneDays: [Date] = []
    var created: Date = Date()
    /// Its event in Apple Calendar (`GoalCalendar`), or empty when it isn't there.
    var calendarEventID: String = ""

    init(title: String, icon: String, start: Date, end: Date? = nil, weekdays: [Int] = []) {
        let cal = Calendar.current
        self.title = title
        self.icon = icon
        self.start = cal.startOfDay(for: start)
        self.end = end.map { cal.startOfDay(for: $0) }
        self.weekdays = weekdays.sorted()
    }

    var isOneOff: Bool { end == start }

    func isDue(on day: Date) -> Bool {
        let cal = Calendar.current
        let d = cal.startOfDay(for: day)
        guard d >= start else { return false }
        if let end, d > end { return false }
        return weekdays.isEmpty || weekdays.contains(cal.component(.weekday, from: d))
    }

    func isDone(on day: Date) -> Bool {
        let d = Calendar.current.startOfDay(for: day)
        return doneDays.contains(d)
    }

    func toggle(on day: Date) {
        let d = Calendar.current.startOfDay(for: day)
        if let i = doneDays.firstIndex(of: d) { doneDays.remove(at: i) } else { doneDays.append(d) }
    }

    /// "Once · Fri, Nov 6", "Every day", "Mon, Thu", with "until …" when it ends.
    var scheduleText: String {
        if isOneOff { return "Once · " + start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
        let days: String
        if weekdays.isEmpty || weekdays.count == 7 {
            days = "Every day"
        } else {
            let symbols = Calendar.current.shortWeekdaySymbols
            let order = (0..<7).map { (Calendar.current.firstWeekday - 1 + $0) % 7 + 1 }
            days = order.filter(weekdays.contains).map { symbols[$0 - 1] }.joined(separator: ", ")
        }
        guard let end else { return days }
        return days + " · until " + end.formatted(.dateTime.month(.abbreviated).day())
    }
}
