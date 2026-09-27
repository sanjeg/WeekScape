//
//  CalendarStore.swift
//  WeekScape
//
//  Bridges the app to the user's iPhone Calendar via EventKit. Events are shown
//  as read-only reference data alongside plans, so this store only ever reads —
//  it never creates, edits, or deletes calendar data.
//
//  Reading events requires *full* access (EventKit has no read-only level). The
//  app targets iOS 26, so only the modern access API is used.
//

import Foundation
import EventKit
import SwiftUI
import Observation

/// A lightweight, value-type snapshot of an `EKEvent` for display. Not persisted;
/// rebuilt on every fetch so it always reflects the live calendar.
struct CalendarEvent: Identifiable, Hashable {
    let id: String
    /// Raw EventKit identifier, used to resolve the live `EKEvent` for preview.
    let eventIdentifier: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color

    init(_ event: EKEvent) {
        // Recurring events share an identifier across occurrences, so fold the
        // occurrence start into the id to keep each instance unique.
        let base = event.eventIdentifier ?? event.calendarItemIdentifier
        let startStamp = event.startDate?.timeIntervalSince1970 ?? 0
        self.id = "\(base)-\(startStamp)"
        self.eventIdentifier = base
        self.title = event.title ?? "(No title)"
        self.start = event.startDate ?? .now
        self.end = event.endDate ?? event.startDate ?? .now
        self.isAllDay = event.isAllDay
        if let cg = event.calendar?.cgColor {
            self.color = Color(cgColor: cg)
        } else {
            self.color = .secondary
        }
    }

    /// The first day the event occupies.
    var firstDay: Date {
        WeekConfig.calendar.startOfDay(for: start)
    }

    /// The last day the event occupies, inclusive.
    ///
    /// EventKit stores an exclusive end: an all-day event on Sep 12 ends at
    /// midnight on Sep 13, and a timed event can likewise run to midnight.
    /// Stepping back off an exact midnight keeps a one-day event from counting
    /// as two.
    var lastDay: Date {
        let calendar = WeekConfig.calendar
        var effectiveEnd = end
        if effectiveEnd > start, effectiveEnd == calendar.startOfDay(for: effectiveEnd) {
            effectiveEnd = effectiveEnd.addingTimeInterval(-1)
        }
        return max(calendar.startOfDay(for: effectiveEnd), firstDay)
    }

    /// True when the event covers more than one day.
    var isMultiDay: Bool {
        lastDay > firstDay
    }

    /// Start dates of every week this event runs across, so a multi-day event
    /// appears in each of them the way a multi-day plan does.
    var occupiedWeekStarts: [Date] {
        WeekConfig.weekStarts(from: firstDay, through: lastDay)
    }
}

/// Central place for the app's calendar keys, mirroring `WeekConfig`.
enum CalendarConfig {
    static let showEventsKey = "showCalendarEvents"
    static let selectedCalendarIDsKey = "selectedCalendarIDs"
}

@MainActor
@Observable
final class CalendarStore {
    private let store = EKEventStore()

    /// The backing store, needed by `EKEventViewController` to render an
    /// event's detail page. Read-only use only — this app never writes events.
    var eventStore: EKEventStore { store }

    /// Current calendar authorization for events.
    private(set) var authorizationStatus: EKAuthorizationStatus

    /// Events for the most recently requested window (empty unless the feature
    /// is enabled and the app is authorized).
    private(set) var events: [CalendarEvent] = []

    /// The last window we loaded, so change notifications can re-fetch it.
    private var lastWindow: DateInterval?

    /// Whether the user has opted in to showing calendar events.
    var showEvents: Bool {
        didSet {
            guard oldValue != showEvents else { return }
            UserDefaults.standard.set(showEvents, forKey: CalendarConfig.showEventsKey)
            reloadLastWindow()
        }
    }

    /// Identifiers of the calendars the user chose to include.
    var selectedCalendarIDs: Set<String> {
        didSet {
            guard oldValue != selectedCalendarIDs else { return }
            UserDefaults.standard.set(Array(selectedCalendarIDs), forKey: CalendarConfig.selectedCalendarIDsKey)
            reloadLastWindow()
        }
    }

    init() {
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        self.showEvents = UserDefaults.standard.bool(forKey: CalendarConfig.showEventsKey)
        let stored = UserDefaults.standard.stringArray(forKey: CalendarConfig.selectedCalendarIDsKey) ?? []
        self.selectedCalendarIDs = Set(stored)
    }

    // MARK: - Authorization

    private var isAuthorized: Bool { authorizationStatus == .fullAccess }

    /// Prompt for full access to events. Returns whether access was granted.
    /// On first grant with no saved selection, defaults to including every calendar.
    func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if granted, selectedCalendarIDs.isEmpty {
            selectedCalendarIDs = Set(availableCalendars().map(\.calendarIdentifier))
        }
        return granted
    }

    /// Calendars that can contain events, for the selection UI.
    func availableCalendars() -> [EKCalendar] {
        guard isAuthorized else { return [] }
        return store.calendars(for: .event)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Fetching

    /// Load events for `window`, filtered to the selected calendars. Clears the
    /// list when the feature is off or the app isn't authorized.
    func reload(window: DateInterval) {
        lastWindow = window
        guard showEvents, isAuthorized else {
            events = []
            return
        }

        let calendars = store.calendars(for: .event)
            .filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        // No calendars selected means nothing to show.
        guard !calendars.isEmpty else {
            events = []
            return
        }

        let predicate = store.predicateForEvents(
            withStart: window.start,
            end: window.end,
            calendars: calendars
        )
        events = store.events(matching: predicate)
            .map(CalendarEvent.init)
            .sorted { $0.start < $1.start }
    }

    private func reloadLastWindow() {
        guard let lastWindow else { return }
        reload(window: lastWindow)
    }

    /// Resolve the live `EKEvent` behind a snapshot so it can be previewed.
    /// Matches the exact occurrence when possible — recurring events share an
    /// identifier across occurrences, so the start date disambiguates them.
    func resolveEvent(_ snapshot: CalendarEvent) -> EKEvent? {
        guard isAuthorized else { return nil }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: snapshot.start)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? snapshot.end
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        let occurrence = store.events(matching: predicate).first {
            $0.eventIdentifier == snapshot.eventIdentifier
                && abs($0.startDate.timeIntervalSince(snapshot.start)) < 1
        }
        return occurrence ?? store.event(withIdentifier: snapshot.eventIdentifier)
    }

    // MARK: - Live updates

    /// Watch for external calendar changes and re-fetch the current window.
    /// Runs until the surrounding `.task` is cancelled.
    func observeChanges() async {
        let notifications = NotificationCenter.default.notifications(named: .EKEventStoreChanged)
        for await _ in notifications {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            reloadLastWindow()
        }
    }
}
