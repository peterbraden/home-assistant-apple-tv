import Foundation

/// A Home Assistant state object, as returned by `GET /api/states` or `get_states`.
public struct HAEntity: Codable, Identifiable, Hashable, Sendable {
    public let entityId: String
    public var state: String
    public var attributes: [String: JSONValue]
    public var lastChanged: String?
    public var lastUpdated: String?

    public var id: String { entityId }

    enum CodingKeys: String, CodingKey {
        case entityId = "entity_id"
        case state
        case attributes
        case lastChanged = "last_changed"
        case lastUpdated = "last_updated"
    }

    public init(
        entityId: String,
        state: String,
        attributes: [String: JSONValue] = [:],
        lastChanged: String? = nil,
        lastUpdated: String? = nil
    ) {
        self.entityId = entityId
        self.state = state
        self.attributes = attributes
        self.lastChanged = lastChanged
        self.lastUpdated = lastUpdated
    }

    public var domain: String {
        String(entityId.prefix(while: { $0 != "." }))
    }

    public var objectId: String {
        guard let dot = entityId.firstIndex(of: ".") else { return entityId }
        return String(entityId[entityId.index(after: dot)...])
    }

    public var friendlyName: String {
        if let name = attributes["friendly_name"]?.stringValue, !name.isEmpty {
            return name
        }
        return objectId.replacingOccurrences(of: "_", with: " ").capitalized
    }

    public var deviceClass: String? { attributes["device_class"]?.stringValue }
    public var unit: String? { attributes["unit_of_measurement"]?.stringValue }
    public var icon: String? { attributes["icon"]?.stringValue }
    public var entityPicture: String? { attributes["entity_picture"]?.stringValue }
    public var supportedFeatures: Int { attributes["supported_features"]?.intValue ?? 0 }

    public var isUnavailable: Bool {
        state == "unavailable" || state == "unknown"
    }

    /// Whether the entity is in an "active" state (light on, door open, media playing, ...).
    public var isActive: Bool {
        switch state {
        case "on", "open", "opening", "unlocked", "playing", "home", "heat", "cool", "heat_cool",
             "auto", "dry", "fan_only", "cleaning", "armed_home", "armed_away", "armed_night",
             "triggered", "recording", "streaming":
            return true
        default:
            return false
        }
    }

    public func supports(_ feature: Int) -> Bool {
        supportedFeatures & feature != 0
    }
}
