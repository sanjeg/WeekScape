//
//  ContentView.swift
//  Weekend Planner
//
//  Root scene: the week stream plus access to Settings / standard pages.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
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
        .onAppear {
            SampleData.seedIfNeeded(in: context)
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
