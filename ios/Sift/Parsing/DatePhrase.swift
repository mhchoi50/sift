import Foundation

/// Turns the words someone used for timing into an actual date.
///
/// The on-device model is unreliable at date arithmetic but reliable at
/// repeating what it heard, so it hands over the phrase ("before thursday",
/// "the 14th", "next week") and this resolves it. Deterministic, testable, and
/// it removes the single largest source of wrong dates.
enum DatePhrase {

    struct Resolution {
        var date: Date?
        /// True when the phrase named a window rather than a day.
        var isApproximate: Bool
    }

    private static let weekdays: [String: Int] = [
        "sunday": 1, "sun": 1,
        "monday": 2, "mon": 2,
        "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4,
        "thursday": 5, "thu": 5, "thurs": 5,
        "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7,
    ]

    private static let months: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3,
        "april": 4, "apr": 4, "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7,
        "august": 8, "aug": 8, "september": 9, "sep": 9, "sept": 9,
        "october": 10, "oct": 10, "november": 11, "nov": 11, "december": 12, "dec": 12,
    ]

    static func resolve(_ raw: String, now: Date = Date()) -> Resolution {
        let calendar = Calendar.current
        let today = Calendar.current.startOfDay(for: now)
        var phrase = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return Resolution(date: nil, isApproximate: false) }

        // "before thursday" means the day before it, and it is a hard deadline.
        var deadlineShift = 0
        for prefix in ["before ", "by the end of ", "by ", "ahead of "] where phrase.hasPrefix(prefix) {
            if prefix == "before " || prefix == "ahead of " { deadlineShift = -1 }
            phrase = String(phrase.dropFirst(prefix.count))
            break
        }

        func shifted(_ date: Date?) -> Date? {
            guard let date else { return nil }
            return calendar.date(byAdding: .day, value: deadlineShift, to: date)
        }

        // Explicit days
        if phrase.contains("today") || phrase.contains("tonight") || phrase.contains("this evening") {
            return Resolution(date: shifted(today), isApproximate: false)
        }
        if phrase.contains("tomorrow") {
            return Resolution(date: shifted(calendar.date(byAdding: .day, value: 1, to: today)), isApproximate: false)
        }
        if phrase.contains("day after tomorrow") {
            return Resolution(date: shifted(calendar.date(byAdding: .day, value: 2, to: today)), isApproximate: false)
        }

        // "in 3 days", "in two weeks"
        if let interval = relativeInterval(in: phrase, from: today) {
            return Resolution(date: shifted(interval), isApproximate: false)
        }

        // Windows
        if phrase.contains("weekend") {
            return Resolution(date: shifted(next(weekday: 7, after: today, allowToday: false)), isApproximate: true)
        }
        if phrase.contains("next week") {
            // The end of that week — a window, not a deadline.
            let start = next(weekday: 2, after: today, allowToday: false)
            let friday = start.flatMap { calendar.date(byAdding: .day, value: 4, to: $0) }
            return Resolution(date: shifted(friday), isApproximate: true)
        }
        if phrase.contains("this week") {
            return Resolution(date: shifted(next(weekday: 6, after: today, allowToday: true)), isApproximate: true)
        }
        if phrase.contains("next month") {
            let start = calendar.date(byAdding: .month, value: 1, to: today)
            return Resolution(date: shifted(endOfMonth(start ?? today)), isApproximate: true)
        }
        if phrase.contains("end of the month") || phrase.contains("end of month") {
            return Resolution(date: shifted(endOfMonth(today)), isApproximate: true)
        }
        if phrase.contains("soon") || phrase.contains("sometime") || phrase.contains("eventually")
            || phrase.contains("one of these days") {
            return Resolution(date: nil, isApproximate: true)
        }

        // "september 14", "sept 14th", "14 september"
        if let dated = monthAndDay(in: phrase, from: today) {
            return Resolution(date: shifted(dated), isApproximate: false)
        }

        // "the 14th", "on the 3rd"
        if let dayOfMonth = ordinalDay(in: phrase),
           let dated = nextOccurrence(ofDay: dayOfMonth, from: today) {
            return Resolution(date: shifted(dated), isApproximate: false)
        }

        // A weekday on its own means its next occurrence.
        for (name, weekday) in weekdays where containsWord(phrase, name) {
            let allowToday = !phrase.contains("next")
            var date = next(weekday: weekday, after: today, allowToday: allowToday)
            if phrase.contains("next"), let bumped = date, calendar.dateComponents([.day], from: today, to: bumped).day ?? 0 < 7 {
                date = calendar.date(byAdding: .day, value: 7, to: bumped)
            }
            return Resolution(date: shifted(date), isApproximate: false)
        }

        return Resolution(date: nil, isApproximate: false)
    }

    // MARK: Helpers

    private static func containsWord(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: "\\b\(needle)\\b", options: .regularExpression) != nil
    }

    private static func next(weekday: Int, after date: Date, allowToday: Bool) -> Date? {
        let calendar = Calendar.current
        let current = calendar.component(.weekday, from: date)
        var delta = (weekday - current + 7) % 7
        if delta == 0 && !allowToday { delta = 7 }
        return calendar.date(byAdding: .day, value: delta, to: date)
    }

    private static func endOfMonth(_ date: Date) -> Date? {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return nil }
        return calendar.date(byAdding: .day, value: -1, to: interval.end)
    }

    private static func nextOccurrence(ofDay day: Int, from today: Date) -> Date? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month], from: today)
        components.day = day
        guard let thisMonth = calendar.date(from: components) else { return nil }
        if thisMonth >= today { return thisMonth }
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: thisMonth) else { return nil }
        return nextMonth
    }

    private static func ordinalDay(in phrase: String) -> Int? {
        let pattern = "\\b(\\d{1,2})(st|nd|rd|th)\\b"
        guard let range = phrase.range(of: pattern, options: .regularExpression) else { return nil }
        let digits = phrase[range].prefix { $0.isNumber }
        guard let value = Int(digits), (1...31).contains(value) else { return nil }
        return value
    }

    private static func monthAndDay(in phrase: String, from today: Date) -> Date? {
        let calendar = Calendar.current
        for (name, month) in months where containsWord(phrase, name) {
            guard let range = phrase.range(of: "\\b(\\d{1,2})\\b", options: .regularExpression),
                  let day = Int(phrase[range]), (1...31).contains(day) else { continue }
            var components = calendar.dateComponents([.year], from: today)
            components.month = month
            components.day = day
            guard let date = calendar.date(from: components) else { continue }
            // A month already past means they mean next year.
            if date < calendar.date(byAdding: .day, value: -1, to: today) ?? today {
                components.year = (components.year ?? 0) + 1
                return calendar.date(from: components)
            }
            return date
        }
        return nil
    }

    private static func relativeInterval(in phrase: String, from today: Date) -> Date? {
        let calendar = Calendar.current
        let words = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7]
        guard let match = phrase.range(of: "\\bin (\\d{1,2}|one|two|three|four|five|six|seven) (day|days|week|weeks)\\b",
                                       options: .regularExpression) else { return nil }
        let text = String(phrase[match])
        let parts = text.split(separator: " ")
        guard parts.count >= 3 else { return nil }
        let amount = Int(parts[1]) ?? words[String(parts[1])]
        guard let amount else { return nil }
        let unit = parts[2].hasPrefix("week") ? Calendar.Component.weekOfYear : .day
        return calendar.date(byAdding: unit, value: amount, to: today)
    }
}
