//
//  WeekListView.swift
//  Weekend Planner
//
//  The heart of the app: a vertical stream of week cards. No hourly, daily, or
//  monthly grid — the week is the atomic unit.
//

import SwiftUI
import SwiftData
import EventKit

struct WeekListView: View {
    @Environment(\.modelContext) private var context
    @Environment(CalendarStore.self) private var calendarStore

    @Query(sort: \Plan.sortOrder) private var allPlans: [Plan]

    // Re-read when settings change so the whole stream recomputes.
    @AppStorage(WeekConfig.firstWeekdayKey) private var firstWeekday: Int = 2
    @AppStorage(WeekConfig.weeksAheadKey) private var storedWeeksAhead: Int = WeekConfig.defaultWeeksAhead

    private let defaultWeeksBehind = 1

    /// Temporary expansions beyond the configured default window. `nil` means
    /// "use the default", which keeps the Settings value authoritative.
    @State private var aheadOverride: Int?
    @State private var behindOverride: Int?
    @State private var editorState: PlanEditorState?

    /// Anchor id for the very top of the stream.
    private let topAnchorID = "stream-top"

    private var weeksAhead: Int { aheadOverride ?? storedWeeksAhead }
    private var weeksBehind: Int { behindOverride ?? defaultWeeksBehind }

    private var weeks: [Week] {
        _ = firstWeekday // establish dependency for recomputation
        return WeekConfig.window(past: weeksBehind, future: weeksAhead)
    }

    /// True when the visible window matches the configured default view.
    private var isDefaultWindow: Bool {
        aheadOverride == nil && behindOverride == nil
    }

    /// Date span covering every visible week, used to fetch calendar events.
    private var eventWindow: DateInterval? {
        guard let first = weeks.first?.start, let last = weeks.last?.end else { return nil }
        return DateInterval(start: first, end: last)
    }

    /// Recompute the calendar fetch whenever the window or the user's calendar
    /// preferences change. `EKAuthorizationStatus` isn't `Hashable`, so its raw
    /// value stands in for it.
    private var eventReloadKey: String {
        let window = eventWindow
        return [
            window.map { "\($0.start.timeIntervalSince1970)-\($0.end.timeIntervalSince1970)" } ?? "none",
            "\(calendarStore.showEvents)",
            "\(calendarStore.authorizationStatus.rawValue)",
            calendarStore.selectedCalendarIDs.sorted().joined(separator: ",")
        ].joined(separator: "|")
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.spacing4) {
                    windowControls(
                        expand: ("Earlier weeks", "chevron.up", { behindOverride = weeksBehind + 4 }),
                        collapse: weeksBehind > defaultWeeksBehind
                            ? ("Hide earlier weeks", { collapseEarlier(proxy) })
                            : nil
                    )
                    .id(topAnchorID)

                    ForEach(weeks) { week in
                        WeekCardView(
                            week: week,
                            plans: PlanActions.plans(in: week, from: allPlans),
                            events: calendarStore.events.filter { week.contains($0.start) },
                            allPlans: allPlans,
                            onAdd: { editorState = .create(week) },
                            onEdit: { editorState = .edit($0, week) }
                        )
                        .id(week.id)
                    }

                    windowControls(
                        expand: ("More weeks", "chevron.down", { aheadOverride = weeksAhead + 4 }),
                        collapse: weeksAhead > storedWeeksAhead
                            ? ("Show fewer", { aheadOverride = nil })
                            : nil
                    )
                }
                .padding(Theme.spacing4)
                // Extra breathing room between the nav bar title and content.
                .padding(.top, 5)
            }
            .background(Theme.backgroundWash)
            // Hard scroll edge under the nav bar: scrolled content is cut off
            // with a dividing line instead of colliding with the brand header.
            .hardTopScrollEdge()
            .toolbar {
                // Brand header pinned to the empty top-left of the nav bar,
                // without the shared glass capsule around it.
                ToolbarItem(placement: .navigation) {
                    header(proxy)
                }
                .plainToolbarBackground()

                ToolbarItem(placement: .primaryAction) {
                    if !isDefaultWindow {
                        Button {
                            resetView(proxy)
                        } label: {
                            Label("Today", systemImage: "arrow.uturn.backward.circle")
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .sheet(item: $editorState) { state in
            PlanEditorView(state: state)
        }
        .task(id: eventReloadKey) {
            if let eventWindow { calendarStore.reload(window: eventWindow) }
        }
    }

    // MARK: - Header

    private func header(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: Theme.spacing2) {
            // Tapping the logo jumps back to the top of the stream.
            Button {
                withAnimation(.snappy) { proxy.scrollTo(topAnchorID, anchor: .top) }
            } label: {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .shadow(color: PlanColor.pink.color.opacity(0.35), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scroll to top")

            VStack(alignment: .leading, spacing: 0) {
                Text("WeekScape")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [PlanColor.blue.color, PlanColor.purple.color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text("Your Weeks at a Glance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Toolbar items aggressively compress text; keep ours intact.
            .fixedSize()
        }
    }

    // MARK: - Window controls

    /// A row with an expand button and, when the window is wider than the
    /// default, a collapse button to get back to the standard view.
    private func windowControls(
        expand: (label: String, icon: String, action: () -> Void),
        collapse: (label: String, action: () -> Void)?
    ) -> some View {
        HStack(spacing: Theme.spacing4) {
            Button(action: expand.action) {
                Label(expand.label, systemImage: expand.icon)
            }
            if let collapse {
                Button(action: collapse.action) {
                    Label(collapse.label, systemImage: "arrow.down.right.and.arrow.up.left")
                }
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.spacing1)
    }

    /// Collapse the earlier-weeks expansion and land at the top of the stream.
    /// The scroll happens on the next runloop tick, after the removed cards
    /// have left the layout — otherwise the scroll target position is stale.
    private func collapseEarlier(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy) { behindOverride = nil }
        Task { @MainActor in
            withAnimation(.snappy) { proxy.scrollTo(topAnchorID, anchor: .top) }
        }
    }

    /// Restore the default window and jump back to the top of the stream.
    private func resetView(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy) {
            aheadOverride = nil
            behindOverride = nil
        }
        Task { @MainActor in
            withAnimation(.snappy) { proxy.scrollTo(topAnchorID, anchor: .top) }
        }
    }
}
