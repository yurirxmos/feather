import Foundation

/// Feedback written in the app, sent to `feather-api`, which emails it to the team. It carries only
/// what the user types, plus the app and system versions; never screen context.
public enum Feedback {
    /// The longest message the server accepts, in UTF-16 code units as JavaScript counts them.
    public static let maxMessageLength = 5_000

    public enum Outcome: Equatable, Sendable {
        case sent
        /// The server rejected the message or the email address.
        case invalid
        /// Too much feedback from this network today.
        case rateLimited
        case failed
    }

    public static func request(base: String, message: String, email: String, appVersion: String, platform: String) throws -> URLRequest {
        var request = URLRequest(url: try .endpoint(base: base, path: "/v1/feedback"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = [
            "message": message.trimmingCharacters(in: .whitespacesAndNewlines),
            "app_version": appVersion,
            "platform": platform,
        ]
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.isEmpty { body["email"] = email }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    public static func outcome(status: Int) -> Outcome {
        switch status {
        case 200..<300: .sent
        case 400: .invalid
        case 429: .rateLimited
        default: .failed
        }
    }

    /// Whether the message can be sent: not blank and within the server's limit.
    public static func canSend(_ message: String) -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.utf16.count <= maxMessageLength
    }
}
