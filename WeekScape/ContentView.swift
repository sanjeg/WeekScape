//
//  ContentView.swift
//  Weekend Planner
//
//  Root scene: the week stream plus access to Settings / standard pages.
//

import SwiftUI
import SwiftData
import CoreData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.isCloudSyncing) private var isCloudSyncing
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            WeekListView()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .task {
            await SampleData.seedWhenSafe(in: context, isCloudSyncing: isCloudSyncing)
            SampleData.removeDuplicatePlans(in: context)

            // Starter plans seeded on another device arrive via CloudKit well
            // after launch, so reconcile duplicates after each import too.
            let events = NotificationCenter.default.notifications(
                named: NSPersistentCloudKitContainer.eventChangedNotification
            )
            for await note in events {
                let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                guard let event = note.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
                      event.type == .import, event.endDate != nil else { continue }
                SampleData.removeDuplicatePlans(in: context)
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Plan.self, configurations: config)
    SampleData.insertSamples(in: container.mainContext)
    return ContentView()
        .modelContainer(container)
}
