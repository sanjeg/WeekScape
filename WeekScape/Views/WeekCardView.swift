//
//  WeekCardView.swift
//  Weekend Planner
//
//  A single week rendered as a card. Plans can be dragged between cards (to
//  change which week they belong to) or dropped onto a specific row (to
//  reorder). The card itself is a drop target for appending to the week.
//

import SwiftUI
import SwiftData
import EventKit

struct WeekCardView: View {
    @Environment(\.modelContext) private var context

    let week: Week
    let plans: [Plan]
    let events: [CalendarEvent]

    /// Ids of events already checked off, as a set so each row is an O(1)
    /// lookup rather than a scan of every completion record.
    let completedEventIDs: Set<String>
    let onAdd: () -> Void
    let onEdit: (Plan) -> Void

    @State private var isTargeted = false

    /// Which row a drag is currently hovering over (for the insertion line).
    @State private var rowTargetID: UUID?

    /// Each week gets its own rotating accent hue; the current week is blue.
    private var accentColor: PlanColor {
        Theme.weekAccent(for: week)
    }

    private var accent: Color {
        accentColor.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing3) {
            header
            content
        }
        .padding(Theme.spacing4)
        .background(cardBackground)
        .overlay(cardBorder)
        .animation(.snappy(duration: 0.2), value: isTargeted)
        // Card-level drop: append the plan to the end of this week.
        .dropDestination(for: PlanTransfer.self) { items, _ in
            guard let payload = items.first,
                  let plan = PlanActions.plan(id: payload.id, in: context) else { return false }
            withAnimation(.snappy) {
                PlanActions.move(plan, to: week, weekPlans: plans)
            }
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spacing1) {
            // Row 1: the week dates lead as the prominent element, with the NOW
            // badge and add button.
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacing2) {
                Text(PlannerFormat.weekRange(week))
                    .font(.body.bold())
                    .foregroundStyle(accent)

                Spacer()

                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, accentColor.gradient)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add plan to \(PlannerFormat.weekRange(week))")
            }

            // Row 2: the friendly relative label drops to its own line for
            // breathing room.
            Text(PlannerFormat.weekTitle(week))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if plans.isEmpty && events.isEmpty {
            // Keep a slim open area so empty weeks still read as drop targets.
            Text("Nothing planned")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.spacing2)
        } else {
            VStack(spacing: Theme.spacing2) {
                // Days holding more than one item are gathered into a subtle
                // group; single-item days render as plain rows.
                ForEach(dayGroups) { group in
                    if group.items.count > 1 {
                        dayGroup(group)
                    } else if let item = group.items.first {
                        row(for: item)
                    }
                }

                // Undated plans keep their manual drag order, ungrouped.
                ForEach(undatedItems) { item in
                    row(for: item)
                }
            }
        }
    }

    /// A subtle container for two or more items landing on the same day: a small
    /// day caption, tighter row spacing, and a faint backdrop.
    private func dayGroup(_ group: DayGroup) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing1) {
            Text(PlannerFormat.dayLabel(group.day))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, Theme.spacing2)

            VStack(spacing: Theme.spacing1) {
                ForEach(group.items) { item in
                    row(for: item)
                }
            }
        }
        .padding(.vertical, Theme.spacing2)
        .padding(.horizontal, Theme.spacing1)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius + 4)
                .fill(Theme.dayGroupFill)
        )
    }

    @ViewBuilder
    private func row(for item: WeekItem) -> some View {
        switch item {
        case .plan(let plan):
            planRow(plan)
        case .event(let event):
            // Not draggable: a drag over it falls through to the card-level
            // append drop. It can still be checked off.
            CalendarEventRow(
                event: event,
                isDone: completedEventIDs.contains(event.id),
                onToggleDone: {
                    EventActions.toggleDone(eventID: event.id, in: context)
                }
            )
        }
    }

    /// A plan row with the drag source, row-level reorder drop, and insertion
    /// indicator attached.
    private func planRow(_ plan: Plan) -> some View {
        PlanRowView(
            plan: plan,
            containingWeek: week,
            onToggleDone: { toggleDone(plan) },
            onOpen: { onEdit(plan) },
            onDelete: { PlanActions.delete(plan, in: context) }
        )
        // Drag source is attached directly to the row, with no competing
        // whole-row tap gesture (taps live on buttons inside the row instead).
        .draggable(PlanTransfer(id: plan.id))
        // Row-level drop: insert the dragged plan before this row.
        .dropDestination(for: PlanTransfer.self) { items, _ in
            guard let payload = items.first,
                  payload.id != plan.id,
                  let dragged = PlanActions.plan(id: payload.id, in: context)
            else { return false }
            withAnimation(.snappy) {
                PlanActions.insert(dragged, before: plan, in: week, orderedWeekPlans: plans)
            }
            return true
        } isTargeted: { targeted in
            rowTargetID = targeted ? plan.id : (rowTargetID == plan.id ? nil : rowTargetID)
        }
        // Insertion indicator: a colored line above the row a drop would land
        // in front of.
        .overlay(alignment: .top) {
            if rowTargetID == plan.id {
                Capsule()
                    .fill(accent)
                    .frame(height: 3)
                    .offset(y: -(Theme.spacing2 / 2 + 1.5))
            }
        }
        // NOTE: deliberately no .contextMenu here — on plain views (unlike List
        // rows) it captures the long-press and prevents the drag lift from ever
        // starting. Edit/delete remain available by tapping the row title.
    }

    /// Time-anchored items (dated plans and calendar events) bucketed by the day
    /// they occupy in this week, in chronological order.
    ///
    /// A multi-day plan running in from an earlier week anchors to a day outside
    /// this card, so the bucket key is clamped to the week's start — it groups
    /// under the first day it actually occupies here.
    private var dayGroups: [DayGroup] {
        let cal = WeekConfig.calendar
        let datedPlans = plans.filter { $0.specificDate != nil }
        var timed: [WeekItem] = datedPlans.map { WeekItem.plan($0) } + events.map { WeekItem.event($0) }
        timed.sort { $0.sortDate < $1.sortDate }

        let weekStart = cal.startOfDay(for: week.start)
        var order: [Date] = []
        var buckets: [Date: [WeekItem]] = [:]
        for item in timed {
            let day = max(cal.startOfDay(for: item.sortDate), weekStart)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(item)
        }
        return order.map { DayGroup(day: $0, items: buckets[$0] ?? []) }
    }

    /// Undated plans, which float in the week in the user's manual drag order.
    private var undatedItems: [WeekItem] {
        plans.filter { $0.specificDate == nil }.map { WeekItem.plan($0) }
    }

    // MARK: - Styling

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Theme.cardRadius)
            .fill(.plannerSurface)
            .overlay(
                // A whisper of the week's accent hue, fading toward the bottom.
                LinearGradient(
                    colors: [accent.opacity(week.isCurrent ? 0.16 : 0.06), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            )
            // The current week gets a stronger colored glow so it anchors the stream.
            .shadow(
                color: accent.opacity(week.isCurrent ? 0.35 : 0.12),
                radius: week.isCurrent ? 16 : 10,
                y: week.isCurrent ? 8 : 5
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: Theme.cardRadius)
            .stroke(borderStyle, lineWidth: isTargeted ? 2.5 : (week.isCurrent ? 2 : 1))
    }

    private var borderStyle: AnyShapeStyle {
        if isTargeted {
            return AnyShapeStyle(accent)
        }
        // Gradient ring for the current week; faint tint for the rest.
        return week.isCurrent
            ? AnyShapeStyle(accentColor.gradient)
            : AnyShapeStyle(accent.opacity(0.15))
    }

    private func toggleDone(_ plan: Plan) {
        plan.isDone.toggle()
    }
}

