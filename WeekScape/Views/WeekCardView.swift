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

struct WeekCardView: View {
    @Environment(\.modelContext) private var context

    let week: Week
    let plans: [Plan]
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
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.spacing2) {
                    Text(PlannerFormat.weekTitle(week))
                        .font(.headline)
                        .foregroundStyle(accent)
                    if week.isCurrent {
                        Text("NOW")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accentColor.gradient, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                Text(PlannerFormat.weekRange(week))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, accentColor.gradient)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add plan to \(PlannerFormat.weekRange(week))")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if plans.isEmpty {
            // Keep a slim open area so empty weeks still read as drop targets.
            Text("Nothing planned")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.spacing2)
        } else {
            VStack(spacing: Theme.spacing2) {
                ForEach(plans) { plan in
                    PlanRowView(
                        plan: plan,
                        onToggleDone: { toggleDone(plan) },
                        onOpen: { onEdit(plan) },
                        onDelete: { PlanActions.delete(plan, in: context) }
                    )
                    // Drag source is attached directly to the row, with no
                    // competing whole-row tap gesture (taps live on buttons
                    // inside the row instead).
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
                    // Insertion indicator: a colored line above the row a drop
                    // would land in front of.
                    .overlay(alignment: .top) {
                        if rowTargetID == plan.id {
                            Capsule()
                                .fill(accent)
                                .frame(height: 3)
                                .offset(y: -(Theme.spacing2 / 2 + 1.5))
                        }
                    }
                    // NOTE: deliberately no .contextMenu here — on plain views
                    // (unlike List rows) it captures the long-press and
                    // prevents the drag lift from ever starting. Edit/delete
                    // remain available by tapping the row title.
                }
            }
        }
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
