import Foundation

/// One dated appearance of an event. A non-recurring event has exactly one;
/// a recurring event has one per matching day, generated on the fly.
struct Occurrence: Identifiable, Hashable {
    let itemID: UUID
    let start: Date
    let durationMinutes: Int?
    let title: String
    let details: String?
    let needsReview: Bool
    let isRecurring: Bool

    var id: String { "\(itemID.uuidString)-\(start.timeIntervalSince1970)" }

    var end: Date? {
        durationMinutes.map { start.addingTimeInterval(TimeInterval($0 * 60)) }
    }
}

/// Everything filed under a single day.
struct DayContents {
    var events: [Occurrence] = []
    var tasks: [Item] = []
    var notes: [Item] = []

    var isEmpty: Bool { events.isEmpty && tasks.isEmpty && notes.isEmpty }
    var total: Int { events.count + tasks.count + notes.count }
}

enum Schedule {
    static var calendar: Calendar { Calendar.current }

    // MARK: Recurrence expansion

    /// Dates on which `item` occurs within the given day range, inclusive.
    /// Only simple rules are supported, and a series has no per-occurrence
    /// exceptions — that is a deliberate v1 limit.
    static func occurrences(of item: Item, from rangeStart: Date, to rangeEnd: Date) -> [Occurrence] {
        guard item.kind == .event, let first = item.startAt else { return [] }

        func make(_ date: Date) -> Occurrence {
            Occurrence(
                itemID: item.id,
                start: date,
                durationMinutes: item.durationMinutes,
                title: item.title,
                details: item.details,
                needsReview: item.needsReview,
                isRecurring: item.isRecurring
            )
        }

        guard let rule = item.recurrence else {
            return (first >= rangeStart && first <= rangeEnd) ? [make(first)] : []
        }

        let stop = min(rangeEnd, rule.until.map { endOfDay($0) } ?? rangeEnd)
        guard stop >= rangeStart else { return [] }

        let time = calendar.dateComponents([.hour, .minute], from: first)
        var results: [Occurrence] = []
        var cursor = max(startOfDay(rangeStart), startOfDay(first))
        let limit = startOfDay(stop)

        // Personal-scale ranges are at most a few months, so a day walk is
        // simpler and plenty fast compared with per-rule date arithmetic.
        var guardCount = 0
        while cursor <= limit && guardCount < 1200 {
            guardCount += 1
            if matches(rule: rule, day: cursor, seriesStart: first),
               let dated = calendar.date(bySettingHour: time.hour ?? 0,
                                         minute: time.minute ?? 0,
                                         second: 0,
                                         of: cursor),
               dated >= first, dated >= rangeStart, dated <= stop {
                results.append(make(dated))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return results
    }

    private static func matches(rule: Recurrence, day: Date, seriesStart: Date) -> Bool {
        switch rule.frequency {
        case .daily:
            return true
        case .weekly:
            let weekday = calendar.component(.weekday, from: day)
            if let days = rule.weekdays, !days.isEmpty { return days.contains(weekday) }
            return weekday == calendar.component(.weekday, from: seriesStart)
        case .monthly:
            let dom = calendar.component(.day, from: day)
            let target = rule.dayOfMonth ?? calendar.component(.day, from: seriesStart)
            if dom == target { return true }
            // A 31st rule still fires in a short month, on its last day.
            let range = calendar.range(of: .day, in: .month, for: day)
            if let last = range?.upperBound.advanced(by: -1), target > last, dom == last { return true }
            return false
        }
    }

    // MARK: Assembling a day

    static func contents(for day: Date, items: [Item]) -> DayContents {
        let start = startOfDay(day)
        let end = endOfDay(day)
        var out = DayContents()

        for item in items {
            switch item.kind {
            case .event:
                out.events += occurrences(of: item, from: start, to: end)
            case .task:
                if let due = item.dueOn, calendar.isDate(due, inSameDayAs: start) { out.tasks.append(item) }
            case .note:
                if let noteDay = item.day, calendar.isDate(noteDay, inSameDayAs: start) { out.notes.append(item) }
            case .backlog:
                break
            }
        }

        out.events.sort { $0.start < $1.start }
        out.tasks.sort { ($0.isDone ? 1 : 0, $0.createdAt) < ($1.isDone ? 1 : 0, $1.createdAt) }
        out.notes.sort { $0.createdAt < $1.createdAt }
        return out
    }

    /// Tasks that were due before today and are still open.
    static func overdue(asOf day: Date, items: [Item]) -> [Item] {
        let start = startOfDay(day)
        return items
            .filter { $0.kind == .task && !$0.isDone }
            .filter { ($0.dueOn.map { $0 < start }) == true }
            .sorted { ($0.dueOn ?? .distantPast) < ($1.dueOn ?? .distantPast) }
    }

    /// Open backlog, oldest first — age is what creates the pressure to act.
    static func backlog(items: [Item]) -> [Item] {
        items
            .filter { $0.kind == .backlog && !$0.isDone }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: Date helpers

    static func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    static func endOfDay(_ date: Date) -> Date {
        calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay(date)) ?? date
    }

    static func monthGrid(for month: Date) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: interval.start) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }
}