// MARK: - Week item

/// The items landing on one day of a week card.
private struct DayGroup: Identifiable {
    let day: Date
    let items: [WeekItem]

    var id: Date { day }
}

/// One entry in a week card: either a user plan or a read-only calendar event.
private enum WeekItem: Identifiable {
    case plan(Plan)
    case event(CalendarEvent)

    var id: String {
        switch self {
        case .plan(let plan): return "plan-\(plan.id.uuidString)"
        case .event(let event): return "event-\(event.id)"
        }
    }

    /// Chronological anchor for interleaving. Dated plans anchor to the start of
    /// their day so they lead that day's timed events.
    var sortDate: Date {
        switch self {
        case .plan(let plan):
            let date = plan.specificDate ?? plan.createdAt
            return WeekConfig.calendar.startOfDay(for: date)
        case .event(let event):
            return event.start
        }
    }
}

// MARK: - Calendar event row

/// A row for an event mirrored from the iPhone Calendar. It matches a plan row
/// exactly — color spine, completion toggle, title, and a day badge in the same
/// places. The badge carries a calendar glyph so the row still reads as
/// imported, and the event itself stays read-only: checking it off is recorded
/// in the app and never written back to the user's calendar.
private struct CalendarEventRow: View {
    @Environment(CalendarStore.self) private var calendarStore

