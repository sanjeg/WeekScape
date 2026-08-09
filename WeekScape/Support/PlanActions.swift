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

    /// All plans belonging to a week, ordered.
    static func plans(in week: Week, from all: [Plan]) -> [Plan] {
        all.filter { week.contains($0.weekStart) }
            .sorted { lhs, rhs in
                lhs.sortOrder == rhs.sortOrder
                    ? lhs.createdAt < rhs.createdAt
                    : lhs.sortOrder < rhs.sortOrder
            }
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
    /// fractional sort key between `target` and its predecessor.
    static func insert(_ plan: Plan, before target: Plan, in week: Week, orderedWeekPlans: [Plan]) {
        guard target.id != plan.id else { return }
        reassignWeek(plan, to: week)

        let others = orderedWeekPlans.filter { $0.id != plan.id }
        guard let targetIndex = others.firstIndex(where: { $0.id == target.id }) else {
            plan.sortOrder = appendOrder(in: others)
            return
        }
        let upper = target.sortOrder
        let lower = targetIndex > 0 ? others[targetIndex - 1].sortOrder : upper - 2
        plan.sortOrder = (upper + lower) / 2
    }

    /// Point a plan at a new week. A pinned date travels with the plan: it is
    /// remapped to the same weekday in the destination week.
    private static func reassignWeek(_ plan: Plan, to week: Week) {
        if let date = plan.specificDate, !week.contains(date) {
            let calendar = WeekConfig.calendar
            let oldWeekStart = WeekConfig.startOfWeek(for: date)
            let weekdayOffset = calendar.dateComponents(
                [.day],
                from: oldWeekStart,
                to: calendar.startOfDay(for: date)
            ).day ?? 0
            plan.specificDate = calendar.date(byAdding: .day, value: weekdayOffset, to: week.start)
        }
        plan.weekStart = week.start
    }

    static func delete(_ plan: Plan, in context: ModelContext) {
        context.delete(plan)
    }
}
