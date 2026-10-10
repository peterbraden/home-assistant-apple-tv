import Charts
import HomeAssistantKit
import SwiftUI

/// Most points drawn per line; longer series are averaged into buckets.
private let maxPointsPerSeries = 300

/// Reloads `load` now and then every `interval` while the view is on screen.
private struct PeriodicLoad: ViewModifier {
    let interval: Duration
    let load: () async -> Void

    func body(content: Content) -> some View {
        content.task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: interval)
            }
        }
    }
}

private extension View {
    func reload(every interval: Duration, _ load: @escaping () async -> Void) -> some View {
        modifier(PeriodicLoad(interval: interval, load: load))
    }
}

/// Spinner / error / content switch shared by data-backed cards.
private struct LoadingState<Value, Content: View>: View {
    let value: Value?
    let error: String?
    let height: CGFloat
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        if let value {
            content(value)
        } else if let error {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: height)
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: height)
        }
    }
}

// MARK: - History graph

private struct LinePoint: Identifiable {
    let series: String
    let time: Date
    let value: Double
    var id: String { "\(series)-\(time.timeIntervalSince1970)" }
}

private struct TimelineSegment: Identifiable {
    let row: String
    let state: String
    let start: Date
    let end: Date
    var id: String { "\(row)-\(start.timeIntervalSince1970)" }
}

/// The `history-graph` card: a line chart per unit for numeric entities and a
/// timeline for everything else, as in Home Assistant.
struct HistoryGraphCard: View {
    let card: LovelaceCard
    let chartHeight: CGFloat

    @Environment(HomeStore.self) private var store
    @State private var history: [String: [HAHistoryPoint]]?
    @State private var error: String?
    @State private var loadedAt = Date()

    private var hours: Double { card.double("hours_to_show") ?? 24 }

    var body: some View {
        CardContainer(title: card.title) {
            LoadingState(value: history, error: error, height: chartHeight) { history in
                charts(history)
            }
        }
        .reload(every: .seconds(max(card.double("refresh_interval") ?? 60, 30))) { await load() }
    }

    private func load() async {
        let now = Date()
        do {
            history = try await store.history(
                for: card.entities.map(\.entityId), since: now.addingTimeInterval(-hours * 3600))
            loadedAt = now
            error = nil
        } catch {
            if history == nil { self.error = error.localizedDescription }
        }
    }

    @ViewBuilder
    private func charts(_ history: [String: [HAHistoryPoint]]) -> some View {
        let start = loadedAt.addingTimeInterval(-hours * 3600)
        let refs = card.entities
        let numeric = refs.filter { store.entity($0.entityId)?.unit != nil }
        let timeline = refs.filter { store.entity($0.entityId)?.unit == nil }
        let units = numeric.compactMap { store.entity($0.entityId)?.unit }.uniqued()

        VStack(alignment: .leading, spacing: 40) {
            ForEach(units, id: \.self) { unit in
                let points = numeric
                    .filter { store.entity($0.entityId)?.unit == unit }
                    .flatMap { linePoints(for: $0, history: history, until: loadedAt) }
                Chart(points) { point in
                    LineMark(x: .value("Time", point.time), y: .value(unit, point.value))
                        .foregroundStyle(by: .value("Entity", point.series))
                        .interpolationMethod(.stepEnd)
                }
                .chartXScale(domain: start...loadedAt)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel(unit)
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: chartHeight)
            }

            if !timeline.isEmpty {
                let bars = timeline.flatMap { segments(for: $0, history: history, from: start, until: loadedAt) }
                Chart(bars) { segment in
                    BarMark(
                        xStart: .value("Start", segment.start),
                        xEnd: .value("End", segment.end),
                        y: .value("Entity", segment.row)
                    )
                    .foregroundStyle(by: .value("State", segment.state))
                }
                .chartXScale(domain: start...loadedAt)
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: CGFloat(timeline.count) * 70 + 80)
            }
        }
    }

    private func name(of ref: LovelaceEntityRef) -> String {
        if let name = ref.name { return name }
        guard let entity = store.entity(ref.entityId) else { return ref.entityId }
        return entity.friendlyName
    }

    private func linePoints(for ref: LovelaceEntityRef, history: [String: [HAHistoryPoint]], until end: Date) -> [LinePoint] {
        let series = name(of: ref)
        var points = HADownsampler.numeric(history[ref.entityId] ?? [], maxCount: maxPointsPerSeries)
            .map { LinePoint(series: series, time: $0.time, value: $0.value) }
        // Carry the latest value to "now" so lines reach the right edge.
        if let last = points.last {
            points.append(LinePoint(series: series, time: end, value: last.value))
        }
        return points
    }

    private func segments(
        for ref: LovelaceEntityRef, history: [String: [HAHistoryPoint]], from start: Date, until end: Date
    ) -> [TimelineSegment] {
        let row = name(of: ref)
        let points = history[ref.entityId] ?? []
        return points.enumerated().map { index, point in
            let next = index + 1 < points.count ? points[index + 1].time : end
            return TimelineSegment(row: row, state: humanize(point.state), start: max(point.time, start), end: next)
        }
    }
}

