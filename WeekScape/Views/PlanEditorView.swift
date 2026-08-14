//
//  PlanEditorView.swift
//  Weekend Planner
//
//  Sheet for creating or editing a plan. A plan usually belongs to a week; the
//  user may optionally pin it to a specific day (or a span of days) within that
//  week. Plans can also live dateless in the Wishlist, and be scheduled into a
//  week from here.
//

import SwiftUI
import SwiftData

/// What the editor sheet is currently doing.
enum PlanEditorState: Identifiable {
    case create(Week)
    case edit(Plan, Week)
    /// Create a new dateless Wishlist plan.
    case createWishlist
    /// Edit an existing Wishlist plan (optionally scheduling it into a week).
    case editWishlist(Plan)

    var id: String {
        switch self {
        case .create(let week): return "create-\(week.id.timeIntervalSince1970)"
        case .edit(let plan, _): return "edit-\(plan.id.uuidString)"
        case .createWishlist: return "create-wishlist"
        case .editWishlist(let plan): return "edit-wishlist-\(plan.id.uuidString)"
        }
    }

    /// The week the plan starts in, when it already has one.
    var week: Week? {
        switch self {
        case .create(let week): return week
        case .edit(_, let week): return week
        case .createWishlist, .editWishlist: return nil
        }
    }

    var existing: Plan? {
        switch self {
        case .edit(let plan, _): return plan
        case .editWishlist(let plan): return plan
        case .create, .createWishlist: return nil
        }
    }

    /// True when the editor was opened from the Wishlist, which surfaces the
    /// "Add to a week" scheduling toggle.
    var isWishlistContext: Bool {
        switch self {
        case .createWishlist, .editWishlist: return true
        case .create, .edit: return false
        }
    }
}

