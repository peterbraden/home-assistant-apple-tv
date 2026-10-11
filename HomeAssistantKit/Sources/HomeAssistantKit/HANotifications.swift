import Foundation

/// A persistent notification shown in Home Assistant's sidebar.
public struct HAPersistentNotification: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String?
    public let message: String
    public let createdAt: Date?

    public init?(_ json: JSONValue) {
        guard let id = json["notification_id"]?.stringValue else { return nil }
        self.id = id
        title = json["title"]?.stringValue
        message = json["message"]?.stringValue ?? ""
        createdAt = json["created_at"]?.stringValue.flatMap(HADate.parse)
    }

    /// Applies a `persistent_notification/subscribe` event to the current set, and
    /// returns notifications that are new rather than part of the initial list.
    @discardableResult
    public static func apply(
        _ event: JSONValue, to notifications: inout [String: HAPersistentNotification]
    ) -> [HAPersistentNotification] {
        let items = (event["notifications"]?.objectValue ?? [:]).values.compactMap(HAPersistentNotification.init)
        switch event["type"]?.stringValue {
        case "current":
            notifications = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            return []
        case "added":
            let new = items.filter { notifications[$0.id] == nil }
            items.forEach { notifications[$0.id] = $0 }
            return new
        case "updated":
            items.forEach { notifications[$0.id] = $0 }
            return []
        case "removed":
            let ids = Set((event["notifications"]?.objectValue ?? [:]).keys)
            ids.forEach { notifications.removeValue(forKey: $0) }
            return []
        default:
            return []
        }
    }
}