// MARK: - Statistics graph

private struct StatisticPoint: Identifiable {
    let entity: String
    let type: String
    let time: Date
    let value: Double
    var id: String { "\(entity)-\(type)-\(time.timeIntervalSince1970)" }
}

/// The `statistics-graph` card: long-term statistics (mean/min/max or sums) per period.
struct StatisticsGraphCard: View {
    let card: LovelaceCard
    let chartHeight: CGFloat

    @Environment(HomeStore.self) private var store
    @State private var statistics: [String: [HAStatisticPoint]]?
    @State private var error: String?

    private var period: String { card.string("period") ?? "hour" }
    private var days: Double { card.double("days_to_show") ?? 30 }
    private var types: [String] {
        let types = card.strings("stat_types")
        return types.isEmpty ? ["mean", "min", "max"] : types
    }
    private var ids: [String] { card.entities.map(\.entityId) }

    var body: some View {
        CardContainer(title: card.title) {
            LoadingState(value: statistics, error: error, height: chartHeight) { statistics in
                chart(statistics)
            }
        }
        .reload(every: .seconds(period == "5minute" ? 300 : 900)) { await load() }
    }

    private func load() async {
        do {
            statistics = try await store.statistics(
                for: ids, since: Date().addingTimeInterval(-days * 86400), period: period, types: types)
            error = nil
        } catch {
            if statistics == nil { self.error = error.localizedDescription }
        }
    }

    @ViewBuilder
    private func chart(_ statistics: [String: [HAStatisticPoint]]) -> some View {
        let unit = ids.lazy.compactMap { store.entity($0)?.unit }.first ?? ""
        let series = ids.map { id in
            (id: id,
             name: store.entity(id)?.friendlyName ?? id,
             points: HADownsampler.statistics(statistics[id] ?? [], maxCount: maxPointsPerSeries))
        }
        let isBar = card.string("chart_type") == "bar"
        let points = series.flatMap { entry in
            types.flatMap { type in
                entry.points.compactMap { point in
                    point.value(for: type).map {
                        StatisticPoint(entity: entry.name, type: type, time: point.start, value: $0)
                    }
                }
            }
        }
        // With one entity, shade the min–max range behind the mean like Home Assistant.
        let band = series.count == 1 && types.contains("min") && types.contains("max") && !isBar
            ? series[0].points.filter { $0.min != nil && $0.max != nil } : []

        if points.isEmpty {
            Text("No statistics recorded for this period.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: chartHeight)
        } else {
            Chart {
                ForEach(band, id: \.start) { point in
                    AreaMark(
                        x: .value("Time", point.start),
                        yStart: .value("Min", point.min!),
                        yEnd: .value("Max", point.max!)
                    )
                    .foregroundStyle(.tint.opacity(0.2))
                }
                ForEach(points) { point in
                    if isBar {
                        BarMark(x: .value("Time", point.time), y: .value(unit, point.value))
                            .foregroundStyle(by: .value("Entity", point.entity))
                    } else {
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value(unit, point.value),
                            series: .value("Series", "\(point.entity) \(point.type)")
                        )
                        .foregroundStyle(by: .value("Entity", point.entity))
                        .lineStyle(point.type == "mean" || types.count == 1
                            ? StrokeStyle(lineWidth: 3)
                            : StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    }
                }
            }
            .chartYScale(domain: .automatic(includesZero: isBar))
            .chartYAxisLabel(unit)
            .chartLegend(series.count > 1 ? .visible : .hidden)
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: chartHeight)
        }
    }
}

