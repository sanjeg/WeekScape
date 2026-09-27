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
    @State private var showingWishlist = false

    /// Restores deleted plans. Deletions are the only undoable action.
    private let undoStore = PlanUndoStore.shared

    /// One-time onboarding flag. Bumped if the intro copy changes materially.
    @AppStorage(SampleData.onboardingKey) private var didCompleteOnboarding = false

    /// User-selected appearance (system, light, dark).
    @AppStorage(Theme.appearanceKey) private var appearance: AppAppearance = .system

    /// Owns the EventKit bridge for the whole scene so the week stream and
    /// Settings share one source of truth.
    @State private var calendarStore = CalendarStore()

    var body: some View {
        NavigationStack {
            WeekListView(showingWishlist: $showingWishlist)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: Theme.spacing3) {
                            if undoStore.canUndo {
                                Button {
                                    undoStore.undoLastDeletion(in: context)
                                } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                        .fontWeight(.regular)
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityLabel("Undo delete")
                            }
                            Button {
                                withAnimation(.snappy) { showingWishlist.toggle() }
                            } label: {
                                Image(systemName: showingWishlist ? "star.fill" : "star")
                                    .fontWeight(.regular)
                                    .foregroundStyle(showingWishlist ? PlanColor.orange.color : .secondary)
                            }
                            .accessibilityLabel(showingWishlist ? "Hide Wishlist" : "Show Wishlist")
                            Button {
                                showingSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                                    .fontWeight(.regular)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("Settings")
                        }
                        .buttonStyle(.plain)
                    }
                    .plainToolbarBackground()
                }
        }
        .preferredColorScheme(appearance.colorScheme)
        .environment(calendarStore)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environment(calendarStore)
        }
        .fullScreenCover(isPresented: Binding(
            get: { !didCompleteOnboarding },
            set: { if $0 == false { didCompleteOnboarding = true } }
        )) {
            OnboardingView { didCompleteOnboarding = true }
        }
        .task { await calendarStore.observeChanges() }
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
    let container = try! ModelContainer(
        for: Plan.self, EventCompletion.self,
        configurations: config
    )
    SampleData.insertSamples(in: container.mainContext)
    return ContentView()
        .modelContainer(container)
}
