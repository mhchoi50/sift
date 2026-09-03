#if DEBUG
import Foundation
import SwiftData

/// Fills an empty store with a plausible day so the layouts can be seen without
/// a server. Compiled out of release builds. Launch with `-siftSampleData YES`.
enum SampleData {
    static func installIfRequested(in context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: "siftSampleData") else { return }
        let existing = try? context.fetch(FetchDescriptor<Item>())
        guard (existing?.isEmpty ?? true) else { return }

        let calendar = Schedule.calendar
        let today = Schedule.startOfDay(Date())
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today) ?? today
        }

        let capture = Capture(transcript: "god today was brutal, three back to backs. um I need to shoot professor Kim an email about the recommendation thing before Thursday, and book the flight and the hotel for the conference, oh and dentist at 2 on the 14th")
        context.insert(capture)

        let items: [Item] = [
            Item(kind: .event, title: "Standup", startAt: at(0, 9, 30), durationMinutes: 15,
                 recurrence: Recurrence(frequency: .weekly, weekdays: [2, 3, 4, 5, 6], dayOfMonth: nil, until: nil)),
            Item(kind: .event, title: "Lunch with Ada", details: "The place on Fifth",
                 startAt: at(0, 12, 30), durationMinutes: 60),
            Item(kind: .event, title: "Dentist", startAt: at(11, 14), durationMinutes: 45),
            Item(kind: .event, title: "Flight to Chicago", startAt: at(4, 7, 15)),
            Item(kind: .task, title: "Email Prof. Kim about recommendation letter", dueOn: day(0)),
            Item(kind: .task, title: "Renew parking pass", dueOn: day(-2)),
            Item(kind: .task, title: "Draft the conference talk", dueOn: day(5), isSoftDate: true),
            Item(kind: .task, title: "Return the library books", dueOn: day(1)),
            Item(kind: .backlog, title: "Book conference flight"),
            Item(kind: .backlog, title: "Book conference hotel"),
            Item(kind: .backlog, title: "Look into that grad program"),
            Item(kind: .note, title: "Rough day — three back-to-back meetings", day: day(0)),
            Item(kind: .note, title: "Ada suggested moving the launch to October", day: day(0)),
        ]

        // Backdate creation so the backlog ages read realistically.
        let ages = [0, 0, 0, 0, 0, 3, 1, 0, 9, 9, 23, 0, 0]
        for (item, age) in zip(items, ages) {
            item.createdAt = calendar.date(byAdding: .day, value: -age, to: Date()) ?? Date()
            item.capture = capture
            context.insert(item)
        }
        try? context.save()
    }
}
#endif
