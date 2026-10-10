import Foundation

public enum HAError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case missingToken
    case unauthorized
    case http(status: Int)
    case invalidResponse
    case commandFailed(code: String, message: String)
    case disconnected

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That doesn't look like a valid Home Assistant address."
        case .missingToken:
            return "An access token is required."
        case .unauthorized:
            return "Home Assistant rejected the access token."
        case .http(let status):
            return "Home Assistant returned HTTP \(status)."
        case .invalidResponse:
            return "Received an unexpected response from Home Assistant."
        case .commandFailed(let code, let message):
            return "\(message) (\(code))"
        case .disconnected:
            return "The connection to Home Assistant was lost."
        }
    }
}
