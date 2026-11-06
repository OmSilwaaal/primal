import XCTest
@testable import NutriCore

final class GoalTests: XCTestCase {
    private let cal = Calendar.current
    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: .now))! }

    func testOneOffIsDueOnlyOnItsDay() {
        let g = Goal(title: "Raw liver", icon: "heart", start: day(2), end: day(2))
        XCTAssertTrue(g.isOneOff)
        XCTAssertTrue(g.isDue(on: day(2)))
        XCTAssertFalse(g.isDue(on: day(1)))
        XCTAssertFalse(g.isDue(on: day(3)))
    }

    func testEveryDayRunsFromStartUntilEnd() {
        let open = Goal(title: "Morning sun", icon: "sun.max", start: day(-3))
        XCTAssertFalse(open.isDue(on: day(-4)))
        XCTAssertTrue(open.isDue(on: day(-3)))
        XCTAssertTrue(open.isDue(on: day(400)))
        let ending = Goal(title: "Broth", icon: "flame", start: day(0), end: day(5))
        XCTAssertTrue(ending.isDue(on: day(5)))
        XCTAssertFalse(ending.isDue(on: day(6)))
    }

    func testWeekdaysOnlyOnThoseDays() {
        let g = Goal(title: "Organ meat", icon: "heart", start: day(-14), weekdays: [2, 5])   // Mon, Thu
        for offset in -7...7 {
            let d = day(offset)
            XCTAssertEqual(g.isDue(on: d), [2, 5].contains(cal.component(.weekday, from: d)), "\(d)")
        }
    }

    func testToggleMarksOneDayOnly() {
        let g = Goal(title: "x", icon: "target", start: day(-5))
        g.toggle(on: day(-1).addingTimeInterval(3600 * 15))   // any time that day
        XCTAssertTrue(g.isDone(on: day(-1)))
        XCTAssertFalse(g.isDone(on: day(0)))
        g.toggle(on: day(-1))
        XCTAssertFalse(g.isDone(on: day(-1)))
    }
}

/// How goals become Apple Calendar events (the rule only; adding events needs the person's permission).
@MainActor
final class GoalCalendarTests: XCTestCase {
    private let cal = Calendar.current
    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: .now))! }

    func testOneOffHasNoRepeat() {
        XCTAssertNil(GoalCalendar.recurrence(for: Goal(title: "Liver", icon: "heart", start: day(1), end: day(1))))
    }

    func testEveryDayRepeatsDailyUntilItsEnd() throws {
        let rule = try XCTUnwrap(GoalCalendar.recurrence(for: Goal(title: "Sun", icon: "sun.max", start: day(0), end: day(10))))
        XCTAssertEqual(rule.frequency, .daily)
        XCTAssertNotNil(rule.recurrenceEnd?.endDate)
        XCTAssertNil(GoalCalendar.recurrence(for: Goal(title: "Sun", icon: "sun.max", start: day(0)))?.recurrenceEnd)
    }

    func testChosenWeekdaysRepeatWeeklyOnThoseDays() throws {
        let goal = Goal(title: "Organ meat", icon: "heart", start: day(0), weekdays: [2, 5])
        let rule = try XCTUnwrap(GoalCalendar.recurrence(for: goal))
        XCTAssertEqual(rule.frequency, .weekly)
        XCTAssertEqual(rule.daysOfTheWeek?.map(\.dayOfTheWeek.rawValue).sorted(), [2, 5])
        XCTAssertTrue(goal.isDue(on: GoalCalendar.firstDay(of: goal)), "the event starts on a day the goal is due")
    }
}
