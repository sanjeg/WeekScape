//
//  AboutView.swift
//  Weekend Planner
//

import SwiftUI

struct AboutView: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing4) {
                Image(systemName: "calendar.day.timeline.left")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [PlanColor.blue.color, PlanColor.purple.color],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.top, Theme.spacing5)

                Text("WeekScape")
                    .font(.title.bold())

                Text(version)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Your Weeks at a Glance")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: Theme.spacing3) {
                    aboutParagraph("Traditional calendars push you into hourly slots. WeekScape works at the scale most personal plans actually live at — the week.")
                    aboutParagraph("See several upcoming weeks at once, drop plans into whichever week fits, and pin a specific day only when you want to. Drag plans between weeks as things shift.")
                    aboutParagraph("Everything you add syncs privately through your own iCloud account, so your plans are on every device you own.")
                }
                .padding(Theme.spacing4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.plannerSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))

                Text("Made with SwiftUI & SwiftData")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, Theme.spacing2)
            }
            .padding(Theme.spacing4)
        }
        .background(.plannerBackground)
        .navigationTitle("About")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func aboutParagraph(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
