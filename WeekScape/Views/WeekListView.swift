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

    /// Whether the Wishlist card is showing above the current week. Owned by
    /// the root view so the toolbar's star button can toggle it.
    @Binding var showingWishlist: Bool

    @Query(sort: \Plan.sortOrder) private var allPlans: [Plan]

    /// Check-off records for imported calendar events, fetched once for the
    /// whole stream rather than per card.
    @Query private var eventCompletions: [EventCompletion]

    // Re-read when settings change so the whole stream recomputes.
    @AppStorage(WeekConfig.firstWeekdayKey) private var firstWeekday: Int = 2
    @AppStorage(WeekConfig.weeksAheadKey) private var storedWeeksAhead: Int = WeekConfig.defaultWeeksAhead

    private let defaultWeeksBehind = 1

    /// Temporary expansions beyond the configured default window. `nil` means
    /// "use the default", which keeps the Settings value authoritative.
    @State private var aheadOverride: Int?
    @State private var behindOverride: Int?
    @State private var editorState: PlanEditorState?

    /// Guards the one-time launch scroll that parks the current week on top.
    @State private var didInitialScroll = false

    /// Anchor id for the very top of the stream.
    private let topAnchorID = "stream-top"

    /// Upper bound on the auto-extension below, so one far-out plan can't make
    /// the stream unboundedly long.
    private let maxWeeksAhead = 104

    /// The window always stretches far enough forward to reach the furthest
    /// scheduled plan, so a plan dated months out is still reachable.
    private var weeksAhead: Int {
        max(aheadOverride ?? storedWeeksAhead, weeksToFurthestPlan)
    }

    private var weeksBehind: Int { behindOverride ?? defaultWeeksBehind }

    /// Weeks from the current week to the furthest future plan (0 when none).
    private var weeksToFurthestPlan: Int {
        let cal = WeekConfig.calendar
        let thisWeek = WeekConfig.startOfWeek(for: Date())
        let furthest = allPlans
            .filter { !$0.isWishlist }
            .map { plan -> Int in
                let anchor = plan.endDate ?? plan.specificDate ?? plan.weekStart
                let week = WeekConfig.startOfWeek(for: anchor)
                return cal.dateComponents([.weekOfYear], from: thisWeek, to: week).weekOfYear ?? 0
            }
            .max() ?? 0
        return min(max(furthest, 0), maxWeeksAhead)
    }

    private var weeks: [Week] {
        _ = firstWeekday // establish dependency for recomputation
        return WeekConfig.window(past: weeksBehind, future: weeksAhead)
    }

    /// The current week always falls inside the window, so this is the scroll
    /// target that puts "this week" at the top on launch.
    private var currentWeekID: Week.ID? {
        weeks.first(where: \.isCurrent)?.id
    }

    /// Dateless wishlist ideas, already in manual order via the query's sort.
    private var wishlistPlans: [Plan] {
        allPlans.filter(\.isWishlist)
    }

    /// Plans and events bucketed by week start, and completions as a set, so
    /// each card is a hash lookup instead of a fresh scan of every collection.
    private var plansByWeekStart: [Date: [Plan]] {
        PlanActions.plansByWeekStart(from: allPlans)
    }

    /// Events bucketed by week start. A multi-day event lands in every week it
    /// runs across, so it reads the same as a multi-day plan rather than
    /// showing up only in the week it began.
    private var eventsByWeekStart: [Date: [CalendarEvent]] {
        var buckets: [Date: [CalendarEvent]] = [:]
        for event in calendarStore.events {
            for weekStart in event.occupiedWeekStarts {
                buckets[weekStart, default: []].append(event)
            }
        }
        return buckets
    }

    private var completedEventIDs: Set<String> {
        Set(eventCompletions.map(\.eventID))
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
        // The stream's height sets the pinned Wishlist card's budget, so it can
        // never grow past its share of the screen.
        GeometryReader { geo in
            stream(containerHeight: geo.size.height)
        }
    }

    private func stream(containerHeight: CGFloat) -> some View {
        // Built once per render and captured by the cards below. Reading the
        // computed properties inside the ForEach would rebuild them per week,
        // which is exactly what this replaces.
        let plansByWeek = plansByWeekStart
        let eventsByWeek = eventsByWeekStart
        let doneEventIDs = completedEventIDs

        return ScrollViewReader { proxy in
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
                            plans: plansByWeek[week.start] ?? [],
                            events: eventsByWeek[week.start] ?? [],
                            completedEventIDs: doneEventIDs,
                            onAdd: { editorState = .create(week) },
                            onEdit: { editorState = .edit($0, week) }
                        )
                        .id(week.id)
                    }

                    windowControls(
                        expand: ("More weeks", "chevron.down", { aheadOverride = weeksAhead + 4 }),
                        // Keyed off the manual override, not `weeksAhead`, which
                        // also grows on its own to reach far-future plans.
                        collapse: aheadOverride != nil
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
            // The Wishlist is pinned above the stream rather than living in it,
            // so it stays put while the weeks scroll underneath. Plans can
            // still be dragged between it and any week card.
            .safeAreaInset(edge: .top, spacing: Theme.spacing4) {
                if showingWishlist {
                    WishlistCardView(
                        plans: wishlistPlans,
                        maxRowsHeight: Theme.wishlistRowsHeight(in: containerHeight),
                        onAdd: { editorState = .createWishlist },
                        onEdit: { editorState = .editWishlist($0) },
                        onClose: {
                            withAnimation(.snappy) { showingWishlist = false }
                        }
                    )
                    .padding(.horizontal, Theme.spacing4)
                    .padding(.top, Theme.spacing2)
                }
            }
            .toolbar {
                // Brand header pinned to the empty top-left of the nav bar,
                // without the shared glass capsule around it.
                ToolbarItem(placement: .navigation) {
                    header(proxy)
                }
                .plainToolbarBackground()
            }
            // Launch with the current week on top. Earlier weeks stay just
            // above, reachable by scrolling up.
            .onAppear {
                guard !didInitialScroll, let currentWeekID else { return }
                didInitialScroll = true
                // Next runloop tick: the lazy stack has to lay the card out
                // before it can be scrolled to.
                Task { @MainActor in
                    proxy.scrollTo(currentWeekID, anchor: .top)
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
}

/// Previews the week stream on its own. `ContentView`'s preview runs the real
/// app root, which starts the long-lived CloudKit and EventKit observers — those
/// make the canvas unstable, so prefer this one while working on the UI.
#Preview("Week stream") {
    @Previewable @State var showingWishlist = false

    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Plan.self, EventCompletion.self,
        configurations: config
    )
    SampleData.insertSamples(in: container.mainContext)

    return NavigationStack {
        WeekListView(showingWishlist: $showingWishlist)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.snappy) { showingWishlist.toggle() }
                    } label: {
                        Image(systemName: showingWishlist ? "star.fill" : "star")
                    }
                }
            }
    }
    .modelContainer(container)
    .environment(CalendarStore())
}
