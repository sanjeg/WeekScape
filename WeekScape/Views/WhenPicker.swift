//
//  WhenPicker.swift
//  WeekScape
//
//  One control for a plan's scheduling. It reads like a date picker — a summary
//  row that expands into a month calendar — but the granularity segment lets the
//  user commit to an exact day or to a whole week with no day at all. This
//  replaces the separate week picker, "pin to a day" toggle, and date picker.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// When a plan is scheduled: an exact day, or a whole week with no committed day.
enum PlanWhen: Equatable {
    case week(Date)
    case day(Date)

    /// Normalized start of the week this selection falls in.
    var weekStart: Date {
        switch self {
        case .week(let start): return WeekConfig.startOfWeek(for: start)
        case .day(let day): return WeekConfig.startOfWeek(for: day)
        }
    }

    /// The committed day, when there is one.
    var day: Date? {
        switch self {
        case .week: return nil
        case .day(let day): return WeekConfig.calendar.startOfDay(for: day)
        }
    }

    var isExactDay: Bool { day != nil }

    /// Summary shown on the collapsed row.
    var label: String {
        switch self {
        case .day(let day):
            return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        case .week(let start):
            return "Week of \(PlannerFormat.weekRange(Week(start: start)))"
        }
    }
}

struct WhenPicker: View {
    @Binding var selection: PlanWhen

    /// Re-read so the grid's first column matches the user's week start.
    @AppStorage(WeekConfig.firstWeekdayKey) private var firstWeekday: Int = 2

    @State private var isExpanded = false
    @State private var visibleMonth: Date

    /// Whether the month/year wheels are showing in place of the day grid.
    @State private var isChoosingMonth = false

    private enum Granularity: Hashable {
        case day, week
    }

    init(selection: Binding<PlanWhen>) {
        _selection = selection
        let anchor = selection.wrappedValue.day ?? selection.wrappedValue.weekStart
        _visibleMonth = State(initialValue: Self.monthStart(of: anchor))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryRow

            if isExpanded {
                granularityPicker
                    .padding(.top, Theme.spacing4)

                if isChoosingMonth {
                    monthYearWheels
                        .padding(.top, Theme.spacing3)
                } else {
                    monthHeader
                        .padding(.top, Theme.spacing4)

                    weekdayHeader
                    grid
                }

                Text(selection.isExactDay
                     ? "Tap a day to pin the plan to it."
                     : "Tap any day to choose its week — the plan floats in that week.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.spacing2)
            }
        }
        .padding(.vertical, Theme.spacing1)
    }

    // MARK: - Summary row

