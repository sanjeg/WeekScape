//
//  CalendarPickerView.swift
//  WeekScape
//
//  Lets the user choose which of their iPhone calendars feed into the week
//  stream. Multi-select: tapping a row toggles its inclusion.
//

import SwiftUI
import EventKit

struct CalendarPickerView: View {
    @Environment(CalendarStore.self) private var calendarStore

    /// Available calendars grouped by their source (e.g. iCloud, Gmail), sorted
    /// for a stable, readable list.
    private var groupedCalendars: [(source: String, calendars: [EKCalendar])] {
        let groups = Dictionary(grouping: calendarStore.availableCalendars()) { $0.source.title }
        return groups
            .map { (source: $0.key, calendars: $0.value) }
            .sorted { $0.source.localizedCaseInsensitiveCompare($1.source) == .orderedAscending }
    }

    var body: some View {
        List {
            ForEach(groupedCalendars, id: \.source) { group in
                Section(group.source) {
                    ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                        row(for: calendar)
                    }
                }
            }
        }
        .navigationTitle("Calendars")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func row(for calendar: EKCalendar) -> some View {
        let isSelected = calendarStore.selectedCalendarIDs.contains(calendar.calendarIdentifier)
        return Button {
            toggle(calendar)
        } label: {
            HStack(spacing: Theme.spacing3) {
                Circle()
                    .fill(Color(cgColor: calendar.cgColor))
                    .frame(width: 12, height: 12)
                Text(calendar.title)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggle(_ calendar: EKCalendar) {
        var ids = calendarStore.selectedCalendarIDs
        if ids.contains(calendar.calendarIdentifier) {
            ids.remove(calendar.calendarIdentifier)
        } else {
            ids.insert(calendar.calendarIdentifier)
        }
        calendarStore.selectedCalendarIDs = ids
    }
}
