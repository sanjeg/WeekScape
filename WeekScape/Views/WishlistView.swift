//
//  WishlistView.swift
//  WeekScape
//
//  A dateless "someday" list. Plans here belong to no week; the user can add
//  ideas freely and later schedule any of them into a week (with an optional
//  day) from the plan editor's "Add to a week" toggle.
//

import SwiftUI
import SwiftData

struct WishlistView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Plan> { $0.isWishlist }, sort: \Plan.sortOrder)
    private var wishlistPlans: [Plan]

    @State private var editorState: PlanEditorState?

    var body: some View {
        NavigationStack {
            Group {
                if wishlistPlans.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .background(Theme.backgroundWash)
            .navigationTitle("Wishlist")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorState = .createWishlist
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add wishlist item")
                }
            }
            .sheet(item: $editorState) { state in
                PlanEditorView(state: state)
            }
        }
    }

    // MARK: - Content

    private var listContent: some View {
        ScrollView {
            VStack(spacing: Theme.spacing2) {
                Text("Tap an item to schedule it into a week.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, Theme.spacing1)

                ForEach(wishlistPlans) { plan in
                    PlanRowView(
                        plan: plan,
                        onToggleDone: { plan.isDone.toggle() },
                        onOpen: { editorState = .editWishlist(plan) },
                        onDelete: { PlanActions.delete(plan, in: context) }
                    )
                }
            }
            .padding(Theme.spacing4)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.spacing3) {
            Image(systemName: "star")
                .font(.system(size: 52))
                .foregroundStyle(PlanColor.orange.gradient)
            Text("Your Wishlist is empty")
                .font(.title3.bold())
            Text("Add plans without a date and schedule them into a week whenever you're ready.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacing5)
            Button {
                editorState = .createWishlist
            } label: {
                Label("Add an idea", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, Theme.spacing2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.spacing4)
    }
}
