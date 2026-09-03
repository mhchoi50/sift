import Foundation
import FoundationModels

enum ParseEngine: String, CaseIterable, Identifiable {
    case onDevice
    case server

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onDevice: return "On device"
        case .server: return "Server"
        }
    }

    var blurb: String {
        switch self {
        case .onDevice:
            return "Apple's on-device model. Free, works offline, nothing leaves the phone."
        case .server:
            return "Claude, via the parse server on your Mac. Better at messy captures; costs per capture."
        }
    }
}

/// Picks where a capture gets parsed. The two engines are interchangeable, so
/// you can compare them on the same speech.
enum CaptureParser {
    private static let key = "sift.engine"

    static var engine: ParseEngine {
        get { ParseEngine(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .onDevice }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    static func parse(transcript: String) async throws -> ParseResponseDTO {
        switch engine {
        case .server:
            return try await ParseClient.shared.parse(transcript: transcript)
        case .onDevice:
            guard OnDeviceParser.isAvailable else {
                throw ParseFailure.unavailable(
                    OnDeviceParser.unavailableExplanation ?? "The on-device model isn't available."
                )
            }
            do {
                let items = try await OnDeviceParser.parse(transcript: transcript)
                return ParseResponseDTO(items: items, transcript: transcript)
            } catch let error as LanguageModelSession.GenerationError {
                throw ParseFailure.model(describe(error))
            }
        }
    }

    private static func describe(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize:
            return "That capture was too long for the on-device model. Try saying it in two goes."
        case .assetsUnavailable:
            return "The on-device model isn't downloaded yet."
        case .guardrailViolation:
            return "The on-device model declined that one. Rephrasing usually clears it."
        case .unsupportedGuide:
            return "That capture hit a limit in the on-device model's schema. Please report it."
        case .concurrentRequests:
            return "Still working on the last capture. Give it a second."
        case .unsupportedLanguageOrLocale:
            return "The on-device model doesn't support this language yet."
        case .decodingFailure:
            return "Couldn't make sense of the model's answer. Try again."
        case .rateLimited:
            return "Too many requests at once. Try again in a moment."
        case .refusal:
            return "The on-device model declined that one."
        @unknown default:
            return "The on-device model couldn't handle that one. Try rephrasing, or switch to Server in Settings."
        }
    }
}

enum ParseFailure: LocalizedError {
    case unavailable(String)
    case model(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .model(let message): return message
        }
    }
}
