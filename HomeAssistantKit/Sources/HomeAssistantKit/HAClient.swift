import Foundation

/// REST client for the Home Assistant HTTP API.
public struct HAClient: Sendable {
    public let config: HAServerConfig
    private let session: URLSession

    public init(config: HAServerConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// Verifies the server is reachable and the token is valid.
    @discardableResult
    public func checkConnection() async throws -> String {
        let response: [String: JSONValue] = try await get("")
        return response["message"]?.stringValue ?? "OK"
    }

    /// The instance's display name (`location_name`) and version.
    public func fetchConfig() async throws -> (name: String, version: String) {
        let response: [String: JSONValue] = try await get("config")
        return (
            response["location_name"]?.stringValue ?? "Home",
            response["version"]?.stringValue ?? ""
        )
    }

    public func fetchStates() async throws -> [HAEntity] {
        try await get("states")
    }

    public func callService(
        domain: String,
        service: String,
        entityId: String? = nil,
        data: [String: JSONValue] = [:]
    ) async throws {
        var body = data
        if let entityId {
            body["entity_id"] = .string(entityId)
        }
        var request = makeRequest(config.apiURL("services/\(domain)/\(service)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        _ = try await perform(request)
    }

    /// Fetches the latest still image from a camera entity.
    public func cameraSnapshot(entityId: String) async throws -> Data {
        try await perform(makeRequest(config.apiURL("camera_proxy/\(entityId)")))
    }

    /// Fetches arbitrary data from the server with authorization, e.g. an `entity_picture`.
    public func data(at path: String) async throws -> Data {
        guard let url = config.resolve(path) else { throw HAError.invalidURL }
        return try await perform(makeRequest(url))
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = path.isEmpty ? config.baseURL.appending(path: "api/") : config.apiURL(path)
        let data = try await perform(makeRequest(url))
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw HAError.invalidResponse
        }
    }

    private func makeRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer \(config.accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HAError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw HAError.unauthorized
        default: throw HAError.http(status: http.statusCode)
        }
    }
}
