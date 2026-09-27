//
//  EventPreviewView.swift
//  WeekScape
//
//  A read-only detail page for an imported calendar event, shown in a sheet so
//  the event can be inspected without leaving WeekScape.
//
//  Built in SwiftUI rather than with EventKitUI's `EKEventViewController`: that
//  controller renders the Calendar row as a live picker which writes straight
//  back to the user's calendar, even with `allowsEditing = false`. WeekScape is
//  read-only toward the calendar, so the source calendar is shown as plain text
//  and editing is handed off to the Calendar app through an explicit link.
//

import SwiftUI
import EventKit

struct EventPreviewView: View {
    let event: EKEvent

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: Theme.spacing3) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(calendarColor)
                            .frame(width: 4, height: 34)
                        Text(title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, Theme.spacing1)
                }

                Section {
                    LabeledContent("When", value: whenText)
                    if let location = event.location, !location.isEmpty {
                        LabeledContent("Location", value: location)
                    }
                    calendarRow
                }

                if let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !notes.isEmpty {
                    Section("Notes") {
                        Text(notes)
                    }
                }

                if let url = event.url {
                    Section {
                        Link(destination: url) {
                            Text(url.absoluteString)
                                .lineLimit(1)
                        }
                    }
                }

                Section {
                    openInCalendarRow
                } footer: {
                    Text("WeekScape never changes your calendar. Open the event in Calendar to edit it.")
                }
            }
            .navigationTitle("Event")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Rows

    /// Which calendar the event came from — static text, so the source calendar
    /// can be seen but never reassigned from here.
    private var calendarRow: some View {
        HStack {
            Text("Calendar")
                .foregroundStyle(.primary)
            Spacer()
            Circle()
                .fill(calendarColor)
                .frame(width: 10, height: 10)
            Text(calendarText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Calendar: \(calendarText)")
    }

    /// Explicit hand-off for editing, kept separate from the calendar row so
    /// tapping the source calendar can't be mistaken for changing it.
    private var openInCalendarRow: some View {
        Button(action: openInCalendar) {
            HStack {
                Label("Open in Calendar", systemImage: "calendar")
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Calendar app on this event's day")
    }

    // MARK: - Derived values

    private var title: String {
        let trimmed = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "(No title)" : trimmed
    }

    private var calendarColor: Color {
        event.calendar.map { Color(cgColor: $0.cgColor) } ?? .secondary
    }

    /// "Account Name - Calendar Name", falling back to just the calendar name
    /// when the source has no title.
    private var calendarText: String {
        guard let calendar = event.calendar else { return "—" }
        let account = calendar.source.title
        return account.isEmpty ? calendar.title : "\(account) - \(calendar.title)"
    }

    private var whenText: String {
        let start = event.startDate ?? .now
        if event.isAllDay {
            // Same end-date interpretation the week cards use, so the badge and
            // this row can't disagree about the final day.
            let lastDay = EventSpan.lastDay(start: start, end: event.endDate ?? start)
            if WeekConfig.calendar.isDate(start, inSameDayAs: lastDay) {
                return "\(start.formatted(date: .abbreviated, time: .omitted)) · All day"
            }
            let from = start.formatted(date: .abbreviated, time: .omitted)
            let to = lastDay.formatted(date: .abbreviated, time: .omitted)
            return "\(from) – \(to) · All day"
        }
        let end = event.endDate ?? start
        if Calendar.current.isDate(start, inSameDayAs: end) {
            let day = start.formatted(date: .abbreviated, time: .omitted)
            let from = start.formatted(date: .omitted, time: .shortened)
            let to = end.formatted(date: .omitted, time: .shortened)
            return "\(day) · \(from) – \(to)"
        }
        let from = start.formatted(date: .abbreviated, time: .shortened)
        let to = end.formatted(date: .abbreviated, time: .shortened)
        return "\(from) – \(to)"
    }

    // MARK: - Actions

    /// Hand off to the Calendar app, landing on the event's day.
    ///
    /// `calshow:` takes seconds since the reference date and opens the day
    /// view at that moment, which is as close as iOS lets a third-party app
    /// get — there is no public URL that selects a specific event. The exact
    /// start time is passed (rather than midnight) so a timed event lands at
    /// its own hour rather than the top of the day.
    private func openInCalendar() {
        let target = event.startDate ?? .now
        let seconds = target.timeIntervalSinceReferenceDate
        if let url = URL(string: "calshow:\(Int(seconds))") {
            openURL(url)
        }
    }
}
