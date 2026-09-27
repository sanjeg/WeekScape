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
        // No SwiftUI NavigationStack here on purpose: the controller brings its
        // own UINavigationController, and Apple's Edit button lives in that
        // bar. Wrapping this in a NavigationStack replaces the bar and the
        // Edit button never appears, leaving title and date uneditable.
        EventDetailController(
            event: event,
            eventStore: eventStore,
            allowsEditing: isEditable
        ) {
            dismiss()
        }
        .ignoresSafeArea()
    }
}

#if os(iOS)

/// Hosts `EKEventViewController`, which renders Calendar's event detail page.
private struct EventDetailController: UIViewControllerRepresentable {
    let event: EKEvent
    let eventStore: EKEventStore
    let allowsEditing: Bool
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = EKEventViewController()
        controller.event = event
        // Apple's Edit button pushes its own editor — the only way to change
        // title, date and time. It is placed in the controller's own
        // navigation bar, which is why a UINavigationController hosts it.
        // Only surfaced when the source calendar accepts changes.
        controller.allowsEditing = allowsEditing
        controller.allowsCalendarPreview = true
        controller.delegate = context.coordinator

        // Our own dismissal, on the left so it doesn't collide with Edit.
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [onDone] _ in onDone() }
        )

        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ nav: UINavigationController, context: Context) {
        guard let controller = nav.viewControllers.first as? EKEventViewController else { return }
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
