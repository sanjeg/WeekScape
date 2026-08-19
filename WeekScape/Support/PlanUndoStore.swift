//
//  PlanUndoStore.swift
//  WeekScape
//
//  A small, targeted undo facility that restores *deleted* plans — and only
//  deletions. It deliberately does not use SwiftData's global undo manager, so
//  edits, moves, reorders, and completion toggles are never undoable; only a
//  removed plan can be brought back.
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class PlanUndoStore {
    /// Shared instance. Deletions funnel through `PlanActions.delete`, and the
    /// toolbar Undo button reads/acts on this one store.
    static let shared = PlanUndoStore()
    private init() {}

    /// Snapshots of recently deleted plans, most recent last.
    private var snapshots: [Snapshot] = []

    /// Cap the history so a long session can't grow it without bound.
    private let maxDepth = 50

    /// True when there is at least one deleted plan available to restore.
    var canUndo: Bool { !snapshots.isEmpty }

    /// Remember a plan's contents just before it is deleted.
    func recordDeletion(of plan: Plan) {
        snapshots.append(Snapshot(plan))
        if snapshots.count > maxDepth {
            snapshots.removeFirst(snapshots.count - maxDepth)
        }
    }

    /// Re-insert the most recently deleted plan, restoring its identity and
    /// contents so it reappears exactly where it was.
    func undoLastDeletion(in context: ModelContext) {
        guard let snapshot = snapshots.popLast() else { return }
        context.insert(snapshot.makePlan())
    }

    /// Forget all remembered deletions (e.g. after a full app reset).
    func clear() {
        snapshots.removeAll()
    }

    /// Immutable copy of a plan's stored fields, enough to recreate it.
    private struct Snapshot {
        let id: UUID
        let title: String
        let notes: String
        let weekStart: Date
        let specificDate: Date?
        let endDate: Date?
        let isWishlist: Bool
        let sortOrder: Double
        let isDone: Bool
        let colorRaw: String
        let createdAt: Date

        init(_ plan: Plan) {
            id = plan.id
            title = plan.title
            notes = plan.notes
            weekStart = plan.weekStart
            specificDate = plan.specificDate
            endDate = plan.endDate
            isWishlist = plan.isWishlist
            sortOrder = plan.sortOrder
            isDone = plan.isDone
            colorRaw = plan.colorRaw
            createdAt = plan.createdAt
        }

        func makePlan() -> Plan {
            let plan = Plan(
                title: title,
                notes: notes,
                weekStart: weekStart,
                specificDate: specificDate,
                endDate: endDate,
                isWishlist: isWishlist,
                sortOrder: sortOrder,
                color: PlanColor(rawValue: colorRaw) ?? .blue
            )
            // Preserve the original identity and metadata so the restored plan is
            // indistinguishable from the deleted one.
            plan.id = id
            plan.isDone = isDone
            plan.createdAt = createdAt
            return plan
        }
    }
}
