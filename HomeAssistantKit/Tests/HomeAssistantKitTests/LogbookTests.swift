import Foundation
import Testing
@testable import HomeAssistantKit

private func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

@Suite struct LogbookTests {
    @Test func parsesEntriesAndCauses() throws {
        let entries = HALogbookEntry.list(from: try json(#"""
        [{"state": "on", "entity_id": "light.office", "when": 1791625057.7},
         {"state": "off", "entity_id": "light.office", "when": 1791650804.9, "context_user_id": "u1",
          "context_domain": "scene", "context_service": "turn_on", "context_event_type": "call_service"},
         {"state": "on", "entity_id": "light.office", "when": 1791657490.1,
          "context_entity_id": "automation.motion", "context_name": "Office motion"},
         {"message": "triggered by time", "name": "Morning", "when": 1791660000},
         {"state": "bad"}]
        """#))
        #expect(entries.count == 4)
        #expect(entries[0].cause == nil)
        #expect(entries[1].cause == "by scene.turn_on")
        #expect(entries[1].contextUserId == "u1")
        #expect(entries[2].cause == "by Office motion")
        #expect(entries[3].message == "triggered by time")
        #expect(entries[0].when == Date(timeIntervalSince1970: 1791625057.7))
    }

    @Test func parsesForecastResponse() throws {
        let response = try json(#"""
        {"weather.home": {"forecast": [
          {"condition": "cloudy", "datetime": "2026-10-10T10:00:00+00:00", "temperature": 13.8,
           "templow": 13.4, "precipitation": 0.0, "humidity": 92, "wind_speed": 11.2},
          {"condition": "sunny", "datetime": "2026-10-11T10:00:00.000+00:00", "temperature": 16.8,
           "precipitation_probability": 20},
          {"condition": "rainy"}]}}
        """#)
        let forecast = HAForecast.list(from: response, entityId: "weather.home")
        #expect(forecast.count == 2)
        #expect(forecast[0].condition == "cloudy")
        #expect(forecast[0].lowTemperature == 13.4)
        #expect(forecast[1].precipitationProbability == 20)
        #expect(forecast[1].date.timeIntervalSince(forecast[0].date) == 86400)
        #expect(HAForecast.list(from: response, entityId: "weather.other").isEmpty)
    }

    @Test func parsesEnergyPrefs() throws {
        let prefs = HAEnergyPrefs(try json(#"""
        {"energy_sources": [
           {"type": "grid", "flow_from": [{"stat_energy_from": "sensor.import"}],
            "flow_to": [{"stat_energy_to": "sensor.export"}]},
           {"type": "solar", "stat_energy_from": "sensor.solar"},
           {"type": "gas", "stat_energy_from": "sensor.gas"}],
         "device_consumption": [{"stat_consumption": "sensor.eir", "name": "Eir"},
                                {"stat_consumption": "sensor.tyr"}]}
        """#))
        #expect(prefs.gridImports == ["sensor.import"])
        #expect(prefs.gridExports == ["sensor.export"])
        #expect(prefs.solar == ["sensor.solar"])
        #expect(prefs.devices.map(\.statistic) == ["sensor.eir", "sensor.tyr"])
        #expect(prefs.devices[0].name == "Eir")
        #expect(!prefs.isEmpty)
        #expect(HAEnergyPrefs(try json(#"{"energy_sources": [], "device_consumption": []}"#)).isEmpty)
    }
}