    private var summaryRow: some View {
        Button {
            // Drop the keyboard first — the title field is usually focused when
            // the sheet opens, and it would otherwise cover the calendar.
            dismissKeyboard()
            withAnimation(.snappy) {
                isExpanded.toggle()
                // Never reopen straight into the year wheels.
                if !isExpanded { isChoosingMonth = false }
            }
        } label: {
            HStack {
                Text("When")
                    .foregroundStyle(Color.primary)

                Spacer()

                Text(selection.label)
                    .foregroundStyle(isExpanded ? Color.accentColor : Color.secondary)

                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("When: \(selection.label)")
        .accessibilityHint(isExpanded ? "Collapses the calendar" : "Expands the calendar")
    }

    // MARK: - Granularity

    private var granularityPicker: some View {
        Picker("Granularity", selection: granularity) {
            Text("Exact day").tag(Granularity.day)
            Text("Whole week").tag(Granularity.week)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// Switching granularity converts the current selection rather than
    /// clearing it, so the user never loses their place in the calendar.
    private var granularity: Binding<Granularity> {
        Binding(
            get: { selection.isExactDay ? .day : .week },
            set: { newValue in
                switch newValue {
                case .day:
                    // Commit to a day in the already-chosen week: today when it
                    // falls there, otherwise the week's first day.
                    let week = Week(start: selection.weekStart)
                    let today = WeekConfig.calendar.startOfDay(for: Date())
                    withAnimation(.snappy) {
                        selection = .day(week.contains(today) ? today : week.start)
                    }
                case .week:
                    withAnimation(.snappy) { selection = .week(selection.weekStart) }
                }
            }
        )
    }

    // MARK: - Month navigation

    private var monthHeader: some View {
        HStack {
            // The title itself opens the month/year wheels, matching the system
            // date picker's behavior.
            Button {
                withAnimation(.snappy) { isChoosingMonth = true }
            } label: {
                HStack(spacing: Theme.spacing1) {
                    Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.forward")
                        .font(.caption2.weight(.bold))
                }
            }
            .accessibilityLabel("\(visibleMonth.formatted(.dateTime.month(.wide).year())), choose month and year")

            Spacer()

            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous month")

            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right")
            }
            .padding(.leading, Theme.spacing3)
            .accessibilityLabel("Next month")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    /// Month and year wheels shown in place of the grid, so the user can jump
    /// years ahead or back without paging a month at a time.
    private var monthYearWheels: some View {
        VStack(spacing: Theme.spacing2) {
            HStack(spacing: 0) {
                Picker("Month", selection: monthBinding) {
                    ForEach(Array(monthSymbols.enumerated()), id: \.offset) { index, name in
                        Text(name).tag(index + 1)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()

                Picker("Year", selection: yearBinding) {
                    ForEach(yearRange, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .frame(height: 140)
            .labelsHidden()

            Button("Done") {
                withAnimation(.snappy) { isChoosingMonth = false }
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    private var monthBinding: Binding<Int> {
        Binding(
            get: { WeekConfig.calendar.component(.month, from: visibleMonth) },
            set: { setVisibleMonth(month: $0, year: nil) }
        )
    }

    private var yearBinding: Binding<Int> {
        Binding(
            get: { WeekConfig.calendar.component(.year, from: visibleMonth) },
            set: { setVisibleMonth(month: nil, year: $0) }
        )
    }

    private func setVisibleMonth(month: Int?, year: Int?) {
        let cal = WeekConfig.calendar
        var comps = cal.dateComponents([.year, .month], from: visibleMonth)
        if let month { comps.month = month }
        if let year { comps.year = year }
        if let date = cal.date(from: comps) {
            visibleMonth = date
        }
    }

    /// Localized full month names in calendar order.
    ///
    /// Formatted from real dates rather than `Calendar.monthSymbols`:
    /// `WeekConfig.calendar` is built without a locale, so its symbol arrays
    /// come back as ICU fallbacks ("M09" instead of "September").
    private var monthSymbols: [String] {
        let cal = WeekConfig.calendar
        return (1...12).compactMap { month in
            cal.date(from: DateComponents(year: 2001, month: month, day: 1))?
                .formatted(.dateTime.month(.wide))
        }
    }

    /// A generous span around today, wide enough for long-range planning.
    private var yearRange: [Int] {
        let cal = WeekConfig.calendar
        let thisYear = cal.component(.year, from: Date())
        let selectedYear = cal.component(.year, from: visibleMonth)
        let lower = min(thisYear - 5, selectedYear)
        let upper = max(thisYear + 25, selectedYear)
        return Array(lower...upper)
    }

    /// Dismisses the keyboard without the editor having to hand focus down.
    private func dismissKeyboard() {
        #if os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }

    private func shiftMonth(_ delta: Int) {
        let cal = WeekConfig.calendar
        guard let shifted = cal.date(byAdding: .month, value: delta, to: visibleMonth) else { return }
        withAnimation(.snappy) { visibleMonth = Self.monthStart(of: shifted) }
    }

    // MARK: - Grid

    private var weekdayHeader: some View {
        HStack(spacing: Theme.spacing1) {
            // Keyed by position, not value: narrow symbols repeat ("T" for
            // Tue/Thu, "S" for Sat/Sun), so `id: \.self` collides.
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, Theme.spacing2)
    }

    private var grid: some View {
        VStack(spacing: 2) {
            ForEach(weekRows, id: \.self) { rowStart in
                let week = Week(start: rowStart)
                HStack(spacing: Theme.spacing1) {
                    ForEach(week.days, id: \.self) { day in
                        dayCell(day)
                    }
                }
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        // In week mode the selected week reads as one block.
                        .fill(isSelectedWeek(rowStart)
                              ? Color.accentColor.opacity(0.18)
                              : Color.clear)
                )
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let cal = WeekConfig.calendar
        let isSelectedDay = selection.day.map { cal.isDate($0, inSameDayAs: day) } ?? false
        let isToday = cal.isDateInToday(day)
        let inMonth = cal.isDate(day, equalTo: visibleMonth, toGranularity: .month)

        return Button {
            withAnimation(.snappy) {
                selection = selection.isExactDay
                    ? .day(day)
                    : .week(WeekConfig.startOfWeek(for: day))
            }
        } label: {
            Text(day.formatted(.dateTime.day()))
                .font(.callout.weight(isSelectedDay || isToday ? .bold : .regular))
                .foregroundStyle(dayForeground(isSelectedDay: isSelectedDay, inMonth: inMonth))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    Circle()
                        .fill(isSelectedDay ? Color.accentColor : Color.clear)
                )
                .overlay(
                    Circle()
                        .stroke(Color.accentColor.opacity(isToday && !isSelectedDay ? 0.6 : 0), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityAddTraits(isSelectedDay ? [.isSelected] : [])
    }

    private func dayForeground(isSelectedDay: Bool, inMonth: Bool) -> Color {
        if isSelectedDay { return .white }
        return inMonth ? .primary : .secondary.opacity(0.5)
    }

    private func isSelectedWeek(_ rowStart: Date) -> Bool {
        !selection.isExactDay && selection.weekStart == rowStart
    }

    // MARK: - Calendar math

    /// Week start dates for every row needed to cover the visible month.
    private var weekRows: [Date] {
        _ = firstWeekday // establish dependency so the grid re-lays out
        let cal = WeekConfig.calendar
        guard let monthRange = cal.range(of: .day, in: .month, for: visibleMonth),
              let monthEnd = cal.date(byAdding: .day, value: monthRange.count - 1, to: visibleMonth)
        else { return [] }

        var rows: [Date] = []
        var cursor = WeekConfig.startOfWeek(for: visibleMonth)
        let lastRow = WeekConfig.startOfWeek(for: monthEnd)
        while cursor <= lastRow {
            rows.append(cursor)
            guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        return rows
    }

    /// Weekday initials for the column headers. Taken from an actual week so
    /// they are localized and already start on the user's first weekday —
    /// `Calendar.veryShortWeekdaySymbols` has the same fallback problem as
    /// `monthSymbols` and would need rotating besides.
    private var weekdaySymbols: [String] {
        _ = firstWeekday // establish dependency for recomputation
        return Week(start: WeekConfig.startOfWeek(for: Date())).days.map {
            $0.formatted(.dateTime.weekday(.narrow))
        }
    }

    private static func monthStart(of date: Date) -> Date {
        let cal = WeekConfig.calendar
        return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }
}

#Preview("When picker", traits: .sizeThatFitsLayout) {
    @Previewable @State var when = PlanWhen.week(WeekConfig.startOfWeek(for: .now))

    Form {
        Section {
            WhenPicker(selection: $when)
        }
    }
}
