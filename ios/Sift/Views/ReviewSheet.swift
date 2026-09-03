import SwiftUI

/// What the parser proposed, before it becomes real. Aggressive rewriting only
/// works if a bad rewrite is cheap to catch, which is what this screen is for.
struct ReviewSheet: View {
    let transcript: String
    let drafts: [ParsedItemDTO]
    let onCommit: ([Item]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edited: [DraftItem] = []
    @State private var expanded: UUID?
    @State private var showingTranscript = false

    private var includedCount: Int { edited.filter(\.include).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach($edited) { $draft in
                        DraftRow(draft: $draft, isExpanded: expanded == draft.id) {
                            withAnimation(.snappy(duration: 0.2)) {
                                expanded = expanded == draft.id ? nil : draft.id
                            }
                        }
                        Rule()
                    }

                    DisclosureGroup(isExpanded: $showingTranscript) {
                        Text(transcript)
                            .font(Theme.serif(15))
                            .foregroundStyle(Theme.inkSoft)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    } label: {
                        Text("What you said")
                            .font(Theme.label)
                            .foregroundStyle(Theme.inkFaint)
                    }
                    .tint(Theme.inkFaint)
                    .padding(.top, 20)
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle("Sifted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Discard") { onCommit([]) }
                        .foregroundStyle(Theme.inkSoft)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(includedCount == 1 ? "Add 1" : "Add \(includedCount)") {
                        onCommit(edited.filter(\.include).map { $0.makeItem() })
                    }
                    .font(.body.weight(.semibold))
                    .disabled(includedCount == 0)
                }
            }
        }
        .onAppear {
            if edited.isEmpty { edited = drafts.map(DraftItem.init) }
        }
    }
}

// MARK: - Editable draft

struct DraftItem: Identifiable {
    let id = UUID()
    var include = true
    var kind: ItemKind
    var title: String
    var details: String?
    var startAt: Date?
    var durationMinutes: Int?
    var dueOn: Date?
    var day: Date?
    var isSoftDate: Bool
    var reminderLeadMinutes: Int?
    var recurrence: Recurrence?
    var needsReview: Bool

    init(_ dto: ParsedItemDTO) {
        let item = ItemFactory.make(from: dto)
        kind = item.kind
        title = item.title
        details = item.details
        startAt = item.startAt
        durationMinutes = item.durationMinutes
        dueOn = item.dueOn
        day = item.day
        isSoftDate = item.isSoftDate
        reminderLeadMinutes = item.reminderLeadMinutes
        recurrence = item.recurrence
        needsReview = item.needsReview
    }

    /// The date this row edits, which depends on its kind.
    var editableDate: Date? {
        switch kind {
        case .event: return startAt
        case .task: return dueOn
        case .note: return day
        case .backlog: return nil
        }
    }

    var dateSummary: String {
        switch kind {
        case .event:
            guard let startAt else { return "No time" }
            return startAt.formatted(date: .abbreviated, time: .shortened)
        case .task:
            guard let dueOn else { return "No date" }
            return (isSoftDate ? "~ " : "") + dueOn.formatted(date: .abbreviated, time: .omitted)
        case .note:
            return (day ?? Date()).formatted(date: .abbreviated, time: .omitted)
        case .backlog:
            return "Someday"
        }
    }

    func makeItem() -> Item {
        Item(
            kind: kind,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            details: details,
            startAt: kind == .event ? startAt : nil,
            durationMinutes: kind == .event ? durationMinutes : nil,
            dueOn: kind == .task ? dueOn.map { Schedule.startOfDay($0) } : nil,
            isSoftDate: isSoftDate,
            day: kind == .note ? Schedule.startOfDay(day ?? Date()) : nil,
            reminderLeadMinutes: reminderLeadMinutes,
            needsReview: false,
            recurrence: kind == .event ? recurrence : nil
        )
    }
}

// MARK: - Row

private struct DraftRow: View {
    @Binding var draft: DraftItem
    let isExpanded: Bool
    let onTapDate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    draft.include.toggle()
                } label: {
                    Image(systemName: draft.include ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 19))
                        .foregroundStyle(draft.include ? Theme.accent(for: draft.kind) : Theme.inkFaint)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 5) {
                    TextField("Title", text: $draft.title, axis: .vertical)
                        .font(Theme.serif(17))
                        .foregroundStyle(draft.include ? Theme.ink : Theme.inkFaint)

                    if let details = draft.details {
                        Text(details)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.inkSoft)
                    }

                    HStack(spacing: 8) {
                        Menu {
                            ForEach(ItemKind.allCases) { kind in
                                Button(kind.label) { draft.kind = kind }
                            }
                        } label: {
                            KindChip(kind: draft.kind)
                        }

                        if draft.kind != .backlog {
                            Button(action: onTapDate) {
                                Text(draft.dateSummary)
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.inkSoft)
                                    .underline(isExpanded, color: Theme.rule)
                            }
                            .buttonStyle(.plain)
                        }

                        if let rule = draft.recurrence {
                            Label(rule.summary, systemImage: "repeat")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.inkFaint)
                                .labelStyle(.titleAndIcon)
                        }

                        if draft.needsReview {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.backlog)
                        }
                    }
                }
            }

            if isExpanded, draft.kind != .backlog {
                datePicker
                    .padding(.leading, 29)
            }
        }
        .padding(.vertical, 12)
        .opacity(draft.include ? 1 : 0.5)
    }

    @ViewBuilder
    private var datePicker: some View {
        switch draft.kind {
        case .event:
            DatePicker(
                "Starts",
                selection: Binding(get: { draft.startAt ?? Date() }, set: { draft.startAt = $0 }),
                displayedComponents: [.date, .hourAndMinute]
            )
            .font(Theme.caption)
        case .task:
            VStack(alignment: .leading, spacing: 6) {
                DatePicker(
                    "Due",
                    selection: Binding(get: { draft.dueOn ?? Date() }, set: { draft.dueOn = $0 }),
                    displayedComponents: [.date]
                )
                Toggle("Approximate", isOn: $draft.isSoftDate)
                    .font(Theme.caption)
                    .tint(Theme.inkSoft)
            }
            .font(Theme.caption)
        case .note:
            DatePicker(
                "Day",
                selection: Binding(get: { draft.day ?? Date() }, set: { draft.day = $0 }),
                displayedComponents: [.date]
            )
            .font(Theme.caption)
        case .backlog:
            EmptyView()
        }
    }
}
