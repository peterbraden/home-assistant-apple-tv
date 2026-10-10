import Foundation
import Testing
@testable import HomeAssistantKit

@Suite struct JSONValueTests {
    @Test func decodesMixedValues() throws {
        let json = #"{"a": true, "b": 1.5, "c": "x", "d": [1, null], "e": {"f": 2}}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        #expect(value["a"] == .bool(true))
        #expect(value["b"]?.doubleValue == 1.5)
        #expect(value["c"]?.stringValue == "x")
        #expect(value["d"] == [1, .null])
        #expect(value["e"]?["f"]?.intValue == 2)
    }

    @Test func integersAreNotBooleans() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data("[0, 1]".utf8))
        #expect(value == [.number(0), .number(1)])
    }

    @Test func roundTrips() throws {
        let value: JSONValue = ["entity_id": "light.kitchen", "brightness_pct": 50, "on": true]
        let decoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        #expect(decoded == value)
    }
}

@Suite struct EntityTests {
    let json = #"""
    {"entity_id": "light.living_room", "state": "on",
     "attributes": {"friendly_name": "Living Room", "brightness": 128, "supported_color_modes": ["hs"]},
     "last_changed": "2026-10-10T10:00:00+00:00", "last_updated": "2026-10-10T10:00:00+00:00"}
    """#

    @Test func decodesStateObject() throws {
        let entity = try JSONDecoder().decode(HAEntity.self, from: Data(json.utf8))
        #expect(entity.domain == "light")
        #expect(entity.friendlyName == "Living Room")
        #expect(entity.isActive)
        #expect(entity.displayState == "50%")
        #expect(entity.primaryAction == .service(domain: "homeassistant", service: "toggle"))
        #expect(entity.category == .lights)
    }

    @Test func fallbackNameFromObjectId() {
        let entity = HAEntity(entityId: "switch.coffee_maker", state: "off")
        #expect(entity.friendlyName == "Coffee Maker")
    }

    @Test func sensorFormatting() {
        let temp = HAEntity(entityId: "sensor.t", state: "21.46", attributes: ["unit_of_measurement": "°C"])
        #expect(temp.displayState == "21.5°C")
        let power = HAEntity(entityId: "sensor.p", state: "120", attributes: ["unit_of_measurement": "W"])
        #expect(power.displayState == "120 W")
        let door = HAEntity(entityId: "binary_sensor.d", state: "on", attributes: ["device_class": "door"])
        #expect(door.displayState == "Open")
    }

    @Test func locksRequireDetails() {
        let lock = HAEntity(entityId: "lock.front_door", state: "locked")
        #expect(lock.primaryAction == .showDetails)
        #expect(lock.symbolName == "lock.fill")
    }
}

@Suite struct ServerConfigTests {
    @Test func addsSchemeAndDefaultPort() {
        #expect(HAServerConfig.normalizedURL(from: "homeassistant.local")?.absoluteString
            == "http://homeassistant.local:8123")
        #expect(HAServerConfig.normalizedURL(from: "192.168.1.5:8124")?.absoluteString
            == "http://192.168.1.5:8124")
    }

    @Test func keepsExplicitSchemeAndStripsPath() {
        #expect(HAServerConfig.normalizedURL(from: " https://ha.example.com/lovelace/0 ")?.absoluteString
            == "https://ha.example.com")
        #expect(HAServerConfig.normalizedURL(from: "http://ha.lan")?.absoluteString == "http://ha.lan")
    }

    @Test func rejectsGarbage() {
        #expect(HAServerConfig.normalizedURL(from: "") == nil)
        #expect(HAServerConfig.normalizedURL(from: "ftp://x") == nil)
    }

    @Test func buildsURLs() throws {
        let config = try HAServerConfig(address: "https://ha.example.com", accessToken: " abc\n")
        #expect(config.accessToken == "abc")
        #expect(config.webSocketURL.absoluteString == "wss://ha.example.com/api/websocket")
        #expect(config.apiURL("services/light/turn_on").absoluteString
            == "https://ha.example.com/api/services/light/turn_on")
        #expect(config.resolve("/api/camera_proxy/camera.door?token=1")?.absoluteString
            == "https://ha.example.com/api/camera_proxy/camera.door?token=1")
    }
}

@Suite struct RegistryTests {
    @Test func resolvesAreasThroughDevices() {
        let registry = HARegistry(
            areas: [HAArea(areaId: "kitchen", name: "Kitchen"), HAArea(areaId: "attic", name: "Attic")],
            devices: [HADeviceEntry(id: "dev1", areaId: "kitchen")],
            entities: [
                HAEntityEntry(entityId: "light.a", deviceId: "dev1"),
                HAEntityEntry(entityId: "light.b", areaId: "attic", deviceId: "dev1"),
                HAEntityEntry(entityId: "sensor.c", deviceId: "dev1", entityCategory: "diagnostic"),
            ]
        )
        #expect(registry.areas.map(\.name) == ["Attic", "Kitchen"])
        #expect(registry.areaId(for: "light.a") == "kitchen")
        #expect(registry.areaId(for: "light.b") == "attic")
        #expect(registry.isHidden("sensor.c"))
        #expect(!registry.isHidden("light.a"))
    }

    @Test func parsesStateChangedEvent() throws {
        let json = #"""
        {"entity_id": "switch.fan", "old_state": null,
         "new_state": {"entity_id": "switch.fan", "state": "on", "attributes": {}}}
        """#
        let data = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let change = try #require(HAStateChange(eventData: data))
        #expect(change.newState?.state == "on")

        let removed = HAStateChange(eventData: ["entity_id": "switch.fan", "new_state": .null])
        #expect(removed?.newState == nil)
    }
}
