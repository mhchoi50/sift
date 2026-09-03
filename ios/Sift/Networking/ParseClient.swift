import Foundation

// MARK: - Wire types (mirror server/app/schema.py)

struct RecurrenceDTO: Decodable {
    let frequency: String
    let weekdays: [Int]?
    let dayOfMonth: Int?
    let until: String?
}

struct ParsedItemDTO: Decodable, Identifiable {
    let id = UUID()
    let kind: String
    let title: String
    let details: String?
    let startAt: String?
    let durationMinutes: Int?
    let dueOn: String?
    let softDate: Bool
    let day: String?
    let reminderLeadMinutes: Int?
    let recurrence: RecurrenceDTO?
    let needsReview: Bool

    private enum CodingKeys: String, CodingKey {
        case kind, title, details, startAt, durationMinutes, dueOn, softDate, day
        case reminderLeadMinutes, recurrence, needsReview
    }
}

struct ParseResponseDTO: Decodable {
    let items: [ParsedItemDTO]
    let transcript: String
}

// MARK: - Client

enum ParseError: LocalizedError {
    case notConfigured
    case server(Int, String)
    case unreachable

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Set the server address in Settings first."
        case .server(_, let detail):
            return detail
        case .unreachable:
            return "Couldn't reach the Sift server. Is it running?"
        }
    }
}

enum ServerConfig {
    private static let key = "sift.serverURL"
    static let fallback = "http://localhost:8787"

    static var urlString: String {
        get { UserDefaults.standard.string(forKey: key) ?? fallback }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var url: URL? { URL(string: urlString) }
}

struct ParseClient {
    static let shared = ParseClient()

    /// Local wall-clock, no zone — the server pairs it with a date table so the
    /// model never has to do calendar arithmetic itself.
    private static let localFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    func parse(transcript: String, now: Date = Date()) async throws -> ParseResponseDTO {
        guard let base = ServerConfig.url, let endpoint = URL(string: "parse", relativeTo: base) else {
            throw ParseError.notConfigured
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "transcript": transcript,
            "now_local": Self.localFormatter.string(from: now),
            "timezone": TimeZone.current.identifier,
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ParseError.unreachable
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw ParseError.server(status, detail ?? "The server returned \(status).")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ParseResponseDTO.self, from: data)
    }
}

// MARK: - Turning wire items into model items

enum ItemFactory {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = format
        return f
    }

    static func date(fromDay string: String?) -> Date? {
        guard let string else { return nil }
        return formatter("yyyy-MM-dd").date(from: string)
    }

    static func date(fromDateTime string: String?) -> Date? {
        guard let string else { return nil }
        // The model is asked for minute precision; tolerate seconds anyway.
        return formatter("yyyy-MM-dd'T'HH:mm").date(from: string)
            ?? formatter("yyyy-MM-dd'T'HH:mm:ss").date(from: string)
    }

    static func make(from dto: ParsedItemDTO) -> Item {
        let kind = ItemKind(rawValue: dto.kind) ?? .note

        var rule: Recurrence?
        if let r = dto.recurrence, let freq = Frequency(rawValue: r.frequency) {
            rule = Recurrence(
                frequency: freq,
                weekdays: r.weekdays,
                dayOfMonth: r.dayOfMonth,
                until: date(fromDay: r.until)
            )
        }

        return Item(
            kind: kind,
            title: dto.title,
            details: dto.details,
            startAt: date(fromDateTime: dto.startAt),
            durationMinutes: dto.durationMinutes,
            dueOn: date(fromDay: dto.dueOn).map { Schedule.startOfDay($0) },
            isSoftDate: dto.softDate,
            day: date(fromDay: dto.day).map { Schedule.startOfDay($0) },
            reminderLeadMinutes: dto.reminderLeadMinutes,
            needsReview: dto.needsReview,
            recurrence: rule
        )
    }
}
