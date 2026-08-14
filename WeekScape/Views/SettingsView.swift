//
//  SettingsView.swift
//  Weekend Planner
//

import SwiftUI
import EventKit
#if os(iOS)
import UIKit
#endif

struct SettingsView: View {
    @Environment(\.isCloudSyncing) private var isCloudSyncing
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(CalendarStore.self) private var calendarStore
    @Environment(\.openURL) private var openURL

    @AppStorage(WeekConfig.firstWeekdayKey) private var firstWeekday: Int = 2
    @AppStorage(WeekConfig.weeksAheadKey) private var weeksAhead: Int = WeekConfig.defaultWeeksAhead

    /// Drives the destructive "Reset App" confirmation.
    @State private var showingResetConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Start week on", selection: $firstWeekday) {
                        Text("Sunday").tag(1)
                        Text("Monday").tag(2)
                    }
                    Picker("Upcoming weeks shown", selection: $weeksAhead) {
                        ForEach([4, 8, 12, 16, 26], id: \.self) { count in
                            Text("\(count) weeks").tag(count)
                        }
                    }
                } header: {
                    Text("Week")
                } footer: {
                    Text("How many future weeks appear when the app opens. You can always load more with “More weeks”.")
                }

                calendarSection

                Section {
                    HStack {
                        Label("iCloud Sync", systemImage: isCloudSyncing ? "checkmark.icloud.fill" : "icloud.slash")
                            .foregroundStyle(isCloudSyncing ? Color.green : .secondary)
                        Spacer()
                        Text(isCloudSyncing ? "On" : "Local only")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    Text(isCloudSyncing
                         ? "Your plans sync automatically across your devices signed in to the same iCloud account."
                         : "Plans are stored on this device. To enable iCloud sync, turn on the iCloud (CloudKit) and Background Modes → Remote notifications capabilities for this app target in Xcode, then relaunch.")
                }

                Section("About") {
                    NavigationLink { AboutView() } label: {
                        Label("About WeekScape", systemImage: "info.circle")
                    }
                    NavigationLink { PrivacyView() } label: {
                        Label("Privacy", systemImage: "hand.raised")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("Reset App", systemImage: "trash")
                    }
                } footer: {
                    Text("Deletes every plan and restores WeekScape to its original state.")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Reset App?", isPresented: $showingResetConfirmation) {
                Button("Delete Everything", role: .destructive, action: resetApp)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently deletes all of your plans and settings and restores WeekScape to its original state. This can't be undone.")
            }
        }
    }

    /// Wipe all data and preferences, then close Settings so the fresh state
    /// (including the welcome screen) is revealed.
    private func resetApp() {
        // Reset in-memory calendar preferences too, since these live in the
        // observable store rather than being re-read from UserDefaults.
        calendarStore.showEvents = false
        calendarStore.selectedCalendarIDs = []
        SampleData.resetToFreshInstall(in: context)
        dismiss()
    }

    // MARK: - Calendar

    @ViewBuilder
    private var calendarSection: some View {
        Section {
            Toggle("Show Calendar Events", isOn: showEventsBinding)

            if calendarStore.showEvents, calendarStore.authorizationStatus == .fullAccess {
                NavigationLink {
                    CalendarPickerView()
                } label: {
                    Label("Calendars", systemImage: "calendar")
                }
            }

            if calendarStore.authorizationStatus == .denied
                || calendarStore.authorizationStatus == .restricted {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }
        } header: {
            Text("Calendar")
        } footer: {
            Text(calendarFooter)
        }
    }

    /// Turning the toggle on when access hasn't been decided prompts for it, and
    /// only commits the "on" state if the user grants access.
    private var showEventsBinding: Binding<Bool> {
        Binding(
            get: { calendarStore.showEvents },
            set: { newValue in
                guard newValue else {
                    calendarStore.showEvents = false
                    return
                }
                if calendarStore.authorizationStatus == .notDetermined {
                    Task { calendarStore.showEvents = await calendarStore.requestAccess() }
                } else {
                    calendarStore.showEvents = true
                }
            }
        )
    }

    private var calendarFooter: String {
        switch calendarStore.authorizationStatus {
        case .denied, .restricted:
            return "Calendar access is off. Turn it on in Settings to show your events alongside your plans."
        default:
            return "Show events from your iPhone Calendar in each week, right beside your plans. Pick which calendars to include."
        }
    }
}