// MARK: - Statistic

/// The `statistic` card: one aggregate value (e.g. this year's mean).
struct StatisticCard: View {
    let card: LovelaceCard

    @Environment(HomeStore.self) private var store
    @State private var value: Double?
    @State private var error: String?

    private var statType: String { card.string("stat_type") ?? "change" }

    var body: some View {
        let entity = card.entity.flatMap(store.entity)
        CardContainer(title: card.string("name") ?? entity?.friendlyName) {
            LoadingState(value: value, error: error, height: 90) { value in
                VStack(alignment: .leading, spacing: 8) {
                    Text(format(value) + (entity?.unit.map { unitSpacing($0) + $0 } ?? ""))
                        .font(.system(size: 64, weight: .light))
                    Text("\(humanize(statType)) · \(periodDescription)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .reload(every: .seconds(600)) { await load() }
    }

    private func load() async {
        guard let id = card.entity else { error = "No entity"; return }
        do {
            let result = try await store.statistic(for: id, period: card.config["period"], types: [statType])
            if let value = result[statType] {
                self.value = value
                error = nil
            } else if self.value == nil {
                error = "No data for this period"
            }
        } catch {
            if value == nil { self.error = error.localizedDescription }
        }
    }

    private var periodDescription: String {
        let period = card.config["period"]
        if let calendar = period?["calendar"]?["period"]?.stringValue {
            let offset = period?["calendar"]?["offset"]?.intValue ?? 0
            return offset == 0 ? "This \(calendar)" : "\(calendar.capitalized) \(offset)"
        }
        if period?["rolling_window"] != nil { return "Rolling window" }
        if period?["fixed_period"] != nil { return "Fixed period" }
        return "Today"
    }
}

// MARK: - Sensor

/// The `sensor` card: the current value with a small history graph.
struct SensorCard: View {
    let card: LovelaceCard

    @Environment(HomeStore.self) private var store
    @State private var points: [(time: Date, value: Double)] = []

    private var hours: Double { card.double("hours_to_show") ?? 24 }

    var body: some View {
        let entity = card.entity.flatMap(store.entity)
        CardContainer(title: card.string("name") ?? entity.map { store.registry.name(for: $0).name }) {
            VStack(alignment: .leading, spacing: 20) {
                if let entity {
                    Text(entity.displayState)
                        .font(.system(size: 64, weight: .light))
                }
                if card.string("graph") != "none", points.count > 1 {
                    Chart(points, id: \.time) { point in
                        LineMark(x: .value("Time", point.time), y: .value("Value", point.value))
                            .interpolationMethod(.monotone)
                        AreaMark(x: .value("Time", point.time), y: .value("Value", point.value))
                            .foregroundStyle(.tint.opacity(0.15))
                            .interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis(.hidden)
                    .frame(height: 160)
                }
            }
        }
        .reload(every: .seconds(120)) { await load() }
    }

    private func load() async {
        guard let id = card.entity,
              let history = try? await store.history(for: [id], since: Date().addingTimeInterval(-hours * 3600))
        else { return }
        // Fewer points than the big graphs: this chart is small.
        points = HADownsampler.numeric(history[id] ?? [], maxCount: 80)
    }
}

// MARK: - Helpers

private func format(_ value: Double) -> String {
    abs(value) >= 100 ? String(Int(value.rounded())) : String(format: "%.1f", value)
}

private func unitSpacing(_ unit: String) -> String {
    unit == "%" || unit.hasPrefix("°") ? "" : " "
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
