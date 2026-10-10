import Foundation
import HomeAssistantKit
import Observation
import TVServices

/// App-wide state: the connection to Home Assistant and the live entity states.
@MainActor
@Observable
final class HomeStore {
    enum Tab: Hashable {
        case rooms, dashboards, settings
        case category(EntityCategory)
    }

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
    /// Dashboards with a stored layout. Auto-generated and strategy dashboards are left out.
    private(set) var dashboards: [LoadedDashboard] = []
    private(set) var locationName = "Home"
    private(set) var serverVersion = ""
    var selectedTab: Tab = .rooms
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
        TVTopShelfContentProvider.topShelfContentDidChange()
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
        dashboards = []
        connectionState = .signedOut
        TVTopShelfContentProvider.topShelfContentDidChange()
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
                let dashboards = await loadDashboards(from: socket)

                guard !Task.isCancelled else { await socket.close(); return }
                self.entities = Dictionary(states.map { ($0.entityId, $0) }, uniquingKeysWith: { _, new in new })
                self.registry = registry
                self.dashboards = dashboards
                if selectedTab == .rooms, rooms.isEmpty {
                    // Non-admin users have no Rooms tab.
                    selectedTab = dashboards.isEmpty ? (tabCategories.first.map(Tab.category) ?? .settings) : .dashboards
                }
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

    private func loadDashboards(from socket: HAWebSocketClient) async -> [LoadedDashboard] {
        guard let list = try? await socket.fetchDashboards() else { return [] }
        var loaded: [LoadedDashboard] = []
        for dashboard in list {
            // Fails with config_not_found for dashboards HA generates automatically.
            guard let config = try? await socket.fetchDashboardConfig(urlPath: dashboard.urlPath),
                  !config.isStrategy, !config.views.isEmpty
            else { continue }
            loaded.append(LoadedDashboard(dashboard: dashboard, config: config))
        }
        return loaded
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

    /// Runs the entity's one-click action (toggle, run scene). Returns false when
    /// it has none, in which case the caller should show details instead.
    @discardableResult
    func performPrimaryAction(on entity: HAEntity) -> Bool {
        guard case .service(let domain, let service) = entity.primaryAction, !entity.isUnavailable else {
            return false
        }
        call(domain, service, on: entity)
        return true
    }

    // MARK: - History

    func history(for entityIds: [String], since start: Date) async throws -> [String: [HAHistoryPoint]] {
        guard let socket else { throw HAError.disconnected }
        return try await socket.fetchHistory(entityIds: entityIds, start: start)
    }

    func statistics(
        for ids: [String], since start: Date, period: String, types: [String]
    ) async throws -> [String: [HAStatisticPoint]] {
        guard let socket else { throw HAError.disconnected }
        return try await socket.fetchStatistics(ids: ids, start: start, period: period, types: types)
    }

    func statistic(for id: String, period: JSONValue?, types: [String]) async throws -> [String: Double] {
        guard let socket else { throw HAError.disconnected }
        return try await socket.fetchStatistic(id: id, period: period, types: types)
    }

    func cameraStreamURL(for entityId: String) async throws -> URL {
        guard let socket else { throw HAError.disconnected }
        return try await socket.cameraStreamURL(entityId: entityId)
    }

    // MARK: - Top Shelf

    /// Dashboard views that the Top Shelf can show, as (id, title) pairs.
    var topShelfChoices: [(id: String, title: String)] {
        dashboards.flatMap { item in
            item.config.views.filter(DashboardSnapshot.hasGraphs).map {
                (id: "\(item.id)/\($0.id)", title: "\(item.dashboard.title) – \($0.title)")
            }
        }
    }

    /// Opens a URL from the Top Shelf.
    func open(_ url: URL) {
        if url == SharedContainer.dashboardsURL, !dashboards.isEmpty {
            selectedTab = .dashboards
        }
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
    /// the rest, so Rooms, Dashboards, the categories and Settings must fit within that.
    var tabCategories: [EntityCategory] {
        var categories = availableCategories
        let limit = 7 - 1 - (rooms.isEmpty ? 0 : 1) - (dashboards.isEmpty ? 0 : 1)
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

struct LoadedDashboard: Identifiable {
    let dashboard: HADashboard
    let config: LovelaceConfig
    var id: String { dashboard.id }
}

struct EntitySection: Identifiable {
    let id: String
    let title: String
    let entities: [HAEntity]
}
