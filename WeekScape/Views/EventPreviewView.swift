//
//  EventPreviewView.swift
//  WeekScape
//
//  The detail page for an imported calendar event. This wraps EventKitUI's
//  `EKEventViewController`, so the user sees exactly what the Calendar app
//  shows — attendees, alerts, recurrence, travel time, notes, and an Edit
//  button — rather than a hand-rolled approximation.
//
//  iOS has no public URL that opens a specific event in the Calendar app
//  (`calshow:` only takes a time and lands on that day), so presenting
//  Calendar's own UI in a sheet is how the real detail page is reached.
//
//  Editing is offered only for events the user can actually change. A
//  subscribed calendar (a webcal feed, Holidays, Birthdays) reports
//  `allowsContentModifications == false`, and offering Edit there would lead
//  to a dead end — so the page stays view-only for those.
//

import SwiftUI
import EventKit
import EventKitUI

struct EventPreviewView: View {
    let event: EKEvent
    let eventStore: EKEventStore

    @Environment(\.dismiss) private var dismiss

    /// Whether the event's calendar accepts changes. False for subscribed
    /// feeds, Holidays and Birthdays, which are read-only at the source.
    private var isEditable: Bool {
        event.calendar?.allowsContentModifications ?? false
    }

    var body: some View {
        NavigationStack {
            EventDetailController(
                event: event,
                eventStore: eventStore,
                allowsEditing: isEditable
            ) {
                dismiss()
            }
            .ignoresSafeArea()
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
}

#if os(iOS)

/// Hosts `EKEventViewController`, which renders Calendar's event detail page.
private struct EventDetailController: UIViewControllerRepresentable {
    let event: EKEvent
    let eventStore: EKEventStore
    let allowsEditing: Bool
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> EKEventViewController {
        let controller = EKEventViewController()
        controller.event = event
        // Apple's Edit button pushes its own editor, which also offers Delete.
        // Only surfaced when the source calendar accepts changes.
        controller.allowsEditing = allowsEditing
        controller.allowsCalendarPreview = true
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventViewController, context: Context) {
        controller.allowsEditing = allowsEditing
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: onDone)
    }

    final class Coordinator: NSObject, EKEventViewDelegate {
        private let onDone: () -> Void

        init(onDone: @escaping () -> Void) {
            self.onDone = onDone
        }

        func eventViewController(_ controller: EKEventViewController,
                                 didCompleteWith action: EKEventViewAction) {
            onDone()
        }
    }
}

#else

/// macOS has no EventKitUI; fall back to a minimal read-only summary.
private struct EventDetailController: View {
    let event: EKEvent
    let eventStore: EKEventStore
    let allowsEditing: Bool
    let onDone: () -> Void

    var body: some View {
        List {
            Text(event.title ?? "(No title)")
                .font(.title3.weight(.semibold))
            if let start = event.startDate {
                LabeledContent("When", value: start.formatted(date: .abbreviated, time: .shortened))
            }
            if let notes = event.notes, !notes.isEmpty {
                Section("Notes") { Text(notes) }
            }
        }
    }
}

#endif
