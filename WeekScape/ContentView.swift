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

    /// Whether an action can currently be undone (drives the Undo button).
    @State private var canUndo = false

    /// One-time onboarding flag. Bumped if the intro copy changes materially.
    @AppStorage(SampleData.onboardingKey) private var didCompleteOnboarding = false

    /// Owns the EventKit bridge for the whole scene so the week stream and
    /// Settings share one source of truth.
    @State private var calendarStore = CalendarStore()

    var body: some View {
        NavigationStack {
            WeekListView()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: Theme.spacing3) {
                            if canUndo {
                                Button {
                                    context.undoManager?.undo()
                                } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                        .fontWeight(.regular)
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityLabel("Undo")
                            }
                            Button {
                                showingWishlist = true
                            } label: {
                                Image(systemName: "star")
                                    .fontWeight(.regular)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("Wishlist")
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
                    .sharedBackgroundVisibility(.hidden)
                }
        }
        .environment(calendarStore)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environment(calendarStore)
        }
        .sheet(isPresented: $showingWishlist) {
            WishlistView()
        }
        .fullScreenCover(isPresented: Binding(
            get: { !didCompleteOnboarding },
            set: { if $0 == false { didCompleteOnboarding = true } }
        )) {
            OnboardingView { didCompleteOnboarding = true }
        }
        .task { await calendarStore.observeChanges() }
        .task { await observeUndo() }
        .task {
            await SampleData.seedWhenSafe(in: context, isCloudSyncing: isCloudSyncing)
            SampleData.removeDuplicatePlans(in: context)
            // Don't let the initial seed/dedup become the user's first "Undo".
            context.undoManager?.removeAllActions()

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

    /// Keep `canUndo` in sync with the context's undo manager by watching the
    /// relevant notifications (avoids Combine and manual polling).
    private func observeUndo() async {
        guard let manager = context.undoManager else { return }
        canUndo = manager.canUndo

        let names: [Notification.Name] = [
            .NSUndoManagerDidCloseUndoGroup,
            .NSUndoManagerDidUndoChange,
            .NSUndoManagerDidRedoChange
        ]
        await withTaskGroup(of: Void.self) { group in
            for name in names {
                group.addTask {
                    let notifications = NotificationCenter.default.notifications(
                        named: name, object: manager
                    )
                    for await _ in notifications {
                        await MainActor.run { canUndo = manager.canUndo }
                    }
                }
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
