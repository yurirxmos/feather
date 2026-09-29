import Foundation

/// Fetches the models available to the current OpenCode Go API key.
public enum OpenCodeGoModelCatalog {
    public static func sortedUniqueModels(_ models: [String], including selectedModel: String? = nil) -> [String] {
        Array(Set(models + [selectedModel].compactMap { $0 })).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    public static func fetchModels(
        apiKey: String,
        baseURL: String = OpenCodeGoProvider.defaultBaseURL
    ) async throws -> [String] {
        var request = URLRequest(url: try .endpoint(base: baseURL, path: "/models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(OpenCodeGoProvider.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.api(message: "The models request did not return an HTTP response.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw LLMError.http(status: http.statusCode, message: String(data: data, encoding: .utf8))
        }
        return try decodeModels(data)
    }

    static func decodeModels(_ data: Data) throws -> [String] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        return sortedUniqueModels(response.data.map(\.id))
    }

    private struct Response: Decodable {
        let data: [Model]
    }

    private struct Model: Decodable {
        let id: String
    }
}
