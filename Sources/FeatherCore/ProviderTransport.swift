import Foundation

public enum ProviderTransport {
    public static let userAgent = "Feather/0.1.0"

    public static func request(
        endpoint: URL,
        token: String,
        sessionHeader: (name: String, value: String)?,
        extraHeaders: [String: String] = [:],
        body: [String: Any]
    ) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (name, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: name) }
        if let sessionHeader, !sessionHeader.value.isEmpty {
            request.setValue(sessionHeader.value, forHTTPHeaderField: sessionHeader.name)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    public static func errorMessage(from body: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return String(data: body, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 }
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let message = json["error"] as? String { return message }
        // ChatGPT's backend explains a rejected request in `detail`.
        return (json["message"] as? String) ?? (json["detail"] as? String)
    }

    public static func streamError(from data: Data) -> LLMError {
        let message = errorMessage(from: data)
        if let message { return .api(message: message) }
        return .api(message: "Unknown error")
    }
}
