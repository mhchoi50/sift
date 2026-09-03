import Foundation
import FoundationModels

/// Parses a capture with Apple's on-device model. No server, no API key, no
/// per-capture cost, and the text never leaves the phone.
///
/// The schema here is deliberately flatter than the server one. A ~3B on-device
/// model is far more reliable with scalar fields and sentinel empty strings than
/// with nested optionals, so dates arrive as strings and are interpreted here.
@available(iOS 26.0, *)
enum OnDeviceParser {

    // MARK: Generable schema

    @Generable
    enum DraftKind: String {
        case event, task, backlog, note
    }

    @Generable
    enum DraftRepeat: String {
        case none, daily, weekly, monthly
    }

    @Generable
    struct DraftItem {
        @Guide(description: "event = happens at a clock time. task = must be done by a date but has no time. backlog = a real intention with no date at all. note = context, feelings or decisions with no action.")
        var kind: DraftKind

        @Guide(description: "A short rewritten title, two to six words. Never the raw sentence, never filler like 'I need to'.")
        var title: String

        // The model is unreliable at date arithmetic but reliable at
        // repeating what it heard, so it hands over the phrase and
        // DatePhrase resolves it. The boolean comes first on purpose:
        // generation is sequential, so it commits to "was there timing at
        // all" before writing any.
        @Guide(description: "true only if the person said when this happens. false for open intentions with no timing.")
        var hasTiming: Bool

        @Guide(description: "The timing words exactly as said, like 'thursday', 'before friday', 'tomorrow', 'the 14th', 'next week'. Empty when hasTiming is false.")
        var when: String

        @Guide(description: "true only if the person said a clock time for this.")
        var hasTime: Bool

        @Guide(description: "The time as HH:MM on a 24-hour clock. Use 00:00 when hasTime is false.")
        var time: String

        @Guide(description: "true when the timing was vague, like 'sometime next week' or 'soon'.")
        var approximate: Bool

        @Guide(description: "How often it repeats. none for a one-off.")
        var repeats: DraftRepeat
    }

    @Generable
    struct DraftList {
        @Guide(description: "One entry for each distinct thing the person mentioned.")
        var items: [DraftItem]
    }

    // MARK: Availability

    static var availability: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    static var isAvailable: Bool { unavailableExplanation == nil }

