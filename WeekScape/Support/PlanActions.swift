//
//  PlanActions.swift
//  Weekend Planner
//
//  Centralized mutations on the plan graph: resolving drag payloads, moving
//  plans between weeks, and reordering within a week using fractional sort
//  keys so we never have to renumber an entire list.
//

import Foundation
import SwiftData

enum PlanActions {
    /// Resolve a live model from a drag payload id.
    static func plan(id: UUID, in context: ModelContext) -> Plan? {
        var descriptor = FetchDescriptor<Plan>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// All plans belonging to a week, ordered. Plans pinned to a specific date
    /// come first in chronological order; undated ("floating") plans follow in
    /// their manual, drag-and-drop order (`sortOrder`). A multi-day plan appears
    /// in every week its span touches, so it shows up as it runs across weeks.
    static func plans(in week: Week, from all: [Plan]) -> [Plan] {
        all.filter { !$0.isWishlist && occupies(week, $0) }
            .sorted { lhs, rhs in
                switch (lhs.specificDate, rhs.specificDate) {
                case let (l?, r?):
                    return l == r ? manualOrder(lhs, rhs) : l < r
                case (.some, nil):
                    return true            // dated before undated
                case (nil, .some):
                    return false           // undated after dated
                case (nil, nil):
                    return manualOrder(lhs, rhs)
                }
            }
    }

    /// Whether `plan` should be shown in `week`. Dated plans are placed by their
    /// day span (so a multi-day plan spans weeks); undated plans belong to their
    /// stored week.
    static func occupies(_ week: Week, _ plan: Plan) -> Bool {
        guard let start = plan.specificDate else {
            return week.contains(plan.weekStart)
        }
        let cal = WeekConfig.calendar
        let spanStart = cal.startOfDay(for: start)
        let spanEnd = plan.endDate.map { cal.startOfDay(for: $0) } ?? spanStart
        // Overlap test between [spanStart, spanEnd] and [week.start, week.end].
        return spanStart <= week.end && spanEnd >= week.start
    }

    /// Tiebreaker for plans that share an ordering key: the user's manual
    /// `sortOrder`, then creation time for stability.
    private static func manualOrder(_ lhs: Plan, _ rhs: Plan) -> Bool {
        lhs.sortOrder == rhs.sortOrder
            ? lhs.createdAt < rhs.createdAt
            : lhs.sortOrder < rhs.sortOrder
    }

    /// Sort key that places a new item after everything currently in the week.
    static func appendOrder(in weekPlans: [Plan]) -> Double {
        (weekPlans.map(\.sortOrder).max() ?? 0) + 1
    }

    /// Move a plan to the end of `week`. If it carried a specific date that no
    /// longer falls inside the target week, that date is cleared.
    static func move(_ plan: Plan, to week: Week, weekPlans: [Plan]) {
        plan.sortOrder = appendOrder(in: weekPlans.filter { $0.id != plan.id })
        reassignWeek(plan, to: week)
    }

    /// Insert `plan` immediately before `target` within `week`, giving it a
    /// fractional sort key between `target` and its undated predecessor.
    ///
    /// Manual ordering only governs undated plans — dated plans are always laid
    /// out chronologically — so the fractional key is computed against the
    /// week's undated block. Reordering a dated plan is a no-op beyond any week
    /// reassignment.
    static func insert(_ plan: Plan, before target: Plan, in week: Week, orderedWeekPlans: [Plan]) {
        guard target.id != plan.id else { return }
        reassignWeek(plan, to: week)
        guard plan.specificDate == nil else { return }

        let undated = orderedWeekPlans.filter { $0.specificDate == nil && $0.id != plan.id }
        // Dropped onto a dated row: park at the front of the undated block,
        // since undated plans always sit below the dated ones.
        guard let targetIndex = undated.firstIndex(where: { $0.id == target.id }) else {
            plan.sortOrder = (undated.map(\.sortOrder).min() ?? 0) - 1
            return
        }
        let upper = target.sortOrder
        let lower = targetIndex > 0 ? undated[targetIndex - 1].sortOrder : upper - 2
        plan.sortOrder = (upper + lower) / 2
    }

    /// Point a plan at a new week. A pinned date travels with the plan: it is
    /// remapped to the same weekday in the destination week, and a multi-day
    /// span shifts by the same amount so its length is preserved.
    private static func reassignWeek(_ plan: Plan, to week: Week) {
        let calendar = WeekConfig.calendar
        if let date = plan.specificDate, !week.contains(date) {
            // Land the start on the same weekday in the destination week, then
            // shift the end (if any) by the identical delta so a multi-day span
            // keeps its length.
            let newStart = calendar.date(byAdding: .day, value: weekdayOffset(of: date), to: week.start)
                ?? week.start
            let shift = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: date),
                to: newStart
            ).day ?? 0
            plan.specificDate = newStart
            if let end = plan.endDate {
                plan.endDate = calendar.date(byAdding: .day, value: shift, to: calendar.startOfDay(for: end))
            }
        }
        plan.weekStart = week.start
    }

    /// Number of days from the start of `date`'s week to `date` itself.
    private static func weekdayOffset(of date: Date) -> Int {
        let calendar = WeekConfig.calendar
        return calendar.dateComponents(
            [.day],
            from: WeekConfig.startOfWeek(for: date),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
    }

    // MARK: - Wishlist

    /// Next sort key that places a new item after everything in the wishlist.
    static func wishlistAppendOrder(in wishlistPlans: [Plan]) -> Double {
        (wishlistPlans.map(\.sortOrder).max() ?? 0) + 1
    }

    /// Promote a wishlist plan into `week`, optionally pinning it to a day, and
    /// append it to the end of that week.
    static func promote(_ plan: Plan, to week: Week, on day: Date?, weekPlans: [Plan]) {
        plan.isWishlist = false
        plan.weekStart = week.start
        plan.specificDate = day.map { WeekConfig.calendar.startOfDay(for: $0) }
        plan.endDate = nil
        plan.sortOrder = appendOrder(in: weekPlans.filter { !$0.isWishlist && $0.id != plan.id })
    }

    static func delete(_ plan: Plan, in context: ModelContext) {
        context.delete(plan)
    }
}
