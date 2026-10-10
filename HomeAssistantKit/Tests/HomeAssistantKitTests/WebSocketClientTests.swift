import Foundation
import Network
import Testing
@testable import HomeAssistantKit

/// A minimal in-process Home Assistant WebSocket server implementing the
/// auth handshake and the handful of commands the client uses.
private final class FakeHomeAssistant: @unchecked Sendable {
    static let token = "good-token"

    private let listener: NWListener
    private let queue = DispatchQueue(label: "FakeHomeAssistant")
    private var connections: [NWConnection] = []

    init() throws {
        let parameters = NWParameters.tcp
        let webSocket = NWProtocolWebSocket.Options()
        webSocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
        listener = try NWListener(using: parameters, on: .any)
    }

    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [self] connection in
            connections.append(connection)
            connection.start(queue: queue)
            send(["type": "auth_required", "ha_version": "2026.10.0"], on: connection)
            receive(on: connection)
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready: continuation.resume(returning: listener.port!.rawValue)
                case .failed(let error): continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        queue.sync {
            connections.forEach { $0.cancel() }
            listener.cancel()
        }
    }

    /// Drops all client connections, simulating a server restart.
    func dropConnections() {
        queue.sync { connections.forEach { $0.cancel() } }
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [self] data, _, _, error in
            guard error == nil, let data,
                  let message = try? JSONDecoder().decode(JSONValue.self, from: data)
            else { return }
            handle(message, on: connection)
            receive(on: connection)
        }
    }

    private func handle(_ message: JSONValue, on connection: NWConnection) {
        let id = message["id"] ?? .null
        func result(_ value: JSONValue) {
            send(["id": id, "type": "result", "success": true, "result": value], on: connection)
        }

        switch message["type"]?.stringValue {
        case "auth":
            let ok = message["access_token"]?.stringValue == Self.token
            send(["type": ok ? "auth_ok" : "auth_invalid"], on: connection)
        case "get_states":
            result([
                ["entity_id": "light.kitchen", "state": "off", "attributes": ["friendly_name": "Kitchen"]],
                ["entity_id": "sensor.temp", "state": "21.5", "attributes": ["unit_of_measurement": "°C"]],
            ])
        case "subscribe_events":
            result(.null)
            send([
                "id": id, "type": "event",
                "event": [
                    "event_type": "state_changed",
                    "data": [
                        "entity_id": "light.kitchen",
                        "new_state": ["entity_id": "light.kitchen", "state": "on", "attributes": [:]],
                    ],
                ],
            ], on: connection)
        case "config/area_registry/list":
            result([["area_id": "kitchen", "name": "Kitchen", "icon": .null]])
        case "config/device_registry/list":
            result([["id": "d1", "area_id": "kitchen"]])
        case "config/entity_registry/list":
            result([["entity_id": "light.kitchen", "device_id": "d1", "area_id": .null]])
        case "camera/stream":
            result(["url": "/api/hls/abc/master_playlist.m3u8"])
        default:
            send([
                "id": id, "type": "result", "success": false,
                "error": ["code": "unknown_command", "message": "Unknown command."],
            ], on: connection)
        }
    }

    private func send(_ value: JSONValue, on connection: NWConnection) {
        let data = try! JSONEncoder().encode(value)
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }
}

@Suite(.serialized) struct WebSocketClientTests {
    private func makeServer() async throws -> (FakeHomeAssistant, URL) {
        let server = try FakeHomeAssistant()
        let port = try await server.start()
        return (server, URL(string: "http://127.0.0.1:\(port)")!)
    }

    @Test func handshakeCommandsAndEvents() async throws {
        let (server, url) = try await makeServer()
        defer { server.stop() }

        let client = HAWebSocketClient(config: HAServerConfig(baseURL: url, accessToken: FakeHomeAssistant.token))
        try await client.connect()
        try await client.subscribeToStateChanges()

        let states = try await client.fetchStates()
        #expect(states.map(\.entityId) == ["light.kitchen", "sensor.temp"])

        let registry = try await client.fetchRegistry()
        #expect(registry.areas.map(\.name) == ["Kitchen"])
        #expect(registry.areaId(for: "light.kitchen") == "kitchen")

        let streamURL = try await client.cameraStreamURL(entityId: "camera.door")
        #expect(streamURL.absoluteString == "\(url.absoluteString)/api/hls/abc/master_playlist.m3u8")

        await #expect(throws: HAError.commandFailed(code: "unknown_command", message: "Unknown command.")) {
            try await client.send(command: "nope")
        }

        var iterator = client.stateChanges.makeAsyncIterator()
        let change = await iterator.next()
        #expect(change?.entityId == "light.kitchen")
        #expect(change?.newState?.state == "on")

        await client.close()
        #expect(await iterator.next() == nil)
    }

    @Test func rejectsBadToken() async throws {
        let (server, url) = try await makeServer()
        defer { server.stop() }

        let client = HAWebSocketClient(config: HAServerConfig(baseURL: url, accessToken: "wrong"))
        await #expect(throws: HAError.unauthorized) {
            try await client.connect()
        }
    }

    @Test func finishesStreamWhenServerDisconnects() async throws {
        let (server, url) = try await makeServer()
        defer { server.stop() }

        let client = HAWebSocketClient(config: HAServerConfig(baseURL: url, accessToken: FakeHomeAssistant.token))
        try await client.connect()
        server.dropConnections()

        for await _ in client.stateChanges {}
        await #expect(throws: HAError.disconnected) {
            try await client.fetchStates()
        }
    }
}
