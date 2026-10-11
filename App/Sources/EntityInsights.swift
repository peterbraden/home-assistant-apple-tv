import Charts
import HomeAssistantKit
import SwiftUI

/// The last day of a numeric sensor, as a line chart.
struct SensorHistoryChart: View {
    let entity: HAEntity
    var hours: Double = 24

    @Environment(HomeStore.self) private var store
    @State private var points: [(time: Date, value: Double)] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Last \(Int(hours)) hours").font(.headline).foregroundStyle(.secondary)
            if points.count > 1 {
                Chart(points, id: \.time) { point in
                    LineMark(x: .value("Time", point.time), y: .value(entity.unit ?? "", point.value))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel(entity.unit ?? "")
                .frame(height: 300)
            } else if loaded {
                Text("No history recorded.").foregroundStyle(.secondary)
            } else {
                ProgressView().frame(height: 300)
            }
        }
        // Lets the remote reach the chart so the sheet scrolls to it.
        .focusable()
        .task(id: entity.entityId) {
            let start = Date().addingTimeInterval(-hours * 3600)
            let history = (try? await store.history(for: [entity.entityId], since: start))?[entity.entityId] ?? []
            points = HADownsampler.numeric(history, maxCount: 400)
            loaded = true
        }
    }
}

/// Recent logbook entries for an entity: what changed and what caused it.
struct ActivityList: View {
    let entity: HAEntity

    @Environment(HomeStore.self) private var store
    @State private var entries: [HALogbookEntry] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Activity").font(.headline).foregroundStyle(.secondary)
            if entries.isEmpty {
                Text(loaded ? "Nothing in the last 2 days." : "Loading…").foregroundStyle(.secondary).font(.callout)
            }
            ForEach(entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Text(entry.when, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                        .frame(width: 320, alignment: .leading)
                    Text(describe(entry))
                    if let cause = entry.cause {
                        Text(cause).foregroundStyle(.tertiary)
                    }
                }
                .font(.callout)
                .lineLimit(1)
            }
        }
        .focusable()
        .task(id: entity.entityId) {
            let start = Date().addingTimeInterval(-2 * 86400)
            entries = Array(((try? await store.logbook(for: entity.entityId, since: start)) ?? []).reversed().prefix(12))
            loaded = true
        }
    }

    private func describe(_ entry: HALogbookEntry) -> String {
        if let message = entry.message { return message.prefix(1).uppercased() + message.dropFirst() }
        guard let state = entry.state else { return "Changed" }
        switch state {
        case "on": return "Turned on"
        case "off": return "Turned off"
        case "unavailable": return "Became unavailable"
        default:
            let value = state.replacingOccurrences(of: "_", with: " ")
            if let unit = entity.unit, Double(state) != nil { return "\(value) \(unit)" }
            return value.prefix(1).uppercased() + value.dropFirst()
        }
    }
}

/// A row of daily forecast cards for a weather entity.
struct ForecastRow: View {
    let entity: HAEntity

    @Environment(HomeStore.self) private var store
    @State private var forecast: [HAForecast] = []
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Forecast").font(.headline).foregroundStyle(.secondary)
            if forecast.isEmpty {
                Text(failed ? "No forecast available." : "Loading…").foregroundStyle(.secondary)
            } else {
                HStack(spacing: 24) {
                    ForEach(forecast.prefix(7)) { day in
                        ForecastDay(day: day, unit: "°")
                    }
                }
            }
        }
        .focusable()
        .task(id: entity.entityId) {
            do {
                forecast = try await store.forecast(for: entity.entityId)
            } catch {
                failed = true
            }
        }
    }
}

private struct ForecastDay: View {
    let day: HAForecast
    let unit: String

    var body: some View {
        VStack(spacing: 12) {
            Text(day.date, format: .dateTime.weekday(.abbreviated)).font(.headline)
            Image(systemName: HAEntity.weatherSymbol(day.condition ?? ""))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 50))
                .frame(height: 60)
            if let high = day.temperature {
                Text("\(Int(high.rounded()))\(unit)").font(.title3.bold())
            }
            if let low = day.lowTemperature {
                Text("\(Int(low.rounded()))\(unit)").foregroundStyle(.secondary)
            }
            if let chance = day.precipitationProbability, chance > 0 {
                Label("\(Int(chance))%", systemImage: "drop.fill").font(.caption).foregroundStyle(.cyan)
            } else if let amount = day.precipitation, amount > 0 {
                Label(String(format: "%.1f", amount), systemImage: "drop.fill").font(.caption).foregroundStyle(.cyan)
            }
        }
        .padding(20)
        .frame(width: 150)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
    }
}
