import FeatherCore
import Foundation

extension LLMError {
    var localizedMessage: String {
        switch self {
        case .missingAPIKey:
            String(localized: "Add an API key in Settings.", bundle: .app)
        case .missingModel:
            String(localized: "Set a model in Settings.", bundle: .app)
        case .invalidBaseURL:
            String(localized: "The base URL in Settings is not valid.", bundle: .app)
        case .http(401, _):
            String(localized: "The provider rejected your sign-in or API key. Check it in Settings.", bundle: .app)
        case .http(429, nil):
            String(localized: "The provider is limiting requests right now. Wait a moment and try again.", bundle: .app)
        case .http(let status, _) where (500..<600).contains(status):
            String(localized: "The provider is having trouble right now (error \(status)). Try again in a moment.", bundle: .app)
        case .http(let status, let message):
            message.map { "\(status): \($0)" } ?? String(localized: "Request failed with status \(status).", bundle: .app)
        case .api(let message):
            message
        case .refused:
            String(localized: "The model declined this request.", bundle: .app)
        case .timedOut:
            String(localized: "The model took more than 1 minute to respond. Try again or choose a faster model in Settings.", bundle: .app)
        case .stalled:
            String(localized: "The reply stopped arriving. Try again.", bundle: .app)
        case .network:
            String(localized: "Feather could not reach the provider. Check your connection and try again.", bundle: .app)
        }
    }
}
