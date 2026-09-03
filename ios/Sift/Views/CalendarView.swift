import SwiftData
import SwiftUI

struct CalendarView: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [Item]

    @State private var month: Date = Schedule.startOfDay(Date())
    @State private var selected: Date = Schedule.startOfDay(Date())
    @State private var editing: Item?

    private var days: [Date] { Schedule.monthGrid(for: month) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthHeader
                weekdayRow
                grid
                Rule()
                dayDetail
            }
            .background(Theme.paper)
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { item in
                ItemEditView(item: item) {
                    let snapshot = items
                    Task { await Scheduler.rebuild(items: snapshot) }
                }
            }
        }
    }

    // MARK: Month

    private var monthHeader: some View {
        HStack {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left").foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(Theme.heading)
                .foregroundStyle(Theme.ink)
            Spacer()
            Button { shift(1) } label: {
                Image(systemName: "chevron.right").foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Theme.inkFaint)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
            ForEach(days, id: \.self) { day in
                DayCell(
                    day: day,
                    contents: Schedule.contents(for: day, items: items),
                    inMonth: Schedule.calendar.isDate(day, equalTo: month, toGranularity: .month),
                    isToday: Schedule.calendar.isDateInToday(day),
                    isSelected: Schedule.calendar.isDate(day, inSameDayAs: selected)
                )
                .onTapGesture { selected = Schedule.startOfDay(day) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    // MARK: Selected day

    private var dayDetail: some View {
        let contents = Schedule.contents(for: selected, items: items)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(Theme.heading)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    // The literal count line, where there is room for words.
                    Text(summaryLine(contents))
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkFaint)
                }
                .padding(.bottom, 10)

                if contents.isEmpty {
                    QuietMessage(text: "Nothing on this day.")
                } else {
                    ForEach(contents.events) { occurrence in
                        Button { editing = items.first { $0.id == occurrence.itemID } } label: {
                            OccurrenceRow(occurrence: occurrence)
                        }
                        .buttonStyle(.plain)
                        Rule()
                    }
                    ForEach(contents.tasks + contents.notes) { item in
                        Button { editing = item } label: {
                            ItemRow(item: item) { toggle(item) }
                        }
                        .buttonStyle(.plain)
                        Rule()
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 56)
        }
        .frame(maxHeight: .infinity)
    }

    private func summaryLine(_ contents: DayContents) -> String {
        var parts: [String] = []
        if !contents.events.isEmpty {
            parts.append(contents.events.count == 1 ? "1 event" : "\(contents.events.count) events")
        }
        let openTasks = contents.tasks.filter { !$0.isDone }.count
        if openTasks > 0 { parts.append(openTasks == 1 ? "1 task" : "\(openTasks) tasks") }
        if !contents.notes.isEmpty {
            parts.append(contents.notes.count == 1 ? "1 note" : "\(contents.notes.count) notes")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Helpers

    private var orderedWeekdaySymbols: [String] {
        let symbols = Schedule.calendar.veryShortWeekdaySymbols
        let first = Schedule.calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func shift(_ months: Int) {
        guard let next = Schedule.calendar.date(byAdding: .month, value: months, to: month) else { return }
        withAnimation(.snappy(duration: 0.18)) { month = next }
    }

    private func toggle(_ item: Item) {
        item.isDone.toggle()
        item.completedAt = item.isDone ? Date() : nil
        try? context.save()
        let snapshot = items
        Task { await Scheduler.rebuild(items: snapshot) }
    }
}

/// A month cell. A phone cell is ~45pt wide, which is too narrow for "5 tasks",
/// so the grid carries colour+glyph+count chips and the words go in the summary
/// line under the grid. On a wide cell the words fit, so they are used.
private struct DayCell: View {
    let day: Date
    let contents: DayContents
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool

    var body: some View {
        GeometryReader { proxy in
            let roomy = proxy.size.width >= 78

            VStack(alignment: .leading, spacing: 2) {
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 13, weight: isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)

                if roomy {
                    ForEach(labels, id: \.0) { kind, count in
                        Text(phrase(kind, count))
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .foregroundStyle(Theme.accent(for: kind))
                    }
                } else {
                    // Three chips do not fit across a ~45pt phone cell, so they
                    // wrap two per row. The words live in the summary line below
                    // the grid, where there is room for them.
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(chipRows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 4) {
                                ForEach(row, id: \.0) { kind, count in
                                    KindChip(kind: kind, count: count, compact: true)
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Theme.paperRaised : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Theme.ink.opacity(0.35) : .clear, lineWidth: 1)
            )
        }
        .frame(height: 62)
        .contentShape(Rectangle())
    }

    /// Two chips per row, so a busy day never clips.
    private var chipRows: [[(ItemKind, Int)]] {
        stride(from: 0, to: labels.count, by: 2).map {
            Array(labels[$0..<min($0 + 2, labels.count)])
        }
    }

    private var labels: [(ItemKind, Int)] {
        var out: [(ItemKind, Int)] = []
        if !contents.events.isEmpty { out.append((.event, contents.events.count)) }
        let open = contents.tasks.filter { !$0.isDone }.count
        if open > 0 { out.append((.task, open)) }
        if !contents.notes.isEmpty { out.append((.note, contents.notes.count)) }
        return out
    }

    private func phrase(_ kind: ItemKind, _ count: Int) -> String {
        switch kind {
        case .event: return count == 1 ? "event" : "\(count) events"
        case .task: return count == 1 ? "1 task" : "\(count) tasks"
        case .note: return count == 1 ? "note" : "\(count) notes"
        case .backlog: return "\(count)"
        }
    }

    private var numberColor: Color {
        if !inMonth { return Theme.inkFaint.opacity(0.55) }
        return isToday ? Theme.ink : Theme.inkSoft
    }
}
