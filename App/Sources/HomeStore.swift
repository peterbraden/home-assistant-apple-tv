import Foundation
import HomeAssistantKit
import Observation

/// App-wide state: the connection to Home Assistant and the live entity states.
@MainActor
@Observable
final class HomeStore {
    enum ConnectionState: Equatable {
        case signedOut
        case connecting
        case connected
        case reconnecting(String)
        case failed(String)
    }

    private(set) var config: HAServerConfig?
    private(set) var connectionState: ConnectionState = .signedOut
    private(set) var entities: [String: HAEntity] = [:]
    private(set) var registry: HARegistry = .empty
    private(set) var locationName = "Home"
    private(set) var serverVersion = ""
    /// A transient error from a service call, shown as a banner.
    var actionError: String?

    private var socket: HAWebSocketClient?
    private var liveTask: Task<Void, Never>?

    var client: HAClient? { config.map { HAClient(config: $0) } }

    init() {
        config = CredentialStore.load()
        if config != nil {
            connect()
        }
    }

    // MARK: - Session

    func signIn(with config: HAServerConfig) async throws {
        let client = HAClient(config: config)
        try await client.checkConnection()
        CredentialStore.save(config)
        self.config = config
        connect()
    }

    func signOut() {
        liveTask?.cancel()
        liveTask = nil
        Task { [socket] in await socket?.close() }
        socket = nil
        CredentialStore.delete()
        config = nil
        entities = [:]
        registry = .empty
        connectionState = .signedOut
    }

    /// Reconnects if the socket was dropped, e.g. after the app returns from the background.
    func resumeIfNeeded() {
        guard config != nil else { return }
        switch connectionState {
        case .connected, .connecting: return
        default: connect()
        }
    }

    func connect() {
        liveTask?.cancel()
        liveTask = Task { await runLiveUpdates() }
    }

    private func runLiveUpdates() async {
        var retryDelay = 2
        while !Task.isCancelled, let config {
            let socket = HAWebSocketClient(config: config)
            if case .reconnecting = connectionState {} else { connectionState = .connecting }
            do {
                try await socket.connect()
                // Subscribe before fetching so no changes are missed in between.
                try await socket.subscribeToStateChanges()
                let states = try await socket.fetchStates()
                // Registries are optional: they need an admin user.
                let registry = (try? await socket.fetchRegistry()) ?? .empty

                guard !Task.isCancelled else { await socket.close(); return }
                self.entities = Dictionary(states.map { ($0.entityId, $0) }, uniquingKeysWith: { _, new in new })
                self.registry = registry
                self.socket = socket
                connectionState = .connected
                retryDelay = 2

                if let info = try? await HAClient(config: config).fetchConfig() {
                    locationName = info.name
                    serverVersion = info.version
                }

                for await change in socket.stateChanges {
                    apply(change)
                }
                guard !Task.isCancelled else { return }
                connectionState = .reconnecting(HAError.disconnected.localizedDescription)
            } catch HAError.unauthorized {
                await socket.close()
                connectionState = .failed(HAError.unauthorized.localizedDescription)
                return
            } catch {
                await socket.close()
                guard !Task.isCancelled else { return }
                connectionState = .reconnecting(error.localizedDescription)
            }

            self.socket = nil
            try? await Task.sleep(for: .seconds(retryDelay))
            retryDelay = min(retryDelay * 2, 30)
        }
    }

    private func apply(_ change: HAStateChange) {
        if let newState = change.newState {
            entities[change.entityId] = newState
        } else {
            entities.removeValue(forKey: change.entityId)
        }
    }

    // MARK: - Actions

    func call(_ domain: String, _ service: String, on entity: HAEntity, data: [String: JSONValue] = [:]) {
        guard let client else { return }
        Task {
            do {
                try await client.callService(domain: domain, service: service, entityId: entity.entityId, data: data)
            } catch {
                actionError = "\(entity.friendlyName): \(error.localizedDescription)"
            }
        }
    }

    func cameraStreamURL(for entityId: String) async throws -> URL {
        guard let socket else { throw HAError.disconnected }
        return try await socket.cameraStreamURL(entityId: entityId)
    }

    // MARK: - Queries

    private var visibleEntities: [HAEntity] {
        entities.values
            .filter { !registry.isHidden($0.entityId) }
            .sorted { $0.friendlyName.localizedCaseInsensitiveCompare($1.friendlyName) == .orderedAscending }
    }

    var availableCategories: [EntityCategory] {
        let present = Set(visibleEntities.compactMap(\.category))
        return EntityCategory.allCases.filter(present.contains)
    }

    /// Categories to show as tabs. tvOS shows at most 7 tabs and silently drops
    /// the rest, so Rooms, the categories and Settings must fit within that.
    var tabCategories: [EntityCategory] {
        var categories = availableCategories
        let limit = 7 - 1 - (rooms.isEmpty ? 0 : 1)
        if categories.count > limit, !rooms.isEmpty {
            // Scenes also appear in their rooms, so they're the first to go.
            categories.removeAll { $0 == .scenes }
        }
        return Array(categories.prefix(limit))
    }

    func entities(in category: EntityCategory) -> [HAEntity] {
        visibleEntities.filter { $0.category == category }
    }

    /// Controllable entities grouped by area, in area order.
    var rooms: [EntitySection] {
        sections(for: visibleEntities.filter(\.isControllable), includeUnassigned: false)
    }

    /// Groups entities by area, with unassigned entities in a trailing "Other" section.
    func sections(for entities: [HAEntity], includeUnassigned: Bool = true) -> [EntitySection] {
        let grouped = Dictionary(grouping: entities) { registry.areaId(for: $0.entityId) }
        var sections = registry.areas.compactMap { area -> EntitySection? in
            guard let members = grouped[area.areaId], !members.isEmpty else { return nil }
            return EntitySection(id: area.areaId, title: area.name, entities: members)
        }
        if includeUnassigned, let other = grouped[nil], !other.isEmpty {
            sections.append(EntitySection(id: "_other", title: sections.isEmpty ? "" : "Other", entities: other))
        }
        return sections
    }

    func entity(_ id: String) -> HAEntity? {
        entities[id]
    }
}

struct EntitySection: Identifiable {
    let id: String
    let title: String
    let entities: [HAEntity]
}
