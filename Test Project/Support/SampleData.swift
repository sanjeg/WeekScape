//
//  SampleData.swift
//  Weekend Planner
//
//  Seeds a handful of placeholder plans on first launch so new users see how
//  the app works instead of an empty stream.
//

import Foundation
import SwiftData

enum SampleData {
    // v2: bumped so devices whose flag was consumed before seeding landed
    // still receive the samples once.
    static let seededKey = "didSeedSampleData.v2"

    /// Inserts sample plans exactly once, and only when the store is empty
    /// (so we never duplicate data that arrives via iCloud sync).
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: seededKey) else { return }

        var descriptor = FetchDescriptor<Plan>()
        descriptor.fetchLimit = 1
        let isEmpty = ((try? context.fetch(descriptor)) ?? []).isEmpty
        guard isEmpty else {
            defaults.set(true, forKey: seededKey)
            return
        }

        insertSamples(in: context)
        defaults.set(true, forKey: seededKey)
    }

    /// Unconditionally inserts the sample plans. Used by first-launch seeding
    /// and by previews that want representative content.
    @MainActor
    static func insertSamples(in context: ModelContext) {
        let calendar = WeekConfig.calendar
        let thisWeek = Week(start: WeekConfig.startOfWeek(for: Date()))
        guard let nextStart = calendar.date(byAdding: .weekOfYear, value: 1, to: thisWeek.start) else { return }
        let nextWeek = Week(start: WeekConfig.startOfWeek(for: nextStart))

        // Pin one sample to a day near the weekend so the day badge is visible.
        let weekendDay = thisWeek.days.count == 7 ? thisWeek.days[5] : nil

        let samples: [Plan] = [
            // This week
            Plan(title: "Morning hike at the trailhead",
                 notes: "Bring water and sunscreen",
                 weekStart: thisWeek.start,
                 specificDate: weekendDay,
                 sortOrder: 1,
                 color: .green),
            Plan(title: "Movie night",
                 notes: "Pick something everyone likes",
                 weekStart: thisWeek.start,
                 sortOrder: 2,
                 color: .purple),
            Plan(title: "Grocery run for the week",
                 weekStart: thisWeek.start,
                 sortOrder: 3,
                 color: .orange),
            // Next week
            Plan(title: "Dinner with friends",
                 notes: "Try the new ramen place",
                 weekStart: nextWeek.start,
                 sortOrder: 1,
                 color: .pink),
            Plan(title: "Tidy up the garage",
                 weekStart: nextWeek.start,
                 sortOrder: 2,
                 color: .teal),
        ]

        for plan in samples {
            context.insert(plan)
        }
    }
}
