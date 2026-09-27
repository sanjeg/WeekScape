//
//  EventPreviewView.swift
//  WeekScape
//
//  The detail page for an imported calendar event. This wraps EventKitUI's
//  `EKEventViewController`, so the user sees exactly what the Calendar app
//  shows — times, location, recurrence, notes and attendees — rather than a
//  hand-rolled approximation.
//
//  iOS has no public URL that opens a specific event in the Calendar app
//  (`calshow:` only takes a time and lands on that day), so presenting
//  Calendar's own UI in a sheet is how the real detail page is reached.
//
//  The page is deliberately view-only. Turning on `allowsEditing` makes the
//  controller render *two* separate Delete Event controls (`delete-event-cell`
//  inside the card and `delete-event-button` below it), which there is no
//  public way to collapse into one. Editing calendar events happens in the
//  Calendar app.
//

import SwiftUI
import EventKit
import EventKitUI

struct EventPreviewView: View {
    let event: EKEvent
    let eventStore: EKEventStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EventDetailController(event: event, eventStore: eventStore) {
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
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> EKEventViewController {
        let controller = EKEventViewController()
        controller.event = event
        controller.allowsEditing = false
        controller.allowsCalendarPreview = true
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventViewController, context: Context) {
        // The event is fixed for the lifetime of the sheet.
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
