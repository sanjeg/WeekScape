//
//  WeekScapeApp.swift
//  WeekScape
//
//  App entry point. Builds a SwiftData ModelContainer that syncs via iCloud
//  (CloudKit) when the iCloud capability is configured, and transparently falls
//  back to on-device storage otherwise so the app always launches.
//

import SwiftUI
import SwiftData

@main
struct WeekScapeApp: App {
    let modelContainer: ModelContainer

    /// Whether the active container is backed by CloudKit (surfaced in Settings).
    let isCloudSyncing: Bool

    init() {
        let (container, cloud) = Self.makeContainer()
        // Enable undo so edits, deletions, and moves can be reverted.
        container.mainContext.undoManager = UndoManager()
        self.modelContainer = container
        self.isCloudSyncing = cloud
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.isCloudSyncing, isCloudSyncing)
        }
        .modelContainer(modelContainer)
    }

    /// Try CloudKit-backed storage first, then local, then in-memory as a last
    /// resort. Returns the container and whether CloudKit sync is active.
    private static func makeContainer() -> (ModelContainer, Bool) {
        let schema = Schema([Plan.self])

        // 1. iCloud sync (requires the iCloud + Background Modes capabilities).
        let cloudConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        if let container = try? ModelContainer(for: schema, configurations: cloudConfig) {
            return (container, true)
        }

        // 2. Local, on-device persistence.
        let localConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: localConfig) {
            return (container, false)
        }

        // 3. Ephemeral in-memory store so the app can still run.
        let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // If even this fails the app genuinely cannot function, so trap loudly.
        let container = try! ModelContainer(for: schema, configurations: memoryConfig)
        return (container, false)
    }
}

// MARK: - Environment plumbing

private struct CloudSyncingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isCloudSyncing: Bool {
        get { self[CloudSyncingKey.self] }
        set { self[CloudSyncingKey.self] = newValue }
    }
}
