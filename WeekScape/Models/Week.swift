//
//  Week.swift
//  Weekend Planner
//
//  Value types and calendar helpers for reasoning about whole weeks — the
//  fundamental time unit of the app. There are deliberately no day/hour grids.
//

import Foundation

/// A single week, identified by its normalized start date.
struct Week: Identifiable, Hashable {
    let start: Date

    var id: Date { start }

    /// Inclusive last day of the week (start + 6 days).
    var end: Date {
        WeekConfig.calendar.date(byAdding: .day, value: 6, to: start) ?? start
    }

    /// The seven dates in this week, from `start` to `end`.
    var days: [Date] {
        (0..<7).compactMap {
            WeekConfig.calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    var isCurrent: Bool {
        WeekConfig.calendar.isDate(start, equalTo: Date(), toGranularity: .weekOfYear)
    }

    /// Number of weeks from the current week (negative = past).
    var offsetFromNow: Int {
        let comps = WeekConfig.calendar.dateComponents(
            [.weekOfYear],
            from: WeekConfig.startOfWeek(for: Date()),
            to: start
        )
        return comps.weekOfYear ?? 0
    }

    func contains(_ date: Date) -> Bool {
        WeekConfig.calendar.isDate(date, equalTo: start, toGranularity: .weekOfYear)
    }
}

/// Central place for the app's week arithmetic so every view agrees on where a
/// week starts. The first weekday is user-configurable (Sunday vs. Monday).
enum WeekConfig {
    static let firstWeekdayKey = "firstWeekday"

    /// How many upcoming weeks the stream shows by default (user-configurable).
    static let weeksAheadKey = "defaultWeeksAhead"
    static let defaultWeeksAhead = 8

    /// Stored first weekday (1 = Sunday ... 7 = Saturday). Defaults to Monday.
    static var firstWeekday: Int {
        let stored = UserDefaults.standard.integer(forKey: firstWeekdayKey)
        return (1...7).contains(stored) ? stored : 2
    }

    /// Last calendar handed out, with the first weekday it was built for.
    private static var cachedCalendar: (weekday: Int, calendar: Calendar)?

    /// The app's calendar.
    ///
    /// Cached because this is a hot path: every `Week` accessor, every
    /// `PlanActions.occupies` check, and every date format goes through it, so
    /// a scroll through the stream hits it thousands of times. Rebuilding a
    /// `Calendar` each time also re-read `UserDefaults` on every call. The
    /// cache is keyed on the stored first weekday, so changing that setting
    /// still takes effect immediately.
    static var calendar: Calendar {
        let weekday = firstWeekday
        if let cached = cachedCalendar, cached.weekday == weekday {
            return cached.calendar
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = weekday
        cachedCalendar = (weekday, calendar)
        return calendar
    }

    /// Midnight on the first day of the week containing `date`.
    static func startOfWeek(for date: Date) -> Date {
        let calendar = calendar
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
    }

    /// A window of weeks: `past` weeks before the current week through
    /// `future` weeks after it (inclusive of the current week).
    static func window(past: Int, future: Int) -> [Week] {
        let current = startOfWeek(for: Date())
        return (-past...future).compactMap { offset in
            calendar.date(byAdding: .weekOfYear, value: offset, to: current)
                .map { Week(start: startOfWeek(for: $0)) }
        }
    }
}
