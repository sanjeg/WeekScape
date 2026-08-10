//
//  SampleData.swift
//  Weekend Planner
//
//  Seeds a handful of placeholder plans on first launch so new users see how
//  the app works instead of an empty stream.
//

import Foundation
import SwiftData
import CloudKit
import CoreData

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

    /// Seeds the starter plans once it is safe to decide whether this user is
    /// truly new. After a reinstall the local store is empty even though the
    /// user's plans still exist in iCloud, so when an iCloud account is
    /// available, wait for the first CloudKit import to finish (bounded by a
    /// timeout) before treating an empty store as a brand-new user. Without an
    /// iCloud account there is nothing to wait for and seeding runs
    /// immediately.
    @MainActor
    static func seedWhenSafe(in context: ModelContext, isCloudSyncing: Bool) async {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }

        if isCloudSyncing, await iCloudAccountAvailable() {
            await firstImportOrTimeout(seconds: 15)
        }
        seedIfNeeded(in: context)
    }

    private static func iCloudAccountAvailable() async -> Bool {
        let status = try? await CKContainer.default().accountStatus()
        return status == .available
    }

    /// Waits until the first CloudKit import finishes (successfully or not —
    /// a failed import means remote plans cannot arrive anyway) or the timeout
    /// elapses, whichever comes first.
    private static func firstImportOrTimeout(seconds: Double) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                let events = NotificationCenter.default.notifications(
                    named: NSPersistentCloudKitContainer.eventChangedNotification
                )
                for await note in events {
                    let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                    if let event = note.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
                       event.type == .import, event.endDate != nil {
                        return
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
            }
            await group.next()
            group.cancelAll()
        }
    }

    /// Fixed identities for the starter plans. Two devices that both seed
    /// before their first iCloud import produces the same ids, so
    /// `removeDuplicatePlans` can recognize and collapse the copies once sync
    /// brings them together.
    private static let sampleIDs: [UUID] = [
        UUID(uuidString: "5EEDDA7A-0000-4000-8000-000000000001")!,
        UUID(uuidString: "5EEDDA7A-0000-4000-8000-000000000002")!,
        UUID(uuidString: "5EEDDA7A-0000-4000-8000-000000000003")!,
        UUID(uuidString: "5EEDDA7A-0000-4000-8000-000000000004")!,
        UUID(uuidString: "5EEDDA7A-0000-4000-8000-000000000005")!,
    ]

    /// Deletes plans that share an `id`, keeping the earliest-created copy.
    /// Every device keeps the same survivor (ties broken by `createdAt`), so
    /// concurrent dedupes on different devices converge on one copy instead of
    /// each deleting the other's. Only seeding can produce shared ids —
    /// user-created plans always get a fresh `UUID()` and drag-and-drop moves
    /// plans rather than copying them.
    @MainActor
    static func removeDuplicatePlans(in context: ModelContext) {
        guard let plans = try? context.fetch(FetchDescriptor<Plan>()) else { return }
        for copies in Dictionary(grouping: plans, by: \.id).values where copies.count > 1 {
            let ordered = copies.sorted { $0.createdAt < $1.createdAt }
            for extra in ordered.dropFirst() {
                context.delete(extra)
            }
        }
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

        for (plan, id) in zip(samples, sampleIDs) {
            plan.id = id
            context.insert(plan)
        }
    }
}
