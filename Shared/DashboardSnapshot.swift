import Charts
import HomeAssistantKit
import SwiftUI

/// A full-screen picture of a dashboard view's graphs, used as the Top Shelf background.
struct DashboardSnapshot {
    struct Series: Identifiable {
        let name: String
        let points: [(time: Date, value: Double)]
        /// Min/max range shaded behind the line, for statistics with min and max.
        var band: [(time: Date, min: Double, max: Double)] = []
        var id: String { name }
    }

    struct Graph: Identifiable {
        let id: String
        let title: String
        let unit: String
        let series: [Series]
    }

    let dashboardTitle: String
    let viewTitle: String
    let graphs: [Graph]

    /// Most graphs drawn on one screen.
    static let maxGraphs = 2

    /// Card types the snapshot can draw.
    static func hasGraphs(_ view: LovelaceView) -> Bool {
        view.allCards.contains { ["history-graph", "statistics-graph", "sensor"].contains($0.type) }
    }

    /// The view chosen in Settings, or the first view with a graph.
    static func chooseView(
        in dashboards: [(dashboard: HADashboard, config: LovelaceConfig)], preference: String?
    ) -> (dashboard: HADashboard, view: LovelaceView)? {
        let candidates = dashboards.flatMap { item in
            item.config.views.filter(hasGraphs).map { (dashboard: item.dashboard, view: $0) }
        }
        if let preference,
           let match = candidates.first(where: { "\($0.dashboard.id)/\($0.view.id)" == preference }) {
            return match
        }
        return candidates.first
    }

    /// Fetches what's needed to draw `view`. Numeric sensors use 5-minute statistics
    /// rather than raw history: chatty sensors can record tens of thousands of states
    /// a day, too much for an extension's memory limit.
    static func load(
        view: LovelaceView, dashboardTitle: String, socket: HAWebSocketClient
    ) async throws -> DashboardSnapshot {
        let states = Dictionary(
            try await socket.fetchStates().map { ($0.entityId, $0) },
            uniquingKeysWith: { _, new in new }
        )
        let now = Date()
        var graphs: [Graph] = []

        for card in view.allCards.flatMap(flatten) where graphs.count < maxGraphs {
            switch card.type {
            case "history-graph", "sensor":
                let ids = card.type == "sensor" ? [card.entity].compactMap { $0 } : card.entities.map(\.entityId)
                let numeric = ids.filter { states[$0]?.unit != nil }
                guard !numeric.isEmpty else { continue }
                let hours = card.double("hours_to_show") ?? 24
                let start = now.addingTimeInterval(-hours * 3600)
                let points = try await numericSeries(numeric, since: start, socket: socket)

                // One graph per unit, as Home Assistant does.
                var units: [String] = []
                for id in numeric {
                    if let unit = states[id]?.unit, !units.contains(unit) { units.append(unit) }
                }
                for unit in units where graphs.count < maxGraphs {
                    let series = numeric
                        .filter { states[$0]?.unit == unit }
                        .compactMap { id -> Series? in
                            guard let values = points[id], !values.isEmpty else { return nil }
                            return Series(name: states[id]?.friendlyName ?? id, points: values)
                        }
                    guard !series.isEmpty else { continue }
                    let title = card.title ?? card.string("name") ?? series[0].name
                    graphs.append(Graph(
                        id: "\(card.id)-\(unit)",
                        title: units.count > 1 ? "\(title) (\(unit))" : title,
                        unit: unit,
                        series: series
                    ))
                }

            case "statistics-graph":
                let ids = card.entities.map(\.entityId)
                let period = card.string("period") ?? "hour"
                let days = card.double("days_to_show") ?? 30
                var types = card.strings("stat_types")
                if types.isEmpty { types = ["mean", "min", "max"] }
                let statistics = try await socket.fetchStatistics(
                    ids: ids, start: now.addingTimeInterval(-days * 86400), period: period, types: types)
                let primary = types.contains("mean") ? "mean" : types[0]
                let series = ids.compactMap { id -> Series? in
                    let rows = HADownsampler.statistics(statistics[id] ?? [], maxCount: 300)
                    let points = rows.compactMap { row in row.value(for: primary).map { (row.start, $0) } }
                    guard !points.isEmpty else { return nil }
                    let band = ids.count == 1 && types.contains("min") && types.contains("max")
                        ? rows.compactMap { row in row.min.flatMap { min in row.max.map { (row.start, min, $0) } } }
                        : []
                    return Series(name: states[id]?.friendlyName ?? id, points: points, band: band)
                }
                guard !series.isEmpty else { continue }
                graphs.append(Graph(
                    id: card.id,
                    title: card.title ?? series[0].name,
                    unit: ids.lazy.compactMap { states[$0]?.unit }.first ?? "",
                    series: series
                ))

            default:
                continue
            }
        }

        return DashboardSnapshot(dashboardTitle: dashboardTitle, viewTitle: view.title, graphs: graphs)
    }

