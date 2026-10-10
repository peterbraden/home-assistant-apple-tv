import HomeAssistantKit
import OSLog
import TVServices

private let logger = Logger(subsystem: "HomeAssistantTV", category: "TopShelf")

/// Supplies the Top Shelf: a full-screen image of a dashboard view's graphs,
/// shown when the app is highlighted in the top row of the home screen.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        Task { @MainActor in
            completionHandler(await Self.makeContent())
        }
    }

    @MainActor
    private static func makeContent() async -> TVTopShelfContent? {
        // nil falls back to the static Top Shelf image from the asset catalog.
        guard let config = CredentialStore.load() else {
            logger.notice("Not signed in; using the static Top Shelf image")
            return nil
        }

        let socket = HAWebSocketClient(config: config)
        defer { Task { await socket.close() } }
        do {
            try await socket.connect()
            var dashboards: [(dashboard: HADashboard, config: LovelaceConfig)] = []
            for dashboard in try await socket.fetchDashboards() {
                if let config = try? await socket.fetchDashboardConfig(urlPath: dashboard.urlPath), !config.isStrategy {
                    dashboards.append((dashboard, config))
                }
            }
            guard let choice = DashboardSnapshot.chooseView(in: dashboards, preference: SharedContainer.topShelfView)
            else {
                logger.notice("No dashboard view with graphs (\(dashboards.count) dashboards)")
                return nil
            }

            let snapshot = try await DashboardSnapshot.load(
                view: choice.view, dashboardTitle: choice.dashboard.title, socket: socket)
            guard !snapshot.graphs.isEmpty else {
                logger.notice("View \(choice.view.title) has no graph data")
                return nil
            }
            let url = try DashboardSnapshotView.render(snapshot)
            logger.notice("Rendered \(snapshot.graphs.count) graphs of \(choice.view.title) to \(url.lastPathComponent)")
            return carousel(imageURL: url, title: choice.view.title, context: choice.dashboard.title)
        } catch {
            logger.error("Couldn't build Top Shelf: \(error.localizedDescription)")
            // Show the last good picture rather than nothing while Home Assistant is unreachable.
            return DashboardSnapshotView.latestRender.map {
                carousel(imageURL: $0, title: "Home Assistant", context: "Last updated earlier")
            }
        }
    }

    private static func carousel(imageURL: URL, title: String, context: String) -> TVTopShelfContent {
        let item = TVTopShelfCarouselItem(identifier: "dashboard")
        item.title = title
        item.contextTitle = context
        item.setImageURL(imageURL, for: .screenScale1x)
        item.setImageURL(imageURL, for: .screenScale2x)
        item.displayAction = TVTopShelfAction(url: SharedContainer.dashboardsURL)
        return TVTopShelfCarouselContent(style: .details, items: [item])
    }
}
