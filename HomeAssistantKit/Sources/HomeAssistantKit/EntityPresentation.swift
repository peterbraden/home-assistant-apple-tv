import Foundation

/// Groups of entities shown as tabs in the app.
public enum EntityCategory: String, CaseIterable, Identifiable, Sendable {
    case lights
    case climate
    case media
    case security
    case scenes
    case automations
    case controls
    case sensors

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lights: return "Lights"
        case .climate: return "Climate"
        case .media: return "Media"
        case .security: return "Security"
        case .scenes: return "Scenes"
        case .automations: return "Automations"
        case .controls: return "Controls"
        case .sensors: return "Sensors"
        }
    }

    public var symbol: String {
        switch self {
        case .lights: return "lightbulb.fill"
        case .climate: return "thermometer.medium"
        case .media: return "play.tv.fill"
        case .security: return "lock.shield.fill"
        case .scenes: return "sparkles"
        case .automations: return "gearshape.2.fill"
        case .controls: return "slider.horizontal.3"
        case .sensors: return "gauge.with.dots.needle.33percent"
        }
    }

    public static func of(_ entity: HAEntity) -> EntityCategory? {
        switch entity.domain {
        case "light", "switch", "fan", "input_boolean", "humidifier":
            return .lights
        case "climate", "water_heater":
            return .climate
        case "media_player", "remote":
            return .media
        case "lock", "alarm_control_panel", "cover", "valve", "camera":
            return .security
        case "scene", "script", "button", "input_button":
            return .scenes
        case "automation":
            return .automations
        case "select", "input_select", "number", "input_number", "input_datetime", "input_text":
            return .controls
        case "sensor", "binary_sensor", "weather", "person", "device_tracker", "sun":
            return .sensors
        default:
            return nil
        }
    }
}

/// What happens when the user clicks an entity's tile.
public enum EntityPrimaryAction: Equatable, Sendable {
    /// Call a service directly (toggle a light, run a scene).
    case service(domain: String, service: String)
    /// Open the detail view. Used for anything where an accidental click
    /// would be surprising (locks, alarms) or that needs more controls.
    case showDetails
}

extension HAEntity {
    public var category: EntityCategory? { EntityCategory.of(self) }

    /// Entities that can be operated from a tile; used for the Rooms view.
    public var isControllable: Bool {
        switch domain {
        case "light", "switch", "fan", "input_boolean", "humidifier", "climate", "water_heater",
             "media_player", "lock", "cover", "valve", "scene", "script", "button", "input_button",
             "vacuum", "camera", "alarm_control_panel":
            return true
        default:
            return false
        }
    }

    public var primaryAction: EntityPrimaryAction {
        switch domain {
        case "light", "switch", "fan", "input_boolean", "humidifier":
            return .service(domain: "homeassistant", service: "toggle")
        case "scene":
            return .service(domain: "scene", service: "turn_on")
        case "script":
            return .service(domain: "script", service: "turn_on")
        case "button", "input_button":
            return .service(domain: domain, service: "press")
        default:
            return .showDetails
        }
    }

    /// Human-readable state, including units and formatted numbers.
    public var displayState: String {
        if isUnavailable { return state == "unknown" ? "Unknown" : "Unavailable" }

        switch domain {
        case "scene", "script", "button", "input_button":
            return domain == "script" && state == "on" ? "Running" : "Tap to run"
        case "light":
            if state == "on", let brightness = attributes["brightness"]?.doubleValue {
                return "\(Int((brightness / 255 * 100).rounded()))%"
            }
        case "climate":
            let mode = Self.humanize(state)
            if let current = attributes["current_temperature"]?.doubleValue {
                return "\(Self.format(current))° · \(mode)"
            }
            return mode
        case "media_player":
            if let title = attributes["media_title"]?.stringValue, state == "playing" || state == "paused" {
                return title
            }
        case "cover", "valve":
            if let position = attributes["current_position"]?.intValue, state == "open" {
                return "Open · \(position)%"
            }
        case "automation":
            return state == "on" ? "Enabled" : "Disabled"
        case "update":
            if state == "on", let latest = attributes["latest_version"]?.stringValue {
                return "Update to \(latest)"
            }
            return state == "off" ? "Up to date" : Self.humanize(state)
        case "binary_sensor":
            return binarySensorState
        case "sensor":
            if let value = Double(state) {
                return Self.format(value) + (unit.map { unitSpacing($0) + $0 } ?? "")
            }
        case "weather":
            if let temperature = attributes["temperature"]?.doubleValue {
                let unit = attributes["temperature_unit"]?.stringValue ?? "°"
                return "\(Self.format(temperature))\(unit) · \(Self.humanize(state))"
            }
        default:
            break
        }
        if let unit, !unit.isEmpty {
            return state + unitSpacing(unit) + unit
        }
        return Self.humanize(state)
    }

