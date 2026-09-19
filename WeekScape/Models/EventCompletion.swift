//
//  EventCompletion.swift
//  WeekScape
//
//  Completion state for an imported calendar event. Events themselves are
//  read-only EventKit data rebuilt on every fetch, so "checked off" can't live
//  on the event — it's recorded here, keyed by the event's per-occurrence id.
//
//  CloudKit compatibility notes: every stored property has a default value and
//  there are no unique constraints, matching `Plan`.
//

import Foundation
import SwiftData

@Model
final class EventCompletion {
    /// Matches `CalendarEvent.id`, which folds the occurrence start into the
    /// EventKit identifier so each instance of a recurring event is distinct.
    var eventID: String = ""

    var completedAt: Date = Date()

    init(eventID: String) {
        self.eventID = eventID
        self.completedAt = Date()
    }
}

// MARK: - Actions

/// Mutations on calendar-event completion, mirroring `PlanActions` for plans.
enum EventActions {
    /// Check an event off, or clear it if it was already checked off.
    ///
    /// Fetches the occurrence's own records rather than taking the whole list,
    /// so callers can hold completions as a `Set` of ids for O(1) display
    /// lookups instead of scanning an array per row.
    static func toggleDone(eventID: String, in context: ModelContext) {
        var descriptor = FetchDescriptor<EventCompletion>(
            predicate: #Predicate { $0.eventID == eventID }
        )
        descriptor.fetchLimit = 8
        let existing = (try? context.fetch(descriptor)) ?? []

        if existing.isEmpty {
            context.insert(EventCompletion(eventID: eventID))
        } else {
            // Defensive: CloudKit can't enforce uniqueness, so clear any
            // duplicate records for the same occurrence.
            for record in existing {
                context.delete(record)
            }
        }
    }
}
