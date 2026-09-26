//
//  Formatters.swift
//  Weekend Planner
//
//  Shared, cached formatters for presenting week ranges and dates. Creating
//  DateFormatters is expensive, so we reuse them.
//

import Foundation

enum PlannerFormat {
    /// e.g. "Aug 4 – 10" or "Aug 28 – Sep 3" (omits the year and repeated month).
    static func weekRange(_ week: Week) -> String {
        let cal = WeekConfig.calendar
        let start = week.start
        let end = week.end

        let sameMonth = cal.isDate(start, equalTo: end, toGranularity: .month)
        let sameYear = cal.isDate(start, equalTo: end, toGranularity: .year)
        let currentYear = cal.isDate(start, equalTo: Date(), toGranularity: .year)

        if sameMonth {
            let head = start.formatted(.dateTime.month(.abbreviated).day())
            let tail = end.formatted(.dateTime.day())
            let year = currentYear ? "" : ", \(start.formatted(.dateTime.year()))"
            return "\(head) – \(tail)\(year)"
        } else {
            let head = start.formatted(.dateTime.month(.abbreviated).day())
            let tailFormat: Date.FormatStyle = sameYear
                ? .dateTime.month(.abbreviated).day()
                : .dateTime.month(.abbreviated).day().year()
            return "\(head) – \(end.formatted(tailFormat))"
        }
    }

    /// A friendly relative label for a week ("This week", "Next week", "In 3 weeks").
    static func weekTitle(_ week: Week) -> String {
        switch week.offsetFromNow {
        case 0: return "This week"
        case 1: return "Next week"
        case -1: return "Last week"
        case let n where n > 1: return "In \(n) weeks"
        default: return "\(-week.offsetFromNow) weeks ago"
        }
    }

    /// Weekday + day for a plan pinned to a specific date, e.g. "Sat 9".
    static func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    /// The day badge for an item occupying `start...lastDay`, as seen from
    /// `week`: a single day, the full span, or — when the span runs beyond the
    /// week — how it relates to that week (starts, continues, or ends here).
    ///
    /// Shared by plan rows and calendar-event rows so both read the same way.
    static func spanBadge(start: Date, lastDay: Date, in week: Week?) -> String {
        let calendar = WeekConfig.calendar
        let first = calendar.startOfDay(for: start)
        let last = max(calendar.startOfDay(for: lastDay), first)

        guard last > first else { return dayLabel(start) }
        guard let week else { return dayRangeLabel(from: first, to: last) }

        let startsHere = first >= week.start && first <= week.end
        let endsHere = last >= week.start && last <= week.end
        switch (startsHere, endsHere) {
        case (true, true):   return dayRangeLabel(from: first, to: last)
        case (true, false):  return "\(dayLabel(first)) →"
        case (false, true):  return "→ \(dayLabel(last))"
        case (false, false): return "continues"
        }
    }

    /// A compact label for a multi-day span, e.g. "Sat 9 – Sun 10". When the
    /// span crosses into another month the month is shown on both ends so the
    /// range stays unambiguous.
    static func dayRangeLabel(from start: Date, to end: Date) -> String {
        let cal = WeekConfig.calendar
        if cal.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(dayLabel(start)) – \(dayLabel(end))"
        }
        let head = start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let tail = end.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(head) – \(tail)"
    }
}