    static var unavailableExplanation: String? {
        // The Simulator reports the model as available but fails at inference
        // with a generic error. Fail fast with something actionable instead of
        // making you wait ten seconds for it.
        #if targetEnvironment(simulator)
        return "On-device parsing doesn't run in the Simulator. Use a real device, or switch to Server in Settings."
        #else
        switch availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device can't run Apple Intelligence. Use the server instead."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings, then come back."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading. Try again shortly."
        case .unavailable:
            return "The on-device model isn't available right now."
        }
        #endif
    }

    // MARK: Instructions
    //
    // Much tighter than the server prompt: the on-device context window is small,
    // so this keeps only the rules that change the output.

    private static let instructions = """
    You turn someone thinking out loud into an organized plan. They talk like they \
    would to a friend: rambling, self-correcting, mixing what they must do with how \
    they feel.

    Write a short title for each thing. Strip filler and hedging, but keep the words \
    that say which thing it is. Do not quote their sentence back. When they correct \
    themselves, keep only the correction.

    Split by meaning, not by the word "and". Two things done separately are two \
    items. Things done in one go are one item.

    Feelings and stray observations are notes, not tasks. Something they want to do \
    eventually, with no timing, is backlog. Never write down anything they did not say.

    Most things have no timing. Set hasTiming false unless they actually said when, \
    and hasTime false unless they said a clock time. Do not work out any dates \
    yourself: copy their timing words across exactly as spoken.
    """

    // MARK: Parsing

    static func parse(transcript: String, now: Date = Date()) async throws -> [ParsedItemDTO] {
        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
        Organize this:
        \(transcript.trimmingCharacters(in: .whitespacesAndNewlines))
        """

        let response = try await session.respond(
            to: prompt,
            generating: DraftList.self,
            options: GenerationOptions(temperature: 0.3)
        )
        let vetted = stripUnheardTiming(response.content.items, transcript: transcript)
        return vetted.compactMap { convert($0, now: now) }
    }

    private static func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: Draft -> wire item

    private static func convert(_ draft: DraftItem, now: Date) -> ParsedItemDTO? {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let resolved = draft.hasTiming
            ? DatePhrase.resolve(draft.when, now: now)
            : DatePhrase.Resolution(date: nil, isApproximate: false)
        let hasDay = resolved.date != nil
        let day = resolved.date.map(isoDay) ?? ""
        let time = normalizedTime(draft.time.trimmingCharacters(in: .whitespaces))
        let hasTime = draft.hasTime && time != nil
        let approximate = draft.approximate || resolved.isApproximate

        // The model picks a kind, but the fields it actually filled are better
        // evidence than the label — a small model mislabels more often than it
        // invents a time out of nowhere.
        var kind = draft.kind
        switch kind {
        case .event where !hasDay || !hasTime:
            kind = hasDay ? .task : .backlog
        case .task where !hasDay:
            kind = .backlog
        case .note where !hasDay:
            kind = .note
        default:
            break
        }

        let repeats = recurrence(draft.repeats, on: ItemFactory.date(fromDay: day))

        return ParsedItemDTO(
            kind: kind.rawValue,
            title: title,
            details: nil,
            startAt: kind == .event ? "\(day)T\(time ?? "09:00")" : nil,
            durationMinutes: nil,
            dueOn: kind == .task ? day : nil,
            softDate: approximate,
            day: kind == .note ? (hasDay ? day : isoDay(now)) : nil,
            reminderLeadMinutes: nil,
            recurrence: kind == .event ? repeats : nil,
            needsReview: kind == .event && !hasTime
        )
    }


    /// Guards against the model's most common failure: giving several items the
    /// same timing when only one of them had any, or inventing timing outright.
    ///
    /// The instructions say to copy the person's timing words across verbatim,
    /// which makes this checkable — if the words are not in what they said, they
    /// did not say them. A phrase may be used only as many times as it actually
    /// occurs.
    private static func stripUnheardTiming(_ drafts: [DraftItem], transcript: String) -> [DraftItem] {
        let said = transcript.lowercased()
        let filler: Set<String> = ["before", "by", "on", "at", "the", "this", "in", "of", "ahead", "end", "a"]
        var budget: [String: Int] = [:]

        return drafts.map { draft in
            guard draft.hasTiming else { return draft }
            var item = draft

            let words = draft.when.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { !filler.contains($0) && $0.count >= 3 }

            guard let anchor = words.last, words.allSatisfy({ said.contains($0) }) else {
                item.hasTiming = false
                item.when = ""
                return item
            }

            if budget[anchor] == nil {
                budget[anchor] = said.components(separatedBy: anchor).count - 1
            }
            if let remaining = budget[anchor], remaining > 0 {
                budget[anchor] = remaining - 1
            } else {
                item.hasTiming = false
                item.when = ""
            }
            return item
        }
    }

    /// The on-device model reads "dentist at 2" as 02:00. Nobody schedules a
    /// dentist for two in the morning, so an unqualified early hour is read as
    /// afternoon — the same assumption a person would make.
    private static func normalizedTime(_ raw: String) -> String? {
        let parts = raw.split(separator: ":")
        guard parts.count == 2, var hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        if hour >= 1 && hour <= 6 { hour += 12 }
        return String(format: "%02d:%02d", hour, minute)
    }

    /// Weekday and day-of-month come from the first occurrence, so the model
    /// never has to express them separately.
    private static func recurrence(_ repeats: DraftRepeat, on date: Date?) -> RecurrenceDTO? {
        guard repeats != .none else { return nil }
        let calendar = Schedule.calendar
        switch repeats {
        case .none:
            return nil
        case .daily:
            return RecurrenceDTO(frequency: "daily", weekdays: nil, dayOfMonth: nil, until: nil)
        case .weekly:
            let weekday = date.map { calendar.component(.weekday, from: $0) }
            return RecurrenceDTO(frequency: "weekly", weekdays: weekday.map { [$0] }, dayOfMonth: nil, until: nil)
        case .monthly:
            let dom = date.map { calendar.component(.day, from: $0) }
            return RecurrenceDTO(frequency: "monthly", weekdays: nil, dayOfMonth: dom, until: nil)
        }
    }
}
