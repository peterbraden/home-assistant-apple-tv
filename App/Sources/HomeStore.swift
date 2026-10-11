import Foundation
import HomeAssistantKit
import Observation
import TVServices

/// App-wide state: the connection to Home Assistant and the live entity states.
@MainActor
@Observable
final class HomeStore {
    enum Tab: Hashable {
        case rooms, dashboards, media, map, assist, devices, settings
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
    /// The category shown in the Devices tab.
    var selectedCategory: EntityCategory = .lights
    /// A transient error from a service call, shown as a banner.
    var actionError: String?
    /// Media playing on the Apple TV itself.
    let playback = MediaPlayback()
    /// Home Assistant's persistent notifications, by ID.
    private(set) var notifications: [String: HAPersistentNotification] = [:]
    /// A notification that arrived while the app was open, shown briefly as a banner.
    var notificationBanner: HAPersistentNotification?
    /// A doorbell that just rang.
    var doorbellAlert: DoorbellAlert?
    /// A camera shown full screen over everything, e.g. from the doorbell alert.
    var presentedCamera: EntitySelection?
    /// Folders open in the Media tab.
    var mediaPath: [MediaLocation] = []
    private var ranLaunchActions = false

    private var socket: HAWebSocketClient?
    /// What the Energy dashboard tracks; nil when it isn't set up.
    private(set) var energyPrefs: HAEnergyPrefs?
    /// Assist pipelines on the server and Home Assistant's preferred one.
    private(set) var assistPipelines: [HAAssistPipeline] = []
    private(set) var preferredAssistPipeline: HAAssistPipeline?
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
        playback.stop()
        CredentialStore.delete()
        config = nil
        entities = [:]
        registry = .empty
        dashboards = []
        assistPipelines = []
        preferredAssistPipeline = nil
        energyPrefs = nil
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
                // Optional: only admins can subscribe to notifications.
                if let events = try? await socket.subscribe("persistent_notification/subscribe") {
                    Task { await self.receiveNotifications(events) }
                }
                let states = try await socket.fetchStates()
                // Registries are optional: they need an admin user.
                let registry = (try? await socket.fetchRegistry()) ?? .empty
                let dashboards = await loadDashboards(from: socket)
                let pipelines = try? await socket.fetchPipelines()
                let energy = (try? await socket.fetchEnergyPrefs()).flatMap { $0.isEmpty ? nil : $0 }

                guard !Task.isCancelled else { await socket.close(); return }
                self.entities = Dictionary(states.map { ($0.entityId, $0) }, uniquingKeysWith: { _, new in new })
                self.registry = registry
                self.dashboards = dashboards
                self.assistPipelines = pipelines?.pipelines ?? []
                self.energyPrefs = energy
                self.preferredAssistPipeline = pipelines?.preferred
                if selectedTab == .rooms, rooms.isEmpty {
                    // Non-admin users have no Rooms tab.
                    selectedTab = dashboards.isEmpty && energy == nil ? .devices : .dashboards
                }
                self.socket = socket
                connectionState = .connected
                retryDelay = 2
                #if DEBUG
                if !ranLaunchActions {
                    ranLaunchActions = true
                    Task { await runDebugLaunchActions() }
                }
                #endif

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
        if let newState = change.newState, let old = entities[change.entityId],
           newState.domain == "event", newState.deviceClass == "doorbell",
           newState.state != old.state, !newState.isUnavailable, !old.isUnavailable {
            // An event entity's state is the time it last fired.
            doorbellAlert = DoorbellAlert(entityId: change.entityId, name: newState.friendlyName)
        }
        if let newState = change.newState {
            entities[change.entityId] = newState
        } else {
            entities.removeValue(forKey: change.entityId)
        }
    }

    private func receiveNotifications(_ events: AsyncStream<JSONValue>) async {
        for await event in events {
            let new = HAPersistentNotification.apply(event, to: &notifications)
            if let latest = new.last { notificationBanner = latest }
        }
    }

