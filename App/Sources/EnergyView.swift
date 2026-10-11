import Charts
import HomeAssistantKit
import SwiftUI

/// The Energy dashboard: consumption per day (or month) for the grid, solar and
/// each tracked device, from long-term statistics.
struct EnergyView: View {
    let prefs: HAEnergyPrefs

    enum Range: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month", year = "Year"
        var id: String { rawValue }
    }

    private struct Bar: Identifiable {
        let start: Date
        let series: String
        let value: Double
        var id: String { "\(series)|\(start.timeIntervalSince1970)" }
    }

    @Environment(HomeStore.self) private var store
    @State private var range = Range.week
    @State private var bars: [Bar] = []
    @State private var unit = "kWh"
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            ControlRow(title: "Period") {
                ForEach(Range.allCases) { item in
                    OptionButton(title: item.rawValue, isSelected: item == range) { range = item }
                        .accessibilityIdentifier("energy-range-button")
                }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            } else if bars.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 500)
            } else {
                CardContainer(title: "Energy used per \(range == .year ? "month" : "day")") {
                    Chart(bars) { bar in
                        BarMark(
                            x: .value("Date", bar.start, unit: range == .year ? .month : .day),
                            y: .value(unit, bar.value)
                        )
                        .foregroundStyle(by: .value("Source", bar.series))
                    }
                    .chartYAxisLabel(unit)
                    .chartLegend(position: .bottom, alignment: .leading)
                    .frame(height: 460)
                }

                CardContainer(title: "Totals") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(totals, id: \.series) { total in
                            HStack {
                                Text(total.series)
                                Spacer()
                                Text("\(HAEntity.format(total.value)) \(unit)").monospacedDigit()
                            }
                            .font(.title3)
                        }
                    }
                }
            }
        }
        .task(id: range) { await load() }
    }

    private var totals: [(series: String, value: Double)] {
        Dictionary(grouping: bars, by: \.series)
            .map { (series: $0.key, value: $0.value.reduce(0) { $0 + $1.value }) }
            .sorted { $0.value > $1.value }
    }

    private func load() async {
        bars = []
        error = nil
        var series: [(id: String, name: String)] = prefs.gridImports.map { ($0, "Grid") }
            + prefs.solar.map { ($0, "Solar") }
        series += prefs.devices.map { ($0.statistic, $0.name ?? store.entity($0.statistic)?.friendlyName ?? $0.statistic) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start: Date
        switch range {
        case .week: start = calendar.date(byAdding: .day, value: -6, to: today)!
        case .month: start = calendar.date(byAdding: .day, value: -29, to: today)!
        case .year: start = calendar.date(byAdding: .month, value: -11, to: calendar.dateInterval(of: .month, for: today)!.start)!
        }
        do {
            let statistics = try await store.statistics(
                for: series.map(\.id), since: start, period: range == .year ? "month" : "day", types: ["change"])
            unit = series.lazy.compactMap { store.entity($0.id)?.unit }.first ?? "kWh"
            let loaded = series.flatMap { item in
                (statistics[item.id] ?? []).compactMap { point in
                    point.change.map { Bar(start: point.start, series: item.name, value: max($0, 0)) }
                }
            }
            if loaded.isEmpty { error = "No energy recorded in this period." }
            bars = loaded
        } catch {
            self.error = error.localizedDescription
        }
    }
}
