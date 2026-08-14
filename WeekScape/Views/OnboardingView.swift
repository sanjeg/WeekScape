//
//  OnboardingView.swift
//  WeekScape
//
//  A one-time welcome screen shown on first launch. It introduces the app's
//  headline features and lets the user decide whether to start with the sample
//  "starter" plans or a clean slate.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var context

    /// Whether to keep the seeded starter plans. Defaults on so new users have
    /// something to explore.
    @State private var startWithExamples = true

    /// Called when the user finishes onboarding.
    let onFinish: () -> Void

    private struct Feature: Identifiable {
        let id = UUID()
        let icon: String
        let color: PlanColor
        let title: String
        let subtitle: String
    }

    private let features: [Feature] = [
        Feature(icon: "calendar",
                color: .blue,
                title: "Plan by the week",
                subtitle: "See several weeks at a glance and drop plans into whichever week fits."),
        Feature(icon: "calendar.badge.clock",
                color: .green,
                title: "Single or multi-day",
                subtitle: "Pin a plan to a day, span it across several days, or let it float in the week."),
        Feature(icon: "star",
                color: .orange,
                title: "Keep a Wishlist",
                subtitle: "Capture someday ideas with no date, then schedule them into a week when you're ready."),
        Feature(icon: "arrow.uturn.backward",
                color: .purple,
                title: "Undo mistakes",
                subtitle: "Changed your mind? Undo brings back what you just deleted or edited."),
        Feature(icon: "icloud",
                color: .teal,
                title: "Synced privately",
                subtitle: "Everything syncs through your own iCloud account across your devices.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Theme.spacing5) {
                    header
                    VStack(spacing: Theme.spacing4) {
                        ForEach(features) { feature in
                            featureRow(feature)
                        }
                    }
                    starterToggle
                }
                .padding(Theme.spacing4)
            }

            getStartedButton
                .padding(Theme.spacing4)
        }
        .background(Theme.backgroundWash)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: Theme.spacing2) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: PlanColor.pink.color.opacity(0.35), radius: 8, y: 4)
                .padding(.top, Theme.spacing5)

            Text("Welcome to WeekScape")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text("Your Weeks at a Glance")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func featureRow(_ feature: Feature) -> some View {
        HStack(alignment: .top, spacing: Theme.spacing3) {
            Image(systemName: feature.icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(feature.color.gradient, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.headline)
                Text(feature.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var starterToggle: some View {
        VStack(alignment: .leading, spacing: Theme.spacing2) {
            Toggle(isOn: $startWithExamples) {
                Text("Start with example plans")
                    .font(.headline)
            }
            Text("A few sample plans show you how everything works. Turn this off to begin with an empty planner.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.spacing4)
        .background(.plannerSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var getStartedButton: some View {
        Button {
            if !startWithExamples {
                SampleData.removeStarterPlans(in: context)
            }
            onFinish()
        } label: {
            Text("Get Started")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.spacing2)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
