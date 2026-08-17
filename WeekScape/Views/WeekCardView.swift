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
    let allPlans: [Plan]
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
                ForEach(orderedItems) { item in
                    switch item {
                    case .plan(let plan):
                        planRow(plan)
                    case .event(let event):
                        // Read-only: no drag/drop, so a drag over it falls
                        // through to the card-level append drop.
                        CalendarEventRow(event: event)
                    }
                }
            }
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

    /// The card's rows in display order: time-anchored items (dated plans and
    /// calendar events) interleaved chronologically, then undated plans in the
    /// user's manual order.
    private var orderedItems: [WeekItem] {
        let datedPlans = plans.filter { $0.specificDate != nil }
        let undatedPlans = plans.filter { $0.specificDate == nil }
        var timed: [WeekItem] = datedPlans.map { WeekItem.plan($0) } + events.map { WeekItem.event($0) }
        timed.sort { $0.sortDate < $1.sortDate }
        return timed + undatedPlans.map { WeekItem.plan($0) }
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

/// A read-only row for an event mirrored from the iPhone Calendar. It matches a
/// plan row exactly — color spine, title, and a day badge in the same place —
/// with one difference: a calendar icon stands in for the completion toggle. No
/// time is shown, and it carries no toggle/drag/delete affordances.
private struct CalendarEventRow: View {
    @Environment(CalendarStore.self) private var calendarStore

    let event: CalendarEvent

    /// The live event to preview, set on tap. `EKEvent` isn't `Identifiable`,
    /// so it's wrapped for `.sheet(item:)`.
    @State private var previewItem: PreviewItem?

    private struct PreviewItem: Identifiable {
        let id: String
        let event: EKEvent
    }

    var body: some View {
        Button(action: openPreview) {
            rowContent
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows event details")
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

            // Calendar icon in place of the plan's completion circle.
            Image(systemName: "calendar")
                .font(.title3)
                .foregroundStyle(event.color)

            HStack(spacing: Theme.spacing2) {
                Text(event.title.isEmpty ? "(No title)" : event.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: Theme.spacing2)

                Text(PlannerFormat.dayLabel(event.start))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, Theme.spacing2)
                    .padding(.vertical, Theme.spacing1)
                    .background(event.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(event.color)
            }
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
                            event.color.opacity(0.12),
                            event.color.opacity(0.04)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.rowRadius))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rowRadius)
                .stroke(event.color.opacity(0.20), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Calendar event: \(event.title), \(PlannerFormat.dayLabel(event.start))")
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
