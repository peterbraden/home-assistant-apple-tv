import Foundation

public struct HAArea: Codable, Hashable, Identifiable, Sendable {
    public let areaId: String
    public let name: String
    public let icon: String?

    public var id: String { areaId }

    enum CodingKeys: String, CodingKey {
        case areaId = "area_id"
        case name
        case icon
    }

    public init(areaId: String, name: String, icon: String? = nil) {
        self.areaId = areaId
        self.name = name
        self.icon = icon
    }
}

public struct HADeviceEntry: Codable, Hashable, Sendable {
    public let id: String
    public let areaId: String?
    public let name: String?
    public let nameByUser: String?

    enum CodingKeys: String, CodingKey {
        case id
        case areaId = "area_id"
        case name
        case nameByUser = "name_by_user"
    }

    public init(id: String, areaId: String?, name: String? = nil, nameByUser: String? = nil) {
        self.id = id
        self.areaId = areaId
        self.name = name
        self.nameByUser = nameByUser
    }

    /// The name shown in Home Assistant: the user's override, if any.
    public var displayName: String? {
        [nameByUser, name].compactMap { $0 }.first { !$0.isEmpty }
    }
}

/// An entity's name split into the device it belongs to and its own name,
/// e.g. "Purifier (TP11)" + "Humidity" rather than "Purifier (TP11) Humidity".
public struct HAEntityName: Hashable, Sendable {
    public let device: String?
    public let name: String
}

public struct HAEntityEntry: Codable, Hashable, Sendable {
    public let entityId: String
    public let areaId: String?
    public let deviceId: String?
    public let hiddenBy: String?
    public let disabledBy: String?
    public let entityCategory: String?

    enum CodingKeys: String, CodingKey {
        case entityId = "entity_id"
        case areaId = "area_id"
        case deviceId = "device_id"
        case hiddenBy = "hidden_by"
        case disabledBy = "disabled_by"
        case entityCategory = "entity_category"
    }

    public init(
        entityId: String,
        areaId: String? = nil,
        deviceId: String? = nil,
        hiddenBy: String? = nil,
        disabledBy: String? = nil,
        entityCategory: String? = nil
    ) {
        self.entityId = entityId
        self.areaId = areaId
        self.deviceId = deviceId
        self.hiddenBy = hiddenBy
        self.disabledBy = disabledBy
        self.entityCategory = entityCategory
    }
}

/// Area, device and entity registries, used to group entities into rooms
/// and to hide config/diagnostic entities.
public struct HARegistry: Sendable {
    public let areas: [HAArea]
    private let areaByEntity: [String: String]
    private let deviceNameByEntity: [String: String]
    private let hiddenEntities: Set<String>

    public init(areas: [HAArea], devices: [HADeviceEntry], entities: [HAEntityEntry]) {
        self.areas = areas.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let deviceAreas = Dictionary(
            devices.compactMap { device in device.areaId.map { (device.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )

        let deviceNames = Dictionary(
            devices.compactMap { device in device.displayName.map { (device.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )

        var areaByEntity: [String: String] = [:]
        var deviceNameByEntity: [String: String] = [:]
        var hidden: Set<String> = []
        for entry in entities {
            if let deviceId = entry.deviceId, let name = deviceNames[deviceId] {
                deviceNameByEntity[entry.entityId] = name
            }
            // An entity's own area overrides the area of its device.
            if let area = entry.areaId ?? entry.deviceId.flatMap({ deviceAreas[$0] }) {
                areaByEntity[entry.entityId] = area
            }
            if entry.hiddenBy != nil || entry.disabledBy != nil || entry.entityCategory != nil {
                hidden.insert(entry.entityId)
            }
        }
        self.areaByEntity = areaByEntity
        self.deviceNameByEntity = deviceNameByEntity
        self.hiddenEntities = hidden
    }

    public static let empty = HARegistry(areas: [], devices: [], entities: [])

    public func areaId(for entityId: String) -> String? {
        areaByEntity[entityId]
    }

    /// Splits off the device name when the entity's name starts with it.
    public func name(for entity: HAEntity) -> HAEntityName {
        let full = entity.friendlyName
        guard let device = deviceNameByEntity[entity.entityId], full.hasPrefix(device) else {
            return HAEntityName(device: nil, name: full)
        }
        let rest = full.dropFirst(device.count).trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return HAEntityName(device: nil, name: full) }
        return HAEntityName(device: device, name: rest.prefix(1).uppercased() + rest.dropFirst())
    }

    public func isHidden(_ entityId: String) -> Bool {
        hiddenEntities.contains(entityId)
    }
}
