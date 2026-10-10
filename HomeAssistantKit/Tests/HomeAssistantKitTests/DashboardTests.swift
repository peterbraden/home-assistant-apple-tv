import Foundation
import Testing
@testable import HomeAssistantKit

private func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

@Suite struct DashboardTests {
    @Test func listsLovelaceDashboardsFromPanels() throws {
        let panels = try json(#"""
        {"lovelace": {"component_name": "lovelace", "url_path": "lovelace", "title": null},
         "lovelace-home": {"component_name": "lovelace", "url_path": "lovelace-home", "title": "Home", "icon": "mdi:home"},
         "map": {"component_name": "lovelace", "url_path": "map", "title": "Map"},
         "energy": {"component_name": "energy", "url_path": "energy", "title": "energy"}}
        """#)
        let dashboards = HADashboard.fromPanels(panels)
        #expect(dashboards.map(\.title) == ["Overview", "Home", "Map"])
        #expect(dashboards.first?.urlPath == nil)
        #expect(dashboards[1].urlPath == "lovelace-home")
    }

    @Test func parsesViewsCardsAndSections() throws {
        let config = LovelaceConfig(try json(#"""
        {"title": "Home", "views": [
          {"title": "Air", "path": "default_view", "type": "panel",
           "cards": [{"type": "history-graph", "hours_to_show": 48,
                      "entities": [{"entity": "sensor.a"}, "sensor.b"]}]},
          {"title": "Energy", "type": "sections", "sections": [
            {"type": "grid", "column_span": 4, "cards": [
              {"type": "statistics-graph", "entities": ["sensor.p"], "period": "5minute",
               "stat_types": ["mean", "max", "min"]}]}]},
          {"title": "Stack", "cards": [{"type": "vertical-stack", "cards": [{"type": "entity", "entity": "sun.sun"}]}]}
        ]}
        """#))
        #expect(!config.isStrategy)
        #expect(config.views.map(\.title) == ["Air", "Energy", "Stack"])

        let air = config.views[0]
        #expect(air.layout == .panel)
        #expect(air.cards[0].type == "history-graph")
        #expect(air.cards[0].double("hours_to_show") == 48)
        #expect(air.cards[0].entities.map(\.entityId) == ["sensor.a", "sensor.b"])

        let energy = config.views[1]
        #expect(energy.layout == .sections)
        #expect(energy.sections[0].columnSpan == 4)
        #expect(energy.allCards.first?.strings("stat_types") == ["mean", "max", "min"])

        let stack = config.views[2].cards[0]
        #expect(stack.cards.first?.entity == "sun.sun")
        #expect(Set(config.views.flatMap(\.allCards).map(\.id)).count == 3)
    }

    @Test func recognisesStrategyDashboards() throws {
        #expect(LovelaceConfig(try json(#"{"strategy": {"type": "map"}}"#)).isStrategy)
    }
}

@Suite struct HistoryTests {
    @Test func parsesCompressedHistory() throws {
        // Captured from a real server.
        let history = HAHistoryParser.history(try json(#"""
        {"sensor.livingroom_temperature_esp": [{"lu": 1791646896.998, "s": "23.3999996185303"},
                                               {"lu": 1791647460.759044, "s": "23.5"}],
         "sun.sun": [{"lu": 1791646896.998, "s": "above_horizon"}]}
        """#))
        let temperature = try #require(history["sensor.livingroom_temperature_esp"])
        #expect(temperature.count == 2)
        #expect(temperature[1].value == 23.5)
        #expect(temperature[0].time == Date(timeIntervalSince1970: 1791646896.998))
        #expect(history["sun.sun"]?.first?.value == nil)
    }

    @Test func parsesStatistics() throws {
        // Captured from a real server: `start` is in milliseconds.
        let statistics = HAHistoryParser.statistics(try json(#"""
        {"sensor.t": [{"end": 1791410400000, "max": 25.9, "mean": 24.03, "min": 22.8, "start": 1791324000000}]}
        """#))
        let point = try #require(statistics["sensor.t"]?.first)
        #expect(point.start == Date(timeIntervalSince1970: 1791324000))
        #expect(point.value(for: "mean") == 24.03)
        #expect(point.value(for: "max") == 25.9)
        #expect(point.value(for: "sum") == nil)
    }

    @Test func downsamplesNumericHistory() {
        let start = Date(timeIntervalSince1970: 0)
        let points = (0..<1000).map { HAHistoryPoint(time: start.addingTimeInterval(Double($0)), state: String($0)) }
        let reduced = HADownsampler.numeric(points + [HAHistoryPoint(time: start, state: "unavailable")], maxCount: 100)
        #expect(reduced.count == 100)
        #expect(reduced.first!.value == 4.5)  // average of 0...9
        #expect(HADownsampler.numeric(Array(points.prefix(10)), maxCount: 100).count == 10)
    }

    @Test func downsamplesStatisticsKeepingExtremes() {
        let points = (0..<10).map {
            HAStatisticPoint(start: Date(timeIntervalSince1970: Double($0)), mean: Double($0), min: Double($0) - 1, max: Double($0) + 1)
        }
        let reduced = HADownsampler.statistics(points, maxCount: 5)
        #expect(reduced.count == 5)
        #expect(reduced[0].mean == 0.5)
        #expect(reduced[0].min == -1)
        #expect(reduced[0].max == 2)
    }
}
