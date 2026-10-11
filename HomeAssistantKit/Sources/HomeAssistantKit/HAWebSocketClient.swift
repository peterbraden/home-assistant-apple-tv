import Foundation

/// A `state_changed` event. `newState` is nil when the entity was removed.
public struct HAStateChange: Sendable, Hashable {
    public let entityId: String
    public let newState: HAEntity?

    public init(entityId: String, newState: HAEntity?) {
        self.entityId = entityId
        self.newState = newState
    }

    /// Parses the `event.data` payload of a `state_changed` event.
    public init?(eventData: JSONValue) {
        guard let entityId = eventData["entity_id"]?.stringValue else { return nil }
        self.entityId = entityId
        if let newState = eventData["new_state"], newState != .null {
            self.newState = try? newState.decode(as: HAEntity.self)
        } else {
            self.newState = nil
        }
    }
}

/// A single connection to the Home Assistant WebSocket API.
///
/// Instances are one-shot: once the socket drops, `stateChanges` finishes and
/// a new client should be created to reconnect.
public actor HAWebSocketClient {
    public nonisolated let config: HAServerConfig
    public nonisolated let stateChanges: AsyncStream<HAStateChange>

    private let session: URLSession
    private let stateContinuation: AsyncStream<HAStateChange>.Continuation
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var stateSubscriptionID: Int?
    /// Other subscriptions, by command ID: each gets its events' payloads.
    private var subscriptions: [Int: AsyncStream<JSONValue>.Continuation] = [:]
    private var isClosed = false
    /// The most recent outgoing send. Each send waits for the previous one so
    /// messages leave in ID order; Home Assistant rejects IDs that go backwards.
    private var lastSend: Task<Void, Never>?

    public init(config: HAServerConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
        (stateChanges, stateContinuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    /// Opens the socket and performs the authentication handshake.
    public func connect() async throws {
        let task = session.webSocketTask(with: config.webSocketURL)
        self.task = task
        task.resume()

        do {
            let hello = try await receiveMessage(on: task)
            guard hello["type"]?.stringValue == "auth_required" else { throw HAError.invalidResponse }

            try await send(["type": "auth", "access_token": .string(config.accessToken)], on: task)

            let auth = try await receiveMessage(on: task)
            switch auth["type"]?.stringValue {
            case "auth_ok": break
            case "auth_invalid": throw HAError.unauthorized
            default: throw HAError.invalidResponse
            }
        } catch {
            close()
            throw error
        }

        receiveTask = Task { [weak self] in
            await self?.receiveLoop(on: task)
        }
    }

    public func close() {
        guard !isClosed else { return }
        isClosed = true
        receiveTask?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        for continuation in pending.values {
            continuation.resume(throwing: HAError.disconnected)
        }
        pending.removeAll()
        stateContinuation.finish()
        subscriptions.values.forEach { $0.finish() }
        subscriptions.removeAll()
    }

    /// Sends a command and returns its `result` payload.
    @discardableResult
    public func send(command type: String, _ fields: [String: JSONValue] = [:]) async throws -> JSONValue {
        guard let task, !isClosed else { throw HAError.disconnected }
        let id = nextID
        nextID += 1

        var message = fields
        message["id"] = .number(Double(id))
        message["type"] = .string(type)
        let payload = JSONValue.object(message)

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            let previous = lastSend
            lastSend = Task {
                await previous?.value
                do {
                    try await self.send(payload, on: task)
                } catch {
                    self.fail(id: id, error: error)
                }
            }
        }
    }

    public func subscribeToStateChanges() async throws {
        guard stateSubscriptionID == nil else { return }
        stateSubscriptionID = nextID
        do {
            try await send(command: "subscribe_events", ["event_type": "state_changed"])
        } catch {
            stateSubscriptionID = nil
            throw error
        }
    }

    /// Runs a subscription command (e.g. `persistent_notification/subscribe`) and
    /// returns the `event` payloads it sends. The stream ends when the connection closes.
    public func subscribe(_ type: String, _ fields: [String: JSONValue] = [:]) async throws -> AsyncStream<JSONValue> {
        // Register before sending, so an event that follows the result straight away isn't lost.
        let id = nextID
        let (stream, continuation) = AsyncStream<JSONValue>.makeStream(bufferingPolicy: .unbounded)
        subscriptions[id] = continuation
        do {
            try await send(command: type, fields)
        } catch {
            subscriptions.removeValue(forKey: id)?.finish()
            throw error
        }
        return stream
    }

    public func fetchStates() async throws -> [HAEntity] {
        try await send(command: "get_states").decode(as: [HAEntity].self)
    }

    public func fetchRegistry() async throws -> HARegistry {
        async let areas = send(command: "config/area_registry/list")
        async let devices = send(command: "config/device_registry/list")
        async let entities = send(command: "config/entity_registry/list")
        return HARegistry(
            areas: try await areas.decode(),
            devices: try await devices.decode(),
            entities: try await entities.decode()
        )
    }

    /// Lovelace dashboards visible to this user, default first.
    public func fetchDashboards() async throws -> [HADashboard] {
        HADashboard.fromPanels(try await send(command: "get_panels"))
    }

    /// The stored configuration of a dashboard. Throws `commandFailed("config_not_found")`
    /// for dashboards that Home Assistant generates automatically.
    public func fetchDashboardConfig(urlPath: String?) async throws -> LovelaceConfig {
        var fields: [String: JSONValue] = [:]
        if let urlPath { fields["url_path"] = .string(urlPath) }
        return LovelaceConfig(try await send(command: "lovelace/config", fields))
    }

    public func fetchHistory(entityIds: [String], start: Date, end: Date? = nil) async throws -> [String: [HAHistoryPoint]] {
        var fields: [String: JSONValue] = [
            "start_time": .string(HAHistoryParser.isoString(start)),
            "entity_ids": .array(entityIds.map { .string($0) }),
            "minimal_response": true,
            "no_attributes": true,
            "significant_changes_only": false,
        ]
        if let end { fields["end_time"] = .string(HAHistoryParser.isoString(end)) }
        return HAHistoryParser.history(try await send(command: "history/history_during_period", fields))
    }

    /// Long-term statistics, aggregated per `period` (`5minute`, `hour`, `day`, `week`, `month`).
    public func fetchStatistics(
        ids: [String], start: Date, end: Date? = nil, period: String, types: [String]
    ) async throws -> [String: [HAStatisticPoint]] {
        var fields: [String: JSONValue] = [
            "start_time": .string(HAHistoryParser.isoString(start)),
            "statistic_ids": .array(ids.map { .string($0) }),
            "period": .string(period),
            "types": .array(types.map { .string($0) }),
        ]
        if let end { fields["end_time"] = .string(HAHistoryParser.isoString(end)) }
        return HAHistoryParser.statistics(try await send(command: "recorder/statistics_during_period", fields))
    }

    /// A single aggregate over a period, as shown by the `statistic` card.
    /// `period` is the card's period object, e.g. `{"calendar": {"period": "year"}}`.
    public func fetchStatistic(id: String, period: JSONValue?, types: [String]) async throws -> [String: Double] {
        var fields = period?.objectValue ?? ["calendar": ["period": "day"]]
        fields["statistic_id"] = .string(id)
        fields["types"] = .array(types.map { .string($0) })
        let result = try await send(command: "recorder/statistic_during_period", fields)
        return (result.objectValue ?? [:]).compactMapValues(\.doubleValue)
    }

    /// Requests an HLS stream for a camera. Requires the `stream` integration.
    /// All Assist pipelines, and the one chosen as preferred in Home Assistant's voice settings.
    public func fetchPipelines() async throws -> (pipelines: [HAAssistPipeline], preferred: HAAssistPipeline?) {
        let result = try await send(command: "assist_pipeline/pipeline/list")
        return (HAAssistPipeline.all(from: result), HAAssistPipeline.preferred(from: result))
    }

    /// Sends a sentence to Assist, which may run actions or answer a question.
    public func processConversation(
        _ text: String, conversationId: String? = nil, agentId: String? = nil, language: String? = nil
    ) async throws -> HAConversationResponse {
        var fields: [String: JSONValue] = ["text": .string(text)]
        if let conversationId { fields["conversation_id"] = .string(conversationId) }
        if let agentId { fields["agent_id"] = .string(agentId) }
        if let language { fields["language"] = .string(language) }
        return HAConversationResponse(try await send(command: "conversation/process", fields))
    }

    public func fetchEnergyPrefs() async throws -> HAEnergyPrefs {
        HAEnergyPrefs(try await send(command: "energy/get_prefs"))
    }

    /// Logbook entries for the given entities, oldest first.
    public func fetchLogbook(entityIds: [String], start: Date) async throws -> [HALogbookEntry] {
        HALogbookEntry.list(from: try await send(command: "logbook/get_events", [
            "start_time": .string(HAHistoryParser.isoString(start)),
            "entity_ids": .array(entityIds.map { .string($0) }),
        ]))
    }

    /// The weather entity's forecast; `type` is "daily", "hourly" or "twice_daily".
    /// Uses the read-only `weather.get_forecasts` action.
    public func fetchForecast(entityId: String, type: String = "daily") async throws -> [HAForecast] {
        let result = try await send(command: "call_service", [
            "domain": "weather",
            "service": "get_forecasts",
            "service_data": ["type": .string(type)],
            "target": ["entity_id": .string(entityId)],
            "return_response": true,
        ])
        return HAForecast.list(from: result["response"] ?? .null, entityId: entityId)
    }

    /// Browses media sources (local media, radio, cameras, Jellyfin…). nil is the root.
    public func browseMediaSource(_ contentId: String?) async throws -> HAMediaItem {
        var fields: [String: JSONValue] = [:]
        if let contentId { fields["media_content_id"] = .string(contentId) }
        return HAMediaItem(try await send(command: "media_source/browse_media", fields))
    }

    /// Browses what a media player can play. nil ID and type are the player's root.
    public func browseMedia(
        entityId: String, contentId: String? = nil, contentType: String? = nil
    ) async throws -> HAMediaItem {
        var fields: [String: JSONValue] = ["entity_id": .string(entityId)]
        if let contentId, let contentType {
            fields["media_content_id"] = .string(contentId)
            fields["media_content_type"] = .string(contentType)
        }
        return HAMediaItem(try await send(command: "media_player/browse_media", fields))
    }

    /// Turns a media-source ID into a URL that can be streamed directly.
    public func resolveMedia(_ contentId: String) async throws -> HAResolvedMedia {
        guard let media = HAResolvedMedia(try await send(command: "media_source/resolve_media",
                                                         ["media_content_id": .string(contentId)]))
        else { throw HAError.invalidResponse }
        return media
    }

    public func cameraStreamURL(entityId: String) async throws -> URL {
        let result = try await send(command: "camera/stream", ["entity_id": .string(entityId)])
        guard let path = result["url"]?.stringValue, let url = config.resolve(path) else {
            throw HAError.invalidResponse
        }
        return url
    }

    // MARK: - Private

    private func fail(id: Int, error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func receiveLoop(on task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await receiveMessage(on: task)
                handle(message)
            } catch {
                break
            }
        }
        close()
    }

    private func handle(_ message: JSONValue) {
        let id = message["id"]?.intValue
        switch message["type"]?.stringValue {
        case "result":
            guard let id, let continuation = pending.removeValue(forKey: id) else { return }
            if message["success"]?.boolValue == true {
                continuation.resume(returning: message["result"] ?? .null)
            } else {
                let error = message["error"]
                continuation.resume(throwing: HAError.commandFailed(
                    code: error?["code"]?.stringValue ?? "unknown",
                    message: error?["message"]?.stringValue ?? "Command failed"
                ))
            }
        case "event":
            if let id, let subscription = subscriptions[id] {
                subscription.yield(message["event"] ?? .null)
                return
            }
            guard id == stateSubscriptionID,
                  let data = message["event"]?["data"],
                  let change = HAStateChange(eventData: data)
            else { return }
            stateContinuation.yield(change)
        default:
            break
        }
    }

    private func send(_ value: JSONValue, on task: URLSessionWebSocketTask) async throws {
        let data = try JSONEncoder().encode(value)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func receiveMessage(on task: URLSessionWebSocketTask) async throws -> JSONValue {
        let data: Data
        switch try await task.receive() {
        case .string(let text): data = Data(text.utf8)
        case .data(let bytes): data = bytes
        @unknown default: throw HAError.invalidResponse
        }
        return try JSONValue(jsonData: data)
    }
}
