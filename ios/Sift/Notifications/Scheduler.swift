import Foundation
import UserNotifications

/// Local notifications for Sift.
///
/// iOS allows an app 64 pending local notifications, so the three morning-class
/// alerts (5 days out, 1 day out, morning-of) are collapsed into one 7am digest
/// per day instead of being scheduled per item. That keeps the budget at roughly
/// one digest per day plus one hour-before alert per event, and it reads better
/// than three separate pings at the same minute.
///
/// Digest text is baked in at scheduling time, so the whole set is rebuilt
/// whenever the data changes.
enum Scheduler {
    static let digestHour = 7
    static let digestHorizonDays = 14
    static let leadAlertHorizonDays = 30
    static let defaultLeadMinutes = 60
    static let maxLeadAlerts = 45

    private static let center = UNUserNotificationCenter.current()

    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func rebuild(items: [Item]) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        center.removeAllPendingNotificationRequests()

        for request in digestRequests(items: items) + leadRequests(items: items) {
            try? await center.add(request)
        }
    }

    // MARK: Morning digest

    private static func digestRequests(items: [Item]) -> [UNNotificationRequest] {
        let calendar = Schedule.calendar
        let today = Schedule.startOfDay(Date())
        var requests: [UNNotificationRequest] = []

        for offset in 0..<digestHorizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  var fireDate = calendar.date(bySettingHour: digestHour, minute: 0, second: 0, of: day)
            else { continue }

            // Today's digest only makes sense if 7am hasn't already passed.
            if fireDate <= Date() {
                guard offset == 0, let soon = calendar.date(byAdding: .minute, value: 1, to: Date())
                else { continue }
                fireDate = soon
            }

            guard let body = digestBody(for: day, items: items) else { continue }

            let content = UNMutableNotificationContent()
            content.title = offset == 0 ? "Today" : dayTitle(day)
            content.body = body
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            requests.append(
                UNNotificationRequest(
                    identifier: "digest-\(ISO8601DateFormatter.dayString(day))",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
            )
        }
        return requests
    }

    /// One digest covers three of the lead times you asked for: what is happening
    /// today, what lands tomorrow, and what is five days out.
    private static func digestBody(for day: Date, items: [Item]) -> String? {
        let calendar = Schedule.calendar
        var lines: [String] = []

        let todayContents = Schedule.contents(for: day, items: items)
        var todayParts = todayContents.events.map { occurrence in
            "\(timeString(occurrence.start)) \(occurrence.title)"
        }
        todayParts += todayContents.tasks.filter { !$0.isDone }.map(\.title)
        if !todayParts.isEmpty {
            lines.append("Today: " + todayParts.joined(separator: ", "))
        }

        // Soft dates are excluded from the escalation steps — a guess at a date
        // should not nag like a deadline.
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) {
            let titles = escalationTitles(for: tomorrow, items: items)
            if !titles.isEmpty { lines.append("Tomorrow: " + titles.joined(separator: ", ")) }
        }
        if let inFive = calendar.date(byAdding: .day, value: 5, to: day) {
            let titles = escalationTitles(for: inFive, items: items)
            if !titles.isEmpty { lines.append("In 5 days: " + titles.joined(separator: ", ")) }
        }

        let overdue = Schedule.overdue(asOf: day, items: items)
        if !overdue.isEmpty {
            lines.append("Overdue: " + overdue.prefix(3).map(\.title).joined(separator: ", "))
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func escalationTitles(for day: Date, items: [Item]) -> [String] {
        let contents = Schedule.contents(for: day, items: items)
        return contents.events.map(\.title)
            + contents.tasks.filter { !$0.isDone && !$0.isSoftDate }.map(\.title)
    }

    // MARK: Per-event lead alerts

    private static func leadRequests(items: [Item]) -> [UNNotificationRequest] {
        let calendar = Schedule.calendar
        let now = Date()
        guard let horizon = calendar.date(byAdding: .day, value: leadAlertHorizonDays, to: now) else {
            return []
        }

        var upcoming: [(Item, Occurrence)] = []
        for item in items where item.kind == .event {
            for occurrence in Schedule.occurrences(of: item, from: now, to: horizon) {
                upcoming.append((item, occurrence))
            }
        }
        upcoming.sort { $0.1.start < $1.1.start }

        var requests: [UNNotificationRequest] = []
        for (item, occurrence) in upcoming {
            guard requests.count < maxLeadAlerts else { break }
            let lead = item.reminderLeadMinutes ?? defaultLeadMinutes
            guard let fire = calendar.date(byAdding: .minute, value: -lead, to: occurrence.start),
                  fire > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = occurrence.title
            content.body = lead == 60
                ? "In an hour, at \(timeString(occurrence.start))."
                : "In \(minutesPhrase(lead)), at \(timeString(occurrence.start))."
            content.sound = .default

            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fire
            )
            requests.append(
                UNNotificationRequest(
                    identifier: "lead-\(occurrence.id)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
            )
        }
        return requests
    }

    // MARK: Formatting

    private static func minutesPhrase(_ minutes: Int) -> String {
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "an hour" : "\(hours) hours"
        }
        return "\(minutes) minutes"
    }

    private static func timeString(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private static func dayTitle(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide))
    }
}

extension ISO8601DateFormatter {
    static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
