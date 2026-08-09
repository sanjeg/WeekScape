//
//  SettingsView.swift
//  Weekend Planner
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.isCloudSyncing) private var isCloudSyncing
    @Environment(\.dismiss) private var dismiss

    @AppStorage(WeekConfig.firstWeekdayKey) private var firstWeekday: Int = 2
    @AppStorage(WeekConfig.weeksAheadKey) private var weeksAhead: Int = WeekConfig.defaultWeeksAhead

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
        }
    }
}