struct PlanEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let state: PlanEditorState

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var color: PlanColor = .blue

    /// Wishlist only: whether this plan should be scheduled into a week (and so
    /// leave the Wishlist) instead of staying dateless.
    @State private var addToWeek: Bool = false

    @State private var assignDay: Bool = false

    /// The chosen start day, or `nil` when no day has been picked yet — in which
    /// case no chip is highlighted and the plan stays undated.
    @State private var selectedDay: Date?

    /// Whether the plan spans multiple days.
    @State private var multiDay: Bool = false

    /// The chosen end day for a multi-day plan (always on/after `selectedDay`).
    @State private var selectedEndDay: Date?

    /// The week this plan will live in; changeable from the editor.
    @State private var selectedWeekStart: Date

    /// The plan's week when the editor opened, used to detect a move. For a
    /// multi-day plan this is its start week, even when opened from a later week.
    private let originalWeekStart: Date

    init(state: PlanEditorState) {
        self.state = state
        _selectedDay = State(initialValue: state.existing?.specificDate)
        _selectedEndDay = State(initialValue: state.existing?.endDate)

        let initialWeekStart: Date
        if let existing = state.existing {
            initialWeekStart = existing.specificDate.map { WeekConfig.startOfWeek(for: $0) }
                ?? existing.weekStart
        } else {
            initialWeekStart = state.week?.start ?? WeekConfig.startOfWeek(for: Date())
        }
        self.originalWeekStart = initialWeekStart
        _selectedWeekStart = State(initialValue: initialWeekStart)
    }

    private var isEditing: Bool { state.existing != nil }

    private var selectedWeek: Week { Week(start: selectedWeekStart) }

    /// Whether the week/day scheduling controls are shown. Regular plans always
    /// have a week; Wishlist plans only when the user opts to schedule them.
    private var showSchedule: Bool { !state.isWishlistContext || addToWeek }

    /// Weeks offered in the picker: a generous window around today, always
    /// including the plan's current week.
    private var weekOptions: [Week] {
        var options = WeekConfig.window(past: 8, future: 26)
        if !options.contains(where: { $0.start == selectedWeekStart }) {
            options.append(selectedWeek)
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

                if state.isWishlistContext {
                    Section {
                        Toggle("Add to a week", isOn: $addToWeek.animation())
                    } footer: {
                        Text(addToWeek
                             ? "This plan moves out of your Wishlist into the chosen week."
                             : "Kept in your Wishlist with no date. You can schedule it into a week anytime.")
                    }
                }

                if showSchedule {
                    weekSection
                    daySection
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
            .navigationTitle(navigationTitle)
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

    private var navigationTitle: String {
        switch state {
        case .create: return "New Plan"
        case .edit: return "Edit Plan"
        case .createWishlist: return "New Wishlist Item"
        case .editWishlist: return "Edit Wishlist Item"
        }
    }

    // MARK: - Week & day sections

    private var weekSection: some View {
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
            if isEditing, selectedWeekStart != originalWeekStart {
                Text("This plan will move to \(PlannerFormat.weekRange(selectedWeek)).")
            }
        }
        .onChange(of: selectedWeekStart) { _, newStart in
            // Carry the picked start day into the new week (same weekday), and
            // shift a multi-day end by the same delta so the span is preserved.
            let cal = WeekConfig.calendar
            let oldStart = selectedDay
            selectedDay = remap(selectedDay, toWeekStartingAt: newStart)
            if let end = selectedEndDay, let from = oldStart, let to = selectedDay {
                let delta = cal.dateComponents(
                    [.day],
                    from: cal.startOfDay(for: from),
                    to: cal.startOfDay(for: to)
                ).day ?? 0
                selectedEndDay = cal.date(byAdding: .day, value: delta, to: cal.startOfDay(for: end))
            }
        }
    }

    private var daySection: some View {
        Section {
            Toggle("Pin to a specific day", isOn: $assignDay.animation())
            if assignDay {
                dayPicker
                if selectedDay != nil {
                    Toggle("Spans multiple days", isOn: $multiDay.animation())
                    if multiDay, let start = selectedDay {
                        DatePicker(
                            "Ends",
                            selection: endBinding,
                            in: WeekConfig.calendar.startOfDay(for: start)...,
                            displayedComponents: .date
                        )
                    }
                }
            }
        } footer: {
            Text(dayFooter)
        }
        .onChange(of: selectedDay) { _, newDay in
            // Dropping the start day cancels a multi-day span; otherwise keep the
            // end day strictly after the new start.
            let cal = WeekConfig.calendar
            guard let newDay else {
                multiDay = false
                selectedEndDay = nil
                return
            }
            if let end = selectedEndDay, end <= cal.startOfDay(for: newDay) {
                selectedEndDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: newDay))
            }
        }
        .onChange(of: multiDay) { _, on in
            // Seed a sensible end (the day after the start) when turning the span
            // on; clear it when turning it off.
            let cal = WeekConfig.calendar
            guard on, let start = selectedDay else {
                if !on { selectedEndDay = nil }
                return
            }
            let startDay = cal.startOfDay(for: start)
            if selectedEndDay == nil || selectedEndDay! <= startDay {
                selectedEndDay = cal.date(byAdding: .day, value: 1, to: startDay)
            }
        }
    }

    /// Non-optional bridge for the end-date `DatePicker`, normalized to midnight.
    private var endBinding: Binding<Date> {
        Binding(
            get: {
                let cal = WeekConfig.calendar
                if let end = selectedEndDay { return end }
                if let start = selectedDay {
                    return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: start))
                        ?? cal.startOfDay(for: start)
                }
                return cal.startOfDay(for: Date())
            },
            set: { selectedEndDay = WeekConfig.calendar.startOfDay(for: $0) }
        )
    }

    private var dayFooter: String {
        if !assignDay {
            return "Leave off to keep this plan floating anywhere in the week."
        }
        return multiDay
            ? "This plan will span the selected days within the week."
            : "This plan will show a day badge and stay flexible within the week."
    }

    // MARK: - Day pickers

    private var dayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.spacing2) {
                ForEach(selectedWeek.days, id: \.self) { day in
                    dayChip(day, isSelected: isSameDay(day, selectedDay)) {
                        // Tapping the selected day again unselects it (no date).
                        selectedDay = isSameDay(day, selectedDay) ? nil : day
                    }
                }
            }
            .padding(.vertical, Theme.spacing1)
        }
    }

    private func dayChip(_ day: Date, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

    // MARK: - Helpers

    private func isSameDay(_ a: Date, _ b: Date?) -> Bool {
        b.map { WeekConfig.calendar.isDate(a, inSameDayAs: $0) } ?? false
    }

    /// Move a date to the same weekday in the week starting at `weekStart`.
    private func remap(_ date: Date?, toWeekStartingAt weekStart: Date) -> Date? {
        guard let date else { return nil }
        let cal = WeekConfig.calendar
        let offset = cal.dateComponents(
            [.day],
            from: WeekConfig.startOfWeek(for: date),
            to: cal.startOfDay(for: date)
        ).day ?? 0
        return cal.date(byAdding: .day, value: offset, to: weekStart)
    }

    // MARK: - Persistence

    private func loadExisting() {
        guard let plan = state.existing else {
            // New plan: default the pin toggle on for regular plans so a day is
            // easy to add; Wishlist items start dateless (and unscheduled).
            assignDay = !state.isWishlistContext
            return
        }
        title = plan.title
        notes = plan.notes
        color = plan.color
        selectedDay = plan.specificDate
        assignDay = plan.specificDate != nil
        if plan.isMultiDay {
            multiDay = true
            selectedEndDay = plan.endDate
        }
        // Editing a scheduled plan from the Wishlist context keeps it scheduled.
        addToWeek = state.isWishlistContext ? !plan.isWishlist : true
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let scheduled = showSchedule
        // No date is stored unless scheduling into a week, the pin toggle is on,
        // AND a day was picked.
        let cal = WeekConfig.calendar
        let startDay = (scheduled && assignDay) ? selectedDay.map { cal.startOfDay(for: $0) } : nil
        let endDay: Date? = {
            guard let start = startDay, multiDay, let end = selectedEndDay else { return nil }
            let normalizedEnd = cal.startOfDay(for: end)
            return normalizedEnd > start ? normalizedEnd : nil
        }()

        if let plan = state.existing {
            plan.title = trimmedTitle
            plan.notes = trimmedNotes
            plan.color = color
            applyScheduling(to: plan, scheduled: scheduled, startDay: startDay, endDay: endDay)
        } else {
            let plan = makePlan(
                title: trimmedTitle,
                notes: trimmedNotes,
                scheduled: scheduled,
                startDay: startDay,
                endDay: endDay
            )
            context.insert(plan)
        }
        dismiss()
    }

    /// Build a brand-new plan, either scheduled into a week or dateless in the
    /// Wishlist.
    private func makePlan(title: String, notes: String, scheduled: Bool, startDay: Date?, endDay: Date?) -> Plan {
        if scheduled {
            return Plan(
                title: title,
                notes: notes,
                weekStart: selectedWeekStart,
                specificDate: startDay,
                endDate: endDay,
                isWishlist: false,
                sortOrder: PlanActions.appendOrder(in: weekPlans()),
                color: color
            )
        } else {
            return Plan(
                title: title,
                notes: notes,
                weekStart: WeekConfig.startOfWeek(for: Date()),
                isWishlist: true,
                sortOrder: PlanActions.wishlistAppendOrder(in: wishlistPlans()),
                color: color
            )
        }
    }

    /// Apply week/date changes to an existing plan, including promoting a
    /// Wishlist plan into a week (or keeping it in the Wishlist).
    private func applyScheduling(to plan: Plan, scheduled: Bool, startDay: Date?, endDay: Date?) {
        guard scheduled else {
            // Keep (or move) the plan in the Wishlist.
            if !plan.isWishlist {
                plan.isWishlist = true
                plan.sortOrder = PlanActions.wishlistAppendOrder(in: wishlistPlans())
            }
            plan.specificDate = nil
            plan.endDate = nil
            return
        }

        let wasScheduledElsewhere = plan.isWishlist || plan.weekStart != selectedWeekStart
        plan.isWishlist = false
        plan.weekStart = selectedWeekStart
        plan.specificDate = startDay
        plan.endDate = endDay
        if wasScheduledElsewhere {
            plan.sortOrder = PlanActions.appendOrder(in: weekPlans().filter { $0.id != plan.id })
        }
    }

    /// Existing scheduled plans in the selected week (used for sort ordering).
    private func weekPlans() -> [Plan] {
        let start = selectedWeek.start
        let end = selectedWeek.end
        let descriptor = FetchDescriptor<Plan>(
            predicate: #Predicate { !$0.isWishlist && $0.weekStart >= start && $0.weekStart <= end }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Existing Wishlist plans (used for sort ordering).
    private func wishlistPlans() -> [Plan] {
        let descriptor = FetchDescriptor<Plan>(predicate: #Predicate { $0.isWishlist })
        return (try? context.fetch(descriptor)) ?? []
    }
}