    var sortedNotifications: [HAPersistentNotification] {
        notifications.values.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    func dismissNotification(_ notification: HAPersistentNotification) {
        guard let client else { return }
        Task {
            do {
                try await client.callService(domain: "persistent_notification", service: "dismiss",
                                             data: ["notification_id": .string(notification.id)])
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    /// Locks that can be opened from the doorbell alert.
    var doorLocks: [HAEntity] {
        visibleEntities.filter { $0.domain == "lock" && !$0.isUnavailable }
    }

    var availableCameras: [HAEntity] {
        visibleEntities.filter { $0.domain == "camera" && !$0.isUnavailable }
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

    // MARK: - Assist

    /// The pipeline chosen in Settings, or Home Assistant's preferred one.
    var assistPipeline: HAAssistPipeline? {
        let chosen = UserDefaults.standard.string(forKey: "assistPipeline")
        return assistPipelines.first { $0.id == chosen } ?? preferredAssistPipeline
    }

    /// Sends a sentence to Assist using the agent and language of the chosen pipeline.
    func ask(_ text: String, conversationId: String?) async throws -> HAConversationResponse {
        guard let socket else { throw HAError.disconnected }
        let pipeline = assistPipeline
        // "*" means the agent accepts any language; let Home Assistant use its default.
        let language = pipeline?.language == "*" ? nil : pipeline?.language
        return try await socket.processConversation(
            text, conversationId: conversationId, agentId: pipeline?.conversationEngine, language: language)
    }

    func logbook(for entityId: String, since start: Date) async throws -> [HALogbookEntry] {
        guard let socket else { throw HAError.disconnected }
        return try await socket.fetchLogbook(entityIds: [entityId], start: start)
    }

    func forecast(for entityId: String) async throws -> [HAForecast] {
        guard let socket else { throw HAError.disconnected }
        return try await socket.fetchForecast(entityId: entityId)
    }

    // MARK: - Media

    func browseMedia(_ location: MediaLocation) async throws -> HAMediaItem {
        guard let socket else { throw HAError.disconnected }
        switch location {
        case .source(let contentId):
            return try await socket.browseMediaSource(contentId)
        case .player(let entityId, let contentId, let contentType):
            return try await socket.browseMedia(entityId: entityId, contentId: contentId, contentType: contentType)
        }
    }

    /// Media players that can be sent something to play.
    var mediaTargets: [HAEntity] {
        visibleEntities.filter {
            $0.domain == "media_player" && !$0.isUnavailable && $0.supports(HAFeature.MediaPlayer.playMedia)
        }
    }

    /// Media players with a library of their own to browse.
    var browsablePlayers: [HAEntity] {
        mediaTargets.filter { $0.supports(HAFeature.MediaPlayer.browseMedia) }
    }

    /// Asks a Home Assistant media player to play an item.
    func play(_ item: HAMediaItem, on player: HAEntity) {
        call("media_player", "play_media", on: player, data: [
            "media_content_id": .string(item.contentId),
            "media_content_type": .string(item.contentType),
        ])
    }

    /// Streams a media-source item on the Apple TV itself.
    func playHere(_ item: HAMediaItem) async {
        guard let socket, let config else { return }
        do {
            let media = try await socket.resolveMedia(item.contentId)
            guard let url = config.resolve(media.url) else { throw HAError.invalidURL }
            let kind = media.mimeType.isEmpty ? item.kind : HAMediaKind(mediaClass: item.mediaClass, contentType: media.mimeType)
            playback.play(url: url, title: item.title, kind: kind)
            if kind != .image, let thumbnail = item.thumbnail, let client,
               let artwork = try? await client.data(at: thumbnail) {
                playback.setArtwork(artwork)
            }
        } catch {
            actionError = "\(item.title): \(error.localizedDescription)"
        }
    }

    #if DEBUG
    /// Lets the simulator follow a link (`OPEN_URL`), open a media folder (`MEDIA_PATH`) or
    /// play a media-source ID on the Apple TV (`MEDIA_PLAY`, `MEDIA_TITLE`) without pressing
    /// select in UI tests or confirming the system's "Open in…" prompt.
    private func runDebugLaunchActions() async {
        let environment = ProcessInfo.processInfo.environment
        if let doorbell = environment["SIMULATE_DOORBELL"], let entity = entities[doorbell] {
            doorbellAlert = DoorbellAlert(entityId: doorbell, name: entity.friendlyName)
        }
        if let message = environment["SIMULATE_NOTIFICATION"] {
            notificationBanner = HAPersistentNotification([
                "notification_id": "debug", "title": "Test notification", "message": .string(message),
            ])
        }
        if let link = environment["OPEN_URL"].flatMap(URL.init(string:)) {
            open(link)
        }
        if let folder = environment["MEDIA_PATH"] {
            selectedTab = .media
            mediaPath = folder == "root" ? [] : [.source(folder)]
        }
        if let id = environment["MEDIA_PLAY"] {
            selectedTab = .media
            await playHere(HAMediaItem([
                "media_content_id": .string(id), "title": .string(environment["MEDIA_TITLE"] ?? id),
                "media_class": "music", "can_play": true,
            ]))
        }
    }
    #endif

    func cameraStreamURL(for entityId: String) async throws -> URL {
        guard let socket else { throw HAError.disconnected }
        return try await socket.cameraStreamURL(entityId: entityId)
    }

    // MARK: - Top Shelf

    /// Whether the Dashboards tab has anything to show: Lovelace dashboards or Energy.
    var hasDashboards: Bool { !dashboards.isEmpty || energyPrefs != nil }

    /// Dashboard views that the Top Shelf can show, as (id, title) pairs.
    var topShelfChoices: [(id: String, title: String)] {
        dashboards.flatMap { item in
            item.config.views.filter(DashboardSnapshot.hasGraphs).map {
                (id: "\(item.id)/\($0.id)", title: "\(item.dashboard.title) – \($0.title)")
            }
        }
    }

    /// An entity whose details are shown over everything, e.g. from a link.
    var presentedEntity: EntitySelection?

    /// Opens a `homeassistanttv://` link: `dashboards`, `media`, `map`, `assist`, `devices`,
    /// `settings`, `devices/<category>`, or `entity/<entity_id>` to show an entity's details.
    func open(_ url: URL) {
        guard url.scheme == SharedContainer.dashboardsURL.scheme else { return }
        switch url.host() {
        case "dashboards" where hasDashboards: selectedTab = .dashboards
        case "media": selectedTab = .media
        case "map" where !locatedEntities.isEmpty: selectedTab = .map
        case "assist": selectedTab = .assist
        case "devices":
            selectedTab = .devices
            if let category = EntityCategory(rawValue: url.lastPathComponent) { selectedCategory = category }
        case "settings": selectedTab = .settings
        case "entity":
            let id = url.lastPathComponent
            if entities[id] != nil { presentedEntity = EntitySelection(id: id) }
        default: break
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

    /// Visible entities whose name, ID or area matches `query`, best matches first.
    func search(_ query: String) -> [HAEntity] {
        guard !query.isEmpty else { return [] }
        let matches = visibleEntities.filter { entity in
            entity.friendlyName.localizedCaseInsensitiveContains(query)
                || entity.entityId.localizedCaseInsensitiveContains(query)
                || registry.areaName(for: entity.entityId)?.localizedCaseInsensitiveContains(query) == true
        }
        // Names that start with the query first, controllable entities before sensors.
        let ranked = matches.enumerated().sorted { a, b in
            func rank(_ entity: HAEntity) -> Int {
                (entity.friendlyName.lowercased().hasPrefix(query.lowercased()) ? 0 : 2)
                    + (entity.isControllable ? 0 : 1)
            }
            return (rank(a.element), a.offset) < (rank(b.element), b.offset)
        }
        return ranked.prefix(40).map(\.element)
    }

    /// Update entities with a new version waiting.
    var pendingUpdates: [HAEntity] {
        entities.values
            .filter { $0.domain == "update" && $0.state == "on" }
            .sorted { $0.friendlyName.localizedCaseInsensitiveCompare($1.friendlyName) == .orderedAscending }
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

struct DoorbellAlert: Identifiable, Equatable {
    let id = UUID()
    let entityId: String
    let name: String
    let time = Date()
}

/// A place in a media tree: Home Assistant's media sources, or a player's own library.
enum MediaLocation: Hashable {
    case source(String?)
    case player(entityId: String, contentId: String?, contentType: String?)
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
