//
//  WishlistCardView.swift
//  WeekScape
//
//  The dateless "someday" list rendered as a card in the week stream, sitting
//  directly above the current week. Ideas can be dragged out of it onto any
//  week card to schedule them, and week plans can be dragged back in to
//  un-schedule them.
//

import SwiftUI
import SwiftData

/// Reports the measured height of the wishlist's row stack.
private struct RowsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct WishlistCardView: View {
    @Environment(\.modelContext) private var context

    /// Wishlist plans in the user's manual order.
    let plans: [Plan]

    /// Tallest the row area may grow before scrolling inside the card. Supplied
    /// by the stream so the cap tracks the real screen height.
    let maxRowsHeight: CGFloat

    let onAdd: () -> Void
    let onEdit: (Plan) -> Void
    let onClose: () -> Void

    @State private var isTargeted = false

    /// Which row a drag is currently hovering over (for the insertion line).
    @State private var rowTargetID: UUID?

    /// Natural height of the row stack, measured so the card can size to its
    /// rows until it hits `maxRowsHeight`.
    @State private var rowsHeight: CGFloat = 0

    /// The wishlist keeps the orange star hue so it reads as its own thing
    /// against the rotating week accents.
    private let accentColor: PlanColor = .orange

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
        // Card-level drop: pull the plan off its week and onto the wishlist.
        .dropDestination(for: PlanTransfer.self) { items, _ in
            guard let payload = items.first,
                  let plan = PlanActions.plan(id: payload.id, in: context) else { return false }
            withAnimation(.snappy) {
                PlanActions.moveToWishlist(plan, wishlistPlans: plans)
            }
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spacing1) {
            // Row 1 mirrors a week card: title leads, actions trail.
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacing2) {
                Label("Wishlist", systemImage: "star.fill")
                    .font(.body.bold())
                    .foregroundStyle(accent)

                Spacer()

                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, accentColor.gradient)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add wishlist item")

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close wishlist")
            }

            // Surfacing the count matters once the rows scroll inside the card,
            // where the list length is no longer visible at a glance.
            Text(plans.isEmpty
                 ? "Someday — drag an idea into a week"
                 : "^[\(plans.count) idea](inflect: true) — drag one into a week")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if plans.isEmpty {
            // Keep a slim open area so an empty wishlist still reads as a
            // drop target for plans dragged out of a week.
            Text("Nothing here yet — drag a plan in, or tap +")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.spacing2)
        } else {
            // The card is pinned above the stream, so the rows get an explicit
            // height: their natural height while that fits the budget, capped
            // at `maxRowsHeight` beyond it. An exact height is what keeps the
            // rows inside the card — a `maxHeight` alone lets the stack draw
            // past its frame and slide up behind the nav bar.
            ScrollView {
                rowsStack
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: RowsHeightKey.self,
                                value: geo.size.height
                            )
                        }
                    )
            }
            .frame(height: min(max(rowsHeight, 1), maxRowsHeight))
            // No rubber-banding when the rows already fit.
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.visible)
            .onPreferenceChange(RowsHeightKey.self) { height in
                rowsHeight = height
            }
        }
    }

    private var rowsStack: some View {
        VStack(spacing: Theme.spacing2) {
            ForEach(plans) { plan in
                planRow(plan)
            }
        }
    }

    /// A wishlist row with the drag source, row-level reorder drop, and
    /// insertion indicator attached — the same interaction model as a week card.
    private func planRow(_ plan: Plan) -> some View {
        PlanRowView(
            plan: plan,
            onToggleDone: { plan.isDone.toggle() },
            onOpen: { onEdit(plan) },
            onDelete: { PlanActions.delete(plan, in: context) }
        )
        .draggable(PlanTransfer(id: plan.id))
        // Row-level drop: insert the dragged plan before this row.
        .dropDestination(for: PlanTransfer.self) { items, _ in
            guard let payload = items.first,
                  payload.id != plan.id,
                  let dragged = PlanActions.plan(id: payload.id, in: context)
            else { return false }
            withAnimation(.snappy) {
                PlanActions.insertInWishlist(dragged, before: plan, orderedWishlistPlans: plans)
            }
            return true
        } isTargeted: { targeted in
            rowTargetID = targeted ? plan.id : (rowTargetID == plan.id ? nil : rowTargetID)
        }
        .overlay(alignment: .top) {
            if rowTargetID == plan.id {
                Capsule()
                    .fill(accent)
                    .frame(height: 3)
                    .offset(y: -(Theme.spacing2 / 2 + 1.5))
            }
        }
    }

    // MARK: - Styling

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Theme.cardRadius)
            .fill(.plannerSurface)
            .overlay(
                LinearGradient(
                    colors: [accent.opacity(0.14), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            )
            .shadow(color: accent.opacity(0.22), radius: 12, y: 6)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: Theme.cardRadius)
            .stroke(borderStyle, lineWidth: isTargeted ? 2.5 : 1.5)
    }

    private var borderStyle: AnyShapeStyle {
        isTargeted
            ? AnyShapeStyle(accent)
            : AnyShapeStyle(accent.opacity(0.35))
    }
}