    /// An SF Symbol name representing the entity and its current state.
    public var symbolName: String {
        let on = isActive
        switch domain {
        case "light": return on ? "lightbulb.fill" : "lightbulb"
        case "switch", "input_boolean": return on ? "power.circle.fill" : "power.circle"
        case "fan": return on ? "fan.fill" : "fan"
        case "humidifier": return "humidifier.fill"
        case "climate": return on ? "thermometer.sun.fill" : "thermometer.medium"
        case "water_heater": return "water.waves"
        case "media_player":
            switch deviceClass {
            case "speaker": return "hifispeaker.fill"
            case "receiver": return "hifireceiver.fill"
            default: return on ? "play.tv.fill" : "tv"
            }
        case "remote": return "appletvremote.gen4.fill"
        case "camera": return "video.fill"
        case "lock":
            // Never show an open padlock for a lock whose state isn't known.
            if isUnavailable { return "lock.slash" }
            return state == "locked" ? "lock.fill" : "lock.open.fill"
        case "alarm_control_panel": return state == "disarmed" ? "shield" : "shield.lefthalf.filled"
        case "cover":
            switch deviceClass {
            case "garage": return on ? "door.garage.open" : "door.garage.closed"
            case "door", "gate": return on ? "door.left.hand.open" : "door.left.hand.closed"
            default: return on ? "blinds.vertical.open" : "blinds.vertical.closed"
            }
        case "valve": return "spigot.fill"
        case "scene": return "sparkles"
        case "script": return "scroll.fill"
        case "button", "input_button": return "button.programmable"
        case "vacuum": return "fan.ceiling.fill"
        case "automation": return on ? "gearshape.2.fill" : "gearshape.2"
        case "select", "input_select": return "list.bullet.circle"
        case "number", "input_number": return "number.circle"
        case "input_datetime": return "calendar.badge.clock"
        case "input_text": return "character.cursor.ibeam"
        case "update": return on ? "arrow.down.circle.fill" : "checkmark.circle"
        case "person": return state == "home" ? "person.fill.checkmark" : "person.fill"
        case "device_tracker": return "location.fill"
        case "sun": return state == "above_horizon" ? "sun.max.fill" : "moon.stars.fill"
        case "weather": return Self.weatherSymbol(state)
        case "binary_sensor": return binarySensorSymbol
        case "sensor":
            switch deviceClass {
            case "temperature": return "thermometer.medium"
            case "humidity": return "humidity.fill"
            case "battery": return "battery.75percent"
            case "power", "energy", "current", "voltage": return "bolt.fill"
            case "illuminance": return "sun.min.fill"
            case "pressure": return "barometer"
            case "carbon_dioxide", "pm25", "pm10", "aqi", "volatile_organic_compounds": return "aqi.medium"
            case "gas": return "flame.fill"
            case "moisture": return "drop.fill"
            case "timestamp": return "clock.fill"
            default: return "gauge.with.dots.needle.33percent"
            }
        default: return "circle.grid.2x2.fill"
        }
    }

    private var binarySensorState: String {
        let on = state == "on"
        switch deviceClass {
        case "door", "garage_door", "window", "opening": return on ? "Open" : "Closed"
        case "motion", "occupancy", "presence": return on ? "Detected" : "Clear"
        case "moisture": return on ? "Wet" : "Dry"
        case "smoke", "gas", "carbon_monoxide", "safety", "problem", "tamper": return on ? "Alert" : "OK"
        case "lock": return on ? "Unlocked" : "Locked"
        case "connectivity": return on ? "Connected" : "Disconnected"
        case "battery": return on ? "Low" : "Normal"
        case "plug", "power": return on ? "Powered" : "Off"
        default: return on ? "On" : "Off"
        }
    }

    private var binarySensorSymbol: String {
        let on = state == "on"
        switch deviceClass {
        case "door", "garage_door", "opening": return on ? "door.left.hand.open" : "door.left.hand.closed"
        case "window": return on ? "window.vertical.open" : "window.vertical.closed"
        case "motion", "occupancy", "presence": return on ? "figure.walk.motion" : "figure.stand"
        case "moisture": return "drop.fill"
        case "smoke", "gas", "carbon_monoxide": return on ? "smoke.fill" : "smoke"
        case "connectivity": return on ? "wifi" : "wifi.slash"
        case "battery": return on ? "battery.25percent" : "battery.100percent"
        default: return on ? "circle.fill" : "circle"
        }
    }

    private func unitSpacing(_ unit: String) -> String {
        unit == "%" || unit.hasPrefix("°") ? "" : " "
    }

    public static func format(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e9 {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    static func humanize(_ state: String) -> String {
        let text = state.replacingOccurrences(of: "_", with: " ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    public static func weatherSymbol(_ state: String) -> String {
        switch state {
        case "sunny": return "sun.max.fill"
        case "clear-night": return "moon.stars.fill"
        case "partlycloudy": return "cloud.sun.fill"
        case "cloudy": return "cloud.fill"
        case "fog": return "cloud.fog.fill"
        case "rainy": return "cloud.rain.fill"
        case "pouring": return "cloud.heavyrain.fill"
        case "snowy", "snowy-rainy": return "cloud.snow.fill"
        case "hail": return "cloud.hail.fill"
        case "lightning", "lightning-rainy": return "cloud.bolt.rain.fill"
        case "windy", "windy-variant": return "wind"
        default: return "cloud.sun.fill"
        }
    }
}

/// `supported_features` bit flags for the domains the app has controls for.
public enum HAFeature {
    public enum Cover {
        public static let open = 1
        public static let close = 2
        public static let setPosition = 4
        public static let stop = 8
    }

    public enum MediaPlayer {
        public static let pause = 1
        public static let seek = 2
        public static let volumeSet = 4
        public static let volumeMute = 8
        public static let previousTrack = 16
        public static let nextTrack = 32
        public static let turnOn = 128
        public static let turnOff = 256
        public static let playMedia = 512
        public static let volumeStep = 1024
        public static let selectSource = 2048
        public static let stop = 4096
        public static let play = 16384
        public static let browseMedia = 131072
    }

    public enum Climate {
        public static let targetTemperature = 1
        public static let targetTemperatureRange = 2
    }

    public enum Vacuum {
        public static let returnHome = 16
        public static let start = 8192
        public static let pause = 4
    }
}
