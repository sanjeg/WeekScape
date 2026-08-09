//
//  PlanEditorView.swift
//  Weekend Planner
//
//  Sheet for creating or editing a plan. A plan always belongs to a week; the
//  user may optionally pin it to a specific day within that week.
//

import SwiftUI
import SwiftData

/// What the editor sheet is currently doing.
enum PlanEditorState: Identifiable {
    case create(Week)
    case edit(Plan, Week)

    var id: String {
        switch self {
        case .create(let week): return "create-\(week.id.timeIntervalSince1970)"
        case .edit(let plan, _): return "edit-\(plan.id.uuidString)"
        }
    }

    var week: Week {
        switch self {
        case .create(let week): return week
        case .edit(_, let week): return week
        }
    }

    var existing: Plan? {
        if case .edit(let plan, _) = self { return plan }
        return nil
    }
}

struct PlanEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let state: PlanEditorState

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var color: PlanColor = .blue
    @State private var assignDay: Bool = false

    /// The chosen day, or `nil` when no day has been picked yet — in which
    /// case no chip is highlighted and the plan stays undated.
    @State private var selectedDay: Date?

    /// The week this plan will live in; changeable from the editor.
    @State private var selectedWeekStart: Date

    init(state: PlanEditorState) {
        self.state = state
        _selectedDay = State(initialValue: state.existing?.specificDate)
        _selectedWeekStart = State(initialValue: state.week.start)
    }

    private var isEditing: Bool { state.existing != nil }

    private var selectedWeek: Week { Week(start: selectedWeekStart) }

    /// Weeks offered in the picker: a generous window around today, always
    /// including the plan's current week.
    private var weekOptions: [Week] {
        var options = WeekConfig.window(past: 8, future: 26)
        if !options.contains(where: { $0.start == state.week.start }) {
            options.append(state.week)
            options.sort { $0.start < $1.start }
        }
        return options
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What's the plan?", text: $title, axis: .vertical)
                        .font(.body.weight(.medium))
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    Picker("Week", selection: $selectedWeekStart) {
                        ForEach(weekOptions) { week in
                            Text(PlannerFormat.weekRange(week))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .tag(week.start)
                        }
                    }
                } header: {
                    Text("Week")
                } footer: {
                    if isEditing && selectedWeekStart != state.week.start {
                        Text("This plan will move to \(PlannerFormat.weekRange(selectedWeek)).")
                    }
                }
                .onChange(of: selectedWeekStart) { _, newStart in
                    // Carry a picked day into the new week, same weekday.
                    guard let day = selectedDay else { return }
                    let cal = WeekConfig.calendar
                    let offset = cal.dateComponents(
                        [.day],
                        from: WeekConfig.startOfWeek(for: day),
                        to: cal.startOfDay(for: day)
                    ).day ?? 0
                    selectedDay = cal.date(byAdding: .day, value: offset, to: newStart)
                }

                Section {
                    Toggle("Pin to a specific day", isOn: $assignDay.animation())
                    if assignDay {
                        dayPicker
                    }
                } footer: {
                    Text(assignDay
                         ? "This plan will show a day badge and stay flexible within the week."
                         : "Leave off to keep this plan floating anywhere in the week.")
                }

                Section("Color") {
                    colorPicker
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            if let plan = state.existing {
                                PlanActions.delete(plan, in: context)
                            }
                            dismiss()
                        } label: {
                            Label("Delete plan", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Plan" : "New Plan")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    // MARK: - Day picker

    private var dayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.spacing2) {
                ForEach(selectedWeek.days, id: \.self) { day in
                    dayChip(day)
                }
            }
            .padding(.vertical, Theme.spacing1)
        }
    }

    private func dayChip(_ day: Date) -> some View {
        let cal = WeekConfig.calendar
        let isSelected = selectedDay.map { cal.isDate(day, inSameDayAs: $0) } ?? false
        return Button {
            // Tapping the selected day again unselects it (no date).
            selectedDay = isSelected ? nil : day
        } label: {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2)
                Text(day.formatted(.dateTime.day()))
                    .font(.headline)
            }
            .frame(width: 40, height: 52)
            .background(isSelected ? color.color : Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Color picker

    private var colorPicker: some View {
        HStack(spacing: Theme.spacing3) {
            ForEach(PlanColor.allCases) { option in
                Circle()
                    .fill(option.color)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle()
                            .stroke(Color.primary, lineWidth: color == option ? 3 : 0)
                            .padding(2)
                    )
                    .onTapGesture { color = option }
                    .accessibilityLabel(option.displayName)
            }
            Spacer()
        }
        .padding(.vertical, Theme.spacing1)
    }

    // MARK: - Persistence

    private func loadExisting() {
        // The pin toggle always starts on — for new plans and when editing.
        // The user can still switch it off to let a plan float in its week.
        assignDay = true

        guard let plan = state.existing else { return }
        title = plan.title
        notes = plan.notes
        color = plan.color
        if let date = plan.specificDate {
            selectedDay = date
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        // No date is stored unless the toggle is on AND a day was picked.
        let date = assignDay
            ? selectedDay.map { WeekConfig.calendar.startOfDay(for: $0) }
            : nil

        if let plan = state.existing {
            plan.title = trimmedTitle
            plan.notes = trimmedNotes
            plan.color = color
            plan.specificDate = date
            // Moving to another week: append at the end of the destination.
            if selectedWeekStart != state.week.start {
                plan.weekStart = selectedWeekStart
                plan.sortOrder = PlanActions.appendOrder(
                    in: allPlansInWeek().filter { $0.id != plan.id }
                )
            }
        } else {
            let plan = Plan(
                title: trimmedTitle,
                notes: trimmedNotes,
                weekStart: selectedWeekStart,
                specificDate: date,
                sortOrder: PlanActions.appendOrder(in: allPlansInWeek()),
                color: color
            )
            context.insert(plan)
        }
        dismiss()
    }

    /// Fetch existing plans in the selected week to compute the next sort order.
    private func allPlansInWeek() -> [Plan] {
        let start = selectedWeek.start
        let end = selectedWeek.end
        let descriptor = FetchDescriptor<Plan>(
            predicate: #Predicate { $0.weekStart >= start && $0.weekStart <= end }
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
