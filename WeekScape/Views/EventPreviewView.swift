//
//  EventPreviewView.swift
//  WeekScape
//
//  A custom, read-only detail page for a calendar event, shown in a sheet so
//  the event can be previewed without leaving WeekScape. Built in SwiftUI (not
//  EKEventViewController) so every field is under our control — notably the
//  Calendar row, which shows a static "Account - Calendar" label rather than an
//  editable picker — and so the "Open in Calendar" action is always visible.
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

    /// "Account Name - Calendar Name" row with the calendar's color dot. The
    /// whole row is a link that opens the event in the Calendar app.
    private var calendarRow: some View {
        Button(action: openInCalendar) {
            HStack {
                Text("Calendar")
                    .foregroundStyle(.primary)
                Spacer()
                Circle()
                    .fill(calendarColor)
                    .frame(width: 10, height: 10)
                Text(calendarText)
                    .foregroundStyle(.tint)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "arrow.up.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens in Calendar")
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
            return "\(start.formatted(date: .abbreviated, time: .omitted)) · All day"
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

    /// Hand off to the Calendar app, landing on the event's day. iOS has no
    /// public URL to select a specific event.
    private func openInCalendar() {
        let seconds = (event.startDate ?? .now).timeIntervalSinceReferenceDate
        if let url = URL(string: "calshow:\(seconds)") {
            openURL(url)
        }
    }
}
