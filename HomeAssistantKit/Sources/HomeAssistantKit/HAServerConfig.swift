import Foundation

/// Connection details for a Home Assistant instance.
public struct HAServerConfig: Codable, Hashable, Sendable {
    public var baseURL: URL
    public var accessToken: String

    public init(baseURL: URL, accessToken: String) {
        self.baseURL = baseURL
        self.accessToken = accessToken
    }

    /// Builds a config from loosely-typed user input such as `homeassistant.local:8123`.
    public init(address: String, accessToken: String) throws {
        guard let url = Self.normalizedURL(from: address) else {
            throw HAError.invalidURL
        }
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw HAError.missingToken }
        self.init(baseURL: url, accessToken: token)
    }

    /// Adds a scheme and default port where missing and strips trailing paths like `/lovelace`.
    public static func normalizedURL(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "http://" + text
        }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }

        components.scheme = scheme
        // Plain `http://host` without a port almost always means the default HA port.
        if components.port == nil && scheme == "http" && !input.contains("://") {
            components.port = 8123
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    public func apiURL(_ path: String) -> URL {
        baseURL.appending(path: "api").appending(path: path)
    }

    /// Resolves a path such as an `entity_picture` (`/api/media_player_proxy/...`) against the server.
    public func resolve(_ path: String) -> URL? {
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    public var webSocketURL: URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components.path = "/api/websocket"
        return components.url!
    }
}
