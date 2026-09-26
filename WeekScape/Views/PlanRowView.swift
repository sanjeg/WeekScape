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

    /// The week this row is being shown in, so a multi-day plan can describe
    /// whether it starts, continues, or ends here. `nil` (e.g. in the Wishlist)
    /// shows the full span.
    var containingWeek: Week? = nil

    let onToggleDone: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void

    /// Horizontal offset of the row content while swiping left to delete.
    @State private var swipeOffset: CGFloat = 0

    /// Whether the delete button is parked open after a partial swipe.
    @State private var isSwipeRevealed = false

    /// Axis decided on the drag's first movement: true = the row swipes,
    /// false = the drag is vertical and belongs to the surrounding scroll.
    @State private var swipeIsHorizontal: Bool?

    /// True while a swipe is in flight and briefly after it ends. The swipe
    /// runs as a simultaneous gesture, so without this the row's buttons
    /// would also fire when the finger lifts at the end of a swipe.
    @State private var suppressTaps = false

    /// Width of the parked delete button.
    private let revealWidth: CGFloat = 72

    /// Swiping past this point deletes without needing a tap.
    private let fullSwipeDistance: CGFloat = 180

    /// Minimum drag before the swipe gesture activates, so taps and vertical
    /// scrolling win on small movements.
    private let swipeActivationDistance: CGFloat = 25

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteBackdrop
            rowContent
                .offset(x: swipeOffset)
        }
        .simultaneousGesture(swipeToDeleteGesture)
        .contentShape(RoundedRectangle(cornerRadius: Theme.rowRadius))
        .contentShape(.dragPreview, RoundedRectangle(cornerRadius: Theme.rowRadius))
    }

    // MARK: - Row content

    private var rowContent: some View {
        HStack(spacing: Theme.spacing3) {
            // Color spine
            RoundedRectangle(cornerRadius: 3)
                .fill(plan.color.gradient)
                .frame(width: 4)
                .frame(maxHeight: .infinity)
                .opacity(plan.isDone ? 0.35 : 1)

            Button(action: { handleRowTap(onToggleDone) }) {
                Image(systemName: plan.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(plan.isDone ? plan.color.color : Color.secondary)
            }
            .buttonStyle(.plain)

            // The rest of the bar is one big button that opens the editor.
            // Drag still works: the long-press lift takes priority over the
            // button's tap, which only fires on a quick touch.
            Button(action: { handleRowTap(onOpen) }) {
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
                        // Day/date badge: dark-on-tint rather than color-on-tint,
                        // which was too low contrast to read at caption size.
                        // `.primary` keeps it legible in light and dark mode.
                        Text(dayBadgeText(start: date))
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, Theme.spacing2)
                            .padding(.vertical, Theme.spacing1)
                            .background(
                                plan.color.color.opacity(plan.isDone ? 0.12 : 0.30),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .stroke(plan.color.color.opacity(plan.isDone ? 0.15 : 0.45), lineWidth: 1)
                            )
                            .foregroundStyle(plan.isDone ? Color.secondary : Color.primary)
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
    }

    /// The day badge text: a single day, the full span, or — when shown inside a
    /// specific week — how the span relates to that week (starts, continues, or
    /// ends here).
    private func dayBadgeText(start: Date) -> String {
        PlannerFormat.spanBadge(
            start: start,
            lastDay: (plan.isMultiDay ? plan.endDate : nil) ?? start,
            in: containingWeek
        )
    }

    /// Routes taps on the row's buttons: ignored at the end of a swipe, and
    /// while the delete button is parked open a tap closes the swipe instead
    /// of performing the button's normal action.
    private func handleRowTap(_ action: () -> Void) {
        guard !suppressTaps else { return }
        if isSwipeRevealed {
            withAnimation(.snappy) {
                swipeOffset = 0
                isSwipeRevealed = false
            }
        } else {
            action()
        }
    }

    // MARK: - Swipe to delete

    /// Red delete area revealed behind the row. Its width follows the swipe
    /// offset, so it grows, shrinks, and settles in lockstep with the row
    /// content instead of popping in and out of the view hierarchy.
    private var deleteBackdrop: some View {
        Button {
            withAnimation(.snappy) { onDelete() }
        } label: {
            RoundedRectangle(cornerRadius: Theme.rowRadius)
                .fill(.red)
                .overlay(alignment: .trailing) {
                    Image(systemName: "trash.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: revealWidth)
                }
        }
        .buttonStyle(.plain)
        .frame(width: max(0, -swipeOffset), alignment: .trailing)
        .clipped()
        .allowsHitTesting(isSwipeRevealed)
        .accessibilityHidden(!isSwipeRevealed)
        .accessibilityLabel("Delete \(plan.title.isEmpty ? "plan" : plan.title)")
    }

    /// Left swipe reveals the delete button; swiping far enough deletes
    /// outright. The axis is locked on the drag's first movement so a
    /// vertical drag scrolls the stream without wiggling the row, and the
    /// activation distance keeps taps and the long-press drag-to-move
    /// interaction working as before.
    private var swipeToDeleteGesture: some Gesture {
        DragGesture(minimumDistance: swipeActivationDistance)
            .onChanged { value in
                if swipeIsHorizontal == nil {
                    swipeIsHorizontal = abs(value.translation.width) > abs(value.translation.height)
                }
                guard swipeIsHorizontal == true else { return }
                suppressTaps = true
                let base: CGFloat = isSwipeRevealed ? -revealWidth : 0
                swipeOffset = min(0, base + compensated(value.translation.width))
            }
            .onEnded { value in
                defer {
                    swipeIsHorizontal = nil
                    // Lift the tap suppression on the next runloop turns, after
                    // any button action from the same touch has been delivered.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        suppressTaps = false
                    }
                }
                guard swipeIsHorizontal == true else { return }
                let base: CGFloat = isSwipeRevealed ? -revealWidth : 0
                let landing = base + value.predictedEndTranslation.width
                withAnimation(.snappy) {
                    if landing < -fullSwipeDistance {
                        onDelete()
                        swipeOffset = 0
                        isSwipeRevealed = false
                    } else if landing < -revealWidth / 2 {
                        swipeOffset = -revealWidth
                        isSwipeRevealed = true
                    } else {
                        swipeOffset = 0
                        isSwipeRevealed = false
                    }
                }
            }
    }

    /// Shifts the translation back by the activation distance so the row
    /// starts moving from under the finger instead of jumping by the drag
    /// gesture's built-in dead zone.
    private func compensated(_ translation: CGFloat) -> CGFloat {
        translation > 0
            ? max(0, translation - swipeActivationDistance)
            : min(0, translation + swipeActivationDistance)
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    PlanRowView(
        plan: Plan(title: "Morning hike", notes: "Bring water", weekStart: .now),
        onToggleDone: {},
        onOpen: {},
        onDelete: {}
    )
    .padding()
}