    private static func flatten(_ card: LovelaceCard) -> [LovelaceCard] {
        card.cards.isEmpty ? [card] : card.cards.flatMap(flatten)
    }

    /// 5-minute mean statistics per entity, falling back to downsampled history
    /// for entities without statistics.
    private static func numericSeries(
        _ ids: [String], since start: Date, socket: HAWebSocketClient
    ) async throws -> [String: [(time: Date, value: Double)]] {
        let statistics = try await socket.fetchStatistics(ids: ids, start: start, period: "5minute", types: ["mean"])
        var result: [String: [(time: Date, value: Double)]] = [:]
        for id in ids {
            let points = (statistics[id] ?? []).compactMap { row in row.mean.map { (row.start, $0) } }
            if !points.isEmpty {
                result[id] = HADownsampler.numeric(
                    points.map { HAHistoryPoint(time: $0.0, state: String($0.1)) }, maxCount: 300)
            }
        }
        let missing = ids.filter { result[$0] == nil }
        if !missing.isEmpty {
            let history = try await socket.fetchHistory(entityIds: missing, start: start)
            for id in missing {
                result[id] = HADownsampler.numeric(history[id] ?? [], maxCount: 300)
            }
        }
        return result
    }
}

/// Draws a snapshot at 1920×1080. On the Home screen the row of apps and the
/// "swipe up" hint cover the lower part, so the graphs stay in the top ~60%.
struct DashboardSnapshotView: View {
    let snapshot: DashboardSnapshot

    static let size = CGSize(width: 1920, height: 1080)

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.10, blue: 0.20), Color(red: 0.05, green: 0.20, blue: 0.38)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            HStack(alignment: .top, spacing: 70) {
                ForEach(snapshot.graphs) { graph in
                    VStack(alignment: .leading, spacing: 24) {
                        Text(graph.title)
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        chart(graph)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 110)
            .padding(.top, 110)
            .frame(height: 640, alignment: .top)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .dark)
    }

    private func chart(_ graph: DashboardSnapshot.Graph) -> some View {
        Chart {
            ForEach(graph.series) { series in
                ForEach(series.band, id: \.time) { point in
                    AreaMark(
                        x: .value("Time", point.time),
                        yStart: .value("Min", point.min),
                        yEnd: .value("Max", point.max)
                    )
                    .foregroundStyle(.cyan.opacity(0.2))
                }
                ForEach(series.points, id: \.time) { point in
                    LineMark(
                        x: .value("Time", point.time),
                        y: .value(graph.unit, point.value),
                        series: .value("Entity", series.name)
                    )
                    .foregroundStyle(by: .value("Entity", series.name))
                    .lineStyle(StrokeStyle(lineWidth: 4))
                    .interpolationMethod(.monotone)
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel(graph.unit)
        .chartLegend(graph.series.count > 1 ? .visible : .hidden)
        .chartLegend(position: .bottom, alignment: .leading)
        .font(.system(size: 24))
        .frame(maxHeight: .infinity)
    }

    /// Renders the snapshot to a PNG file in the shared container, replacing older ones.
    @MainActor
    static func render(_ snapshot: DashboardSnapshot) throws -> URL {
        let renderer = ImageRenderer(content: DashboardSnapshotView(snapshot: snapshot))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else { throw CocoaError(.fileWriteUnknown) }

        let directory = SharedContainer.directory.appendingPathComponent("TopShelf", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A new name each time, so the system doesn't show a cached image.
        let url = directory.appendingPathComponent("snapshot-\(Int(Date().timeIntervalSince1970)).png")
        try data.write(to: url, options: .atomic)
        for old in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        where old != url {
            try? FileManager.default.removeItem(at: old)
        }
        return url
    }

    /// The most recently rendered snapshot, if any.
    static var latestRender: URL? {
        let directory = SharedContainer.directory.appendingPathComponent("TopShelf", isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "png" }
            .max { $0.lastPathComponent < $1.lastPathComponent }
    }
}
