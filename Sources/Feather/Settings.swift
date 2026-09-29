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
        case .http(let status, let message):
            message.map { "\(status): \($0)" } ?? String(localized: "Request failed with status \(status).", bundle: .app)
        case .api(let message):
            message
        case .refused:
            String(localized: "The model declined this request.", bundle: .app)
        case .timedOut:
            String(localized: "The model took more than 1 minute to respond. Try again or choose a faster model in Settings.", bundle: .app)
        }
    }
}
