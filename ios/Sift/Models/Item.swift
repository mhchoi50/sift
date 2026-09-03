import Foundation
import SwiftData

enum ItemKind: String, Codable, CaseIterable, Identifiable {
    case event, task, backlog, note

    var id: String { rawValue }

    var label: String {
        switch self {
        case .event: return "Event"
        case .task: return "Task"
        case .backlog: return "Backlog"
        case .note: return "Note"
        }
    }

    /// Chips pair colour with a glyph so colour is never the only channel.
    var glyph: String {
        switch self {
        case .event: return "circle.fill"
        case .task: return "square.fill"
        case .backlog: return "triangle.fill"
        case .note: return "diamond.fill"
        }
    }
}

enum Frequency: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, monthly
    var id: String { rawValue }
}

/// Simple rules only: daily, weekly on given weekdays, or monthly on a date.
/// No per-occurrence exceptions — editing a series edits the whole series.
struct Recurrence: Codable, Equatable {
    var frequency: Frequency
    var weekdays: [Int]?      // 1 = Sunday ... 7 = Saturday
    var dayOfMonth: Int?
    var until: Date?

    var summary: String {
        switch frequency {
        case .daily:
            return "Every day"
        case .weekly:
            guard let days = weekdays, !days.isEmpty else { return "Every week" }
            let symbols = Calendar.current.shortWeekdaySymbols
            let names = days.sorted().compactMap { day -> String? in
                guard (1...7).contains(day) else { return nil }
                return symbols[day - 1]
            }
            return "Every " + names.joined(separator: ", ")
        case .monthly:
            guard let day = dayOfMonth else { return "Every month" }
            return "Monthly on the \(day)\(Self.ordinalSuffix(day))"
        }
    }

    static func ordinalSuffix(_ n: Int) -> String {
        switch (n % 100, n % 10) {
        case (11...13, _): return "th"
        case (_, 1): return "st"
        case (_, 2): return "nd"
        case (_, 3): return "rd"
        default: return "th"
        }
    }
}

@Model
final class Item {
    var id: UUID = UUID()
    var kindRaw: String = ItemKind.note.rawValue
    var title: String = ""
    var details: String?

    /// Events: exact start. For a recurring event this is the first occurrence.
    var startAt: Date?
    var durationMinutes: Int?

    /// Tasks: the day it is due, normalised to the start of that day.
    var dueOn: Date?
    /// True when the date came from vague timing. Softly dated items are shown
    /// differently and are left out of the 5-day / 1-day escalation.
    var isSoftDate: Bool = false

    /// Notes: the day they belong to.
    var day: Date?

    var isDone: Bool = false
    var completedAt: Date?
    var createdAt: Date = Date()

    /// Per-item override in minutes before. Nil means use the default ladder.
    var reminderLeadMinutes: Int?

    /// Set by the parser when a date or intent was ambiguous.
    var needsReview: Bool = false

    private var recurrenceData: Data?

    var capture: Capture?

    init(
        kind: ItemKind,
        title: String,
        details: String? = nil,
        startAt: Date? = nil,
        durationMinutes: Int? = nil,
        dueOn: Date? = nil,
        isSoftDate: Bool = false,
        day: Date? = nil,
        reminderLeadMinutes: Int? = nil,
        needsReview: Bool = false,
        recurrence: Recurrence? = nil
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.title = title
        self.details = details
        self.startAt = startAt
        self.durationMinutes = durationMinutes
        self.dueOn = dueOn
        self.isSoftDate = isSoftDate
        self.day = day
        self.reminderLeadMinutes = reminderLeadMinutes
        self.needsReview = needsReview
        self.createdAt = Date()
        self.recurrence = recurrence
    }

    var kind: ItemKind {
        get { ItemKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    var recurrence: Recurrence? {
        get {
            guard let recurrenceData else { return nil }
            return try? JSONDecoder().decode(Recurrence.self, from: recurrenceData)
        }
        set {
            recurrenceData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    var isRecurring: Bool { recurrenceData != nil }

    /// The date this item sorts under, whatever its kind.
    var anchorDate: Date? {
        switch kind {
        case .event: return startAt
        case .task: return dueOn
        case .note: return day
        case .backlog: return nil
        }
    }

    var ageInDays: Int {
        Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0
    }
}

/// The raw text of one capture, kept forever. Because the parser rewrites
/// aggressively, the original wording is the only source of truth when a
/// summary comes out wrong.
@Model
final class Capture {
    var id: UUID = UUID()
    var transcript: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Item.capture)
    var items: [Item]? = []

    init(transcript: String) {
        self.id = UUID()
        self.transcript = transcript
        self.createdAt = Date()
    }
}
