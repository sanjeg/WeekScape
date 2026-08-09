//
//  PrivacyView.swift
//  Weekend Planner
//

import SwiftUI

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing4) {
                Text("Privacy Policy")
                    .font(.largeTitle.bold())
                Text("Last updated: August 2026")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                policySection(
                    "Your data stays yours",
                    "WeekScape does not operate any servers of its own and does not collect analytics, advertising identifiers, or personal information. There are no third-party trackers in this app."
                )

                policySection(
                    "iCloud storage",
                    "When iCloud is enabled on your device, your plans are stored in your personal iCloud account (Apple's CloudKit) so they can sync across your devices. This data is handled by Apple under Apple's privacy policy and is not accessible to the app's developer. If iCloud is unavailable, your plans are stored only on your device."
                )

                policySection(
                    "No account required",
                    "You don't create an account with us. There is no sign-up, and no email or password is collected by the app."
                )

                policySection(
                    "Deleting your data",
                    "You can delete any plan at any time from within the app. Removing the app removes its local data from the device. To remove iCloud-synced data, you can also manage it through your device's iCloud settings."
                )

                policySection(
                    "Contact",
                    "Questions about privacy? Reach out to the developer through the App Store listing for WeekScape."
                )
            }
            .padding(Theme.spacing4)
        }
        .background(.plannerBackground)
        .navigationTitle("Privacy")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func policySection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing2) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
