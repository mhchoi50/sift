import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [Item]
    @State private var editing: Item?

    private var today: Date { Schedule.startOfDay(Date()) }
    private var contents: DayContents { Schedule.contents(for: today, items: items) }
    private var overdue: [Item] { Schedule.overdue(asOf: today, items: items) }
    private var backlog: [Item] { Schedule.backlog(items: items) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    if contents.isEmpty && overdue.isEmpty && backlog.isEmpty {
                        QuietMessage(text: "Nothing written down for today.")
                    }

                    if !contents.events.isEmpty {
                        section("Schedule") {
                            ForEach(contents.events) { occurrence in
                                Button { editing = item(for: occurrence.itemID) } label: {
                                    OccurrenceRow(occurrence: occurrence)
                                }
                                .buttonStyle(.plain)
                                Rule()
                            }
                        }
                    }

                    if !overdue.isEmpty {
                        section("Overdue", trailing: "\(overdue.count)") {
                            ForEach(overdue) { item in
                                row(item, showAge: false)
                            }
                        }
                    }

                    if !contents.tasks.isEmpty {
                        section("Due today") {
                            ForEach(contents.tasks) { item in
                                row(item, showAge: false)
                            }
                        }
                    }

                    if !contents.notes.isEmpty {
                        section("Notes") {
                            ForEach(contents.notes) { item in
                                row(item, showAge: false)
                            }
                        }
                    }

                    if !backlog.isEmpty {
                        // Oldest first: age is the only pressure an undated item has.
                        section("Sitting there", trailing: backlog.count > 5 ? "\(backlog.count)" : nil) {
                            ForEach(backlog.prefix(5)) { item in
                                row(item, showAge: true)
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 56)
            }
            .background(Theme.paper)
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { item in
                ItemEditView(item: item) { rebuildNotifications() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(today.formatted(.dateTime.weekday(.wide)))
                .font(Theme.display)
                .foregroundStyle(Theme.ink)
            Text(today.formatted(.dateTime.day().month(.wide).year()))
                .font(Theme.serif(16))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(text: title, trailing: trailing)
            Rule()
            content()
        }
    }

    private func row(_ item: Item, showAge: Bool) -> some View {
        Group {
            Button { editing = item } label: {
                ItemRow(item: item, showAge: showAge) { toggle(item) }
            }
            .buttonStyle(.plain)
            Rule()
        }
    }

    private func item(for id: UUID) -> Item? {
        items.first { $0.id == id }
    }

    private func toggle(_ item: Item) {
        item.isDone.toggle()
        item.completedAt = item.isDone ? Date() : nil
        try? context.save()
        rebuildNotifications()
    }

    private func rebuildNotifications() {
        let snapshot = items
        Task { await Scheduler.rebuild(items: snapshot) }
    }
}
