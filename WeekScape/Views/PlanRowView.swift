//
//  PlanRowView.swift
//  Weekend Planner
//
//  Presentation for a single plan inside a week card. The editing tap is a
//  real Button inside the row (not a whole-row tap gesture) so it never
//  competes with the long-press drag interaction attached by the parent.
//

import SwiftUI

struct PlanRowView: View {
    let plan: Plan
    let onToggleDone: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: Theme.spacing3) {
            // Color spine
            RoundedRectangle(cornerRadius: 3)
                .fill(plan.color.gradient)
                .frame(width: 4)
                .frame(maxHeight: .infinity)
                .opacity(plan.isDone ? 0.35 : 1)

            Button(action: onToggleDone) {
                Image(systemName: plan.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(plan.isDone ? plan.color.color : Color.secondary)
            }
            .buttonStyle(.plain)

            // The rest of the bar is one big button that opens the editor.
            // Drag still works: the long-press lift takes priority over the
            // button's tap, which only fires on a quick touch.
            Button(action: onOpen) {
                HStack(spacing: Theme.spacing2) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.title.isEmpty ? "Untitled plan" : plan.title)
                            .font(.body.weight(.medium))
                            .strikethrough(plan.isDone, color: .secondary)
                            .foregroundStyle(plan.isDone ? Color.secondary : Color.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if !plan.notes.isEmpty {
                            Text(plan.notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: Theme.spacing2)

                    if let date = plan.specificDate {
                        Text(PlannerFormat.dayLabel(date))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, Theme.spacing2)
                            .padding(.vertical, Theme.spacing1)
                            .background(plan.color.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(plan.color.color)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Theme.spacing2)
        .padding(.horizontal, Theme.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius)
                .fill(.plannerSurface)
                .overlay(
                    // Soft wash of the plan's color across the row.
                    LinearGradient(
                        colors: [
                            plan.color.color.opacity(plan.isDone ? 0.04 : 0.12),
                            plan.color.color.opacity(plan.isDone ? 0.02 : 0.04)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.rowRadius))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rowRadius)
                .stroke(plan.color.color.opacity(plan.isDone ? 0.08 : 0.20), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.rowRadius))
        .contentShape(.dragPreview, RoundedRectangle(cornerRadius: Theme.rowRadius))
    }
}