    let event: CalendarEvent

    /// Whether the user has checked this occurrence off.
    let isDone: Bool
    let onToggleDone: () -> Void

    /// The live event to preview, set on tap. `EKEvent` isn't `Identifiable`,
    /// so it's wrapped for `.sheet(item:)`.
    @State private var previewItem: PreviewItem?

    private struct PreviewItem: Identifiable {
        let id: String
        let event: EKEvent
    }

    var body: some View {
        rowContent
            .sheet(item: $previewItem) { item in
                EventPreviewView(event: item.event)
            }
    }

    /// Resolve the live event and preview it in-app. Silently does nothing if
    /// the event can no longer be found (e.g. it was deleted).
    private func openPreview() {
        if let ekEvent = calendarStore.resolveEvent(event) {
            previewItem = PreviewItem(id: event.id, event: ekEvent)
        }
    }

    private var rowContent: some View {
        HStack(spacing: Theme.spacing3) {
            // Color spine, mirroring PlanRowView.
            RoundedRectangle(cornerRadius: 3)
                .fill(spineGradient)
                .frame(width: 4)
                .frame(maxHeight: .infinity)
                .opacity(isDone ? 0.35 : 1)

            // Completion toggle in the same slot as a plan's.
            Button(action: onToggleDone) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isDone ? event.color : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? "Mark as not done" : "Mark as done")

            // The rest of the row opens the event preview.
            Button(action: openPreview) {
                HStack(spacing: Theme.spacing2) {
                    Text(event.title.isEmpty ? "(No title)" : event.title)
                        .font(.body.weight(.medium))
                        .strikethrough(isDone, color: .secondary)
                        .foregroundStyle(isDone ? Color.secondary : Color.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: Theme.spacing2)

                    // Calendar glyph marks the row as imported, now that the
                    // leading slot holds the completion toggle.
                    HStack(spacing: Theme.spacing1) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text(PlannerFormat.dayLabel(event.start))
                            .font(.caption.weight(.bold))
                    }
                    .padding(.horizontal, Theme.spacing2)
                    .padding(.vertical, Theme.spacing1)
                    .background(event.color.opacity(isDone ? 0.12 : 0.30), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(event.color.opacity(isDone ? 0.15 : 0.45), lineWidth: 1)
                    )
                    .foregroundStyle(isDone ? Color.secondary : Color.primary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Keep announcing the row as imported calendar data, which the
            // visible calendar glyph conveys sighted.
            .accessibilityLabel(
                "Calendar event: \(event.title), \(PlannerFormat.dayLabel(event.start))"
                    + (isDone ? ", done" : "")
            )
            .accessibilityHint("Shows event details")
        }
        .padding(.vertical, Theme.spacing2)
        .padding(.horizontal, Theme.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius)
                .fill(.plannerSurface)
                .overlay(
                    // Soft wash of the event's color across the row.
                    LinearGradient(
                        colors: [
                            event.color.opacity(isDone ? 0.04 : 0.12),
                            event.color.opacity(isDone ? 0.02 : 0.04)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.rowRadius))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rowRadius)
                .stroke(event.color.opacity(isDone ? 0.08 : 0.20), lineWidth: 1)
        )
    }

    /// Matches `PlanColor.gradient` (lighter → base) so the spine reads the same
    /// as a plan's.
    private var spineGradient: LinearGradient {
        LinearGradient(
            colors: [event.color.opacity(0.75), event.color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
