import Foundation

/// One line of Home Assistant's logbook (`logbook/get_events`).
public struct HALogbookEntry: Sendable, Hashable, Identifiable {
    public let when: Date
    public let entityId: String?
    /// The new state, for state changes.
    public let state: String?
    /// Free text, for events such as "triggered by time".
    public let message: String?
    public let name: String?
    /// What caused it: e.g. the domain and service of an action call, or an automation's name.
    public let contextDomain: String?
    public let contextService: String?
    public let contextName: String?
    public let contextEntityId: String?
    public let contextUserId: String?

    public var id: String { "\(when.timeIntervalSince1970)|\(entityId ?? "")|\(state ?? message ?? "")" }

    public init?(_ json: JSONValue) {
        guard let seconds = json["when"]?.doubleValue else { return nil }
        when = Date(timeIntervalSince1970: seconds)
        entityId = json["entity_id"]?.stringValue
        state = json["state"]?.stringValue
        message = json["message"]?.stringValue
        name = json["name"]?.stringValue
        contextDomain = json["context_domain"]?.stringValue
        contextService = json["context_service"]?.stringValue
        contextName = json["context_name"]?.stringValue ?? json["context_entity_id_name"]?.stringValue
        contextEntityId = json["context_entity_id"]?.stringValue
        contextUserId = json["context_user_id"]?.stringValue
    }

    public static func list(from json: JSONValue) -> [HALogbookEntry] {
        (json.arrayValue ?? []).compactMap(HALogbookEntry.init)
    }

    /// A short explanation of the cause, such as "by Living room evening" or "by scene.turn_on".
    public var cause: String? {
        if let contextName { return "by \(contextName)" }
        if let contextEntityId { return "by \(contextEntityId)" }
        if let contextDomain, let contextService { return "by \(contextDomain).\(contextService)" }
        return nil
    }
}

/// One period of a weather forecast (`weather.get_forecasts`).
public struct HAForecast: Sendable, Hashable, Identifiable {
    public let date: Date
    public let condition: String?
    public let temperature: Double?
    public let lowTemperature: Double?
    public let precipitation: Double?
    public let precipitationProbability: Double?
    public let windSpeed: Double?
    public let humidity: Double?

    public var id: Date { date }

    public init?(_ json: JSONValue) {
        guard let text = json["datetime"]?.stringValue, let date = HADate.parse(text) else { return nil }
        self.date = date
        condition = json["condition"]?.stringValue
        temperature = json["temperature"]?.doubleValue
        lowTemperature = json["templow"]?.doubleValue
        precipitation = json["precipitation"]?.doubleValue
        precipitationProbability = json["precipitation_probability"]?.doubleValue
        windSpeed = json["wind_speed"]?.doubleValue
        humidity = json["humidity"]?.doubleValue
    }

    /// Forecasts for `entityId` from a `get_forecasts` service response.
    public static func list(from response: JSONValue, entityId: String) -> [HAForecast] {
        (response[entityId]?["forecast"]?.arrayValue ?? []).compactMap(HAForecast.init)
    }
}

/// Parses Home Assistant's ISO 8601 timestamps, with or without fractional seconds.
public enum HADate {
    public static func parse(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
