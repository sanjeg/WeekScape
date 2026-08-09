//
//  Plan.swift
//  Weekend Planner
//
//  The core model. A `Plan` belongs to a single week (identified by the
//  normalized start-of-week date) and may optionally be pinned to a specific
//  day within that week.
//
//  CloudKit compatibility notes: every stored property has a default value or
//  is optional, and there are no unique constraints or non-optional
//  relationships. This keeps the schema syncable via SwiftData + CloudKit.
//

import Foundation
import SwiftData

@Model
final class Plan {
    /// Stable identity used for drag-and-drop payloads.
    var id: UUID = UUID()

    var title: String = ""
    var notes: String = ""

    /// Normalized start-of-week date that this plan lives in.
    var weekStart: Date = Date()

    /// Optional exact day within the week. When `nil`, the plan floats in the
    /// week without a committed date.
    var specificDate: Date?

    /// Fractional ordering key so plans can be inserted between neighbors
    /// without renumbering the whole list.
    var sortOrder: Double = 0

    var isDone: Bool = false

    /// Name of a `PlanColor` case, stored as a string for CloudKit friendliness.
    var colorRaw: String = PlanColor.blue.rawValue

    var createdAt: Date = Date()

    init(
        title: String = "",
        notes: String = "",
        weekStart: Date,
        specificDate: Date? = nil,
        sortOrder: Double = 0,
        color: PlanColor = .blue
    ) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.weekStart = weekStart
        self.specificDate = specificDate
        self.sortOrder = sortOrder
        self.isDone = false
        self.colorRaw = color.rawValue
        self.createdAt = Date()
    }

    var color: PlanColor {
        get { PlanColor(rawValue: colorRaw) ?? .blue }
        set { colorRaw = newValue.rawValue }
    }
}
