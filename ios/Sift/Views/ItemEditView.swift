import SwiftData
import SwiftUI

/// The escape hatch. Whatever the parser got wrong, this fixes.
struct ItemEditView: View {
    @Bindable var item: Item
    var onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var showingDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $item.title, axis: .vertical)
                        .font(Theme.serif(17))
                    TextField("Details", text: Binding(
                        get: { item.details ?? "" },
                        set: { item.details = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .font(Theme.body)
                }

                Section("Kind") {
                    Picker("Kind", selection: Binding(
                        get: { item.kind },
                        set: { changeKind(to: $0) }
                    )) {
                        ForEach(ItemKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                switch item.kind {
                case .event:
                    Section("When") {
                        DatePicker("Starts", selection: Binding(
                            get: { item.startAt ?? Date() },
                            set: { item.startAt = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])

                        Picker("Duration", selection: Binding(
                            get: { item.durationMinutes ?? 0 },
                            set: { item.durationMinutes = $0 == 0 ? nil : $0 }
                        )) {
                            Text("Not set").tag(0)
                            ForEach([15, 30, 45, 60, 90, 120, 180], id: \.self) {
                                Text("\($0) min").tag($0)
                            }
                        }
                    }
                    Section("Repeats") {
                        RecurrenceEditor(recurrence: Binding(
                            get: { item.recurrence },
                            set: { item.recurrence = $0 }
                        ))
                        if item.isRecurring {
                            Text("Changes apply to the whole series.")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.inkFaint)
                        }
                    }
                case .task:
                    Section("When") {
                        DatePicker("Due", selection: Binding(
                            get: { item.dueOn ?? Date() },
                            set: { item.dueOn = Schedule.startOfDay($0) }
                        ), displayedComponents: [.date])
                        Toggle("Approximate date", isOn: $item.isSoftDate)
                        if item.isSoftDate {
                            Text("Left out of the 5-day and 1-day reminders.")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.inkFaint)
                        }
                    }
                case .note:
                    Section("Day") {
                        DatePicker("Day", selection: Binding(
                            get: { item.day ?? Date() },
                            set: { item.day = Schedule.startOfDay($0) }
                        ), displayedComponents: [.date])
                    }
                case .backlog:
                    Section {
                        Text("No date. It'll surface on the today page, oldest first.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.inkFaint)
                    }
                }

                if item.kind == .event {
                    Section("Reminder") {
                        Picker("Alert", selection: Binding(
                            get: { item.reminderLeadMinutes ?? -1 },
                            set: { item.reminderLeadMinutes = $0 == -1 ? nil : $0 }
                        )) {
                            Text("Default (1 hour before)").tag(-1)
                            ForEach([0, 10, 30, 120, 1440], id: \.self) { minutes in
                                Text(leadLabel(minutes)).tag(minutes)
                            }
                        }
                    }
                }

                if let capture = item.capture {
                    Section("What you said") {
                        Text(capture.transcript)
                            .font(Theme.serif(15))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }

                Section {
                    Button("Delete", role: .destructive) { showingDeleteConfirm = true }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { save() }.font(.body.weight(.semibold))
                }
            }
            .confirmationDialog("Delete this item?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    context.delete(item)
                    save()
                }
            }
        }
    }

    private func changeKind(to kind: ItemKind) {
        item.kind = kind
        switch kind {
        case .event:
            if item.startAt == nil { item.startAt = item.dueOn ?? Date() }
        case .task:
            if item.dueOn == nil { item.dueOn = Schedule.startOfDay(item.startAt ?? Date()) }
        case .note:
            if item.day == nil { item.day = Schedule.startOfDay(item.anchorDate ?? Date()) }
        case .backlog:
            break
        }
    }

    private func leadLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "At the time"
        case 1440: return "A day before"
        case let m where m % 60 == 0: return "\(m / 60) hours before"
        default: return "\(minutes) minutes before"
        }
    }

    private func save() {
        try? context.save()
        onChange()
        dismiss()
    }
}

private struct RecurrenceEditor: View {
    @Binding var recurrence: Recurrence?

    private var isOn: Bool { recurrence != nil }

    var body: some View {
        Toggle("Repeats", isOn: Binding(
            get: { isOn },
            set: { on in recurrence = on ? Recurrence(frequency: .weekly, weekdays: nil, dayOfMonth: nil, until: nil) : nil }
        ))

        if let rule = recurrence {
            Picker("Every", selection: Binding(
                get: { rule.frequency },
                set: { recurrence?.frequency = $0 }
            )) {
                ForEach(Frequency.allCases) { Text($0.rawValue.capitalized).tag($0) }
            }

            if rule.frequency == .weekly {
                WeekdayPicker(selection: Binding(
                    get: { Set(recurrence?.weekdays ?? []) },
                    set: { recurrence?.weekdays = $0.isEmpty ? nil : Array($0).sorted() }
                ))
            }

            if rule.frequency == .monthly {
                Picker("Day", selection: Binding(
                    get: { rule.dayOfMonth ?? 1 },
                    set: { recurrence?.dayOfMonth = $0 }
                )) {
                    ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                }
            }
        }
    }
}

private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...7, id: \.self) { weekday in
                let on = selection.contains(weekday)
                Button {
                    if on { selection.remove(weekday) } else { selection.insert(weekday) }
                } label: {
                    Text(Schedule.calendar.veryShortWeekdaySymbols[weekday - 1])
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 30, height: 30)
                        .background(on ? Theme.event : Theme.paperRaised, in: Circle())
                        .foregroundStyle(on ? Theme.paper : Theme.inkSoft)
                        .overlay(Circle().stroke(Theme.rule, lineWidth: on ? 0 : 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}
