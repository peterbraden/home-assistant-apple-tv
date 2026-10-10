import HomeAssistantKit
import SwiftUI

/// Modal controls for a single entity. Reads live state from the store so it
/// updates as Home Assistant reports changes.
struct EntityDetailView: View {
    let entityId: String

    @Environment(HomeStore.self) private var store

    var body: some View {
        if let entity = store.entity(entityId) {
            ScrollView {
                VStack(alignment: .leading, spacing: 50) {
                    header(entity)
                    controls(for: entity)
                    AttributeList(entity: entity)
                }
                .padding(60)
                .frame(maxWidth: 1400, alignment: .leading)
            }
        } else {
            ContentUnavailableView("Entity unavailable", systemImage: "questionmark.circle")
        }
    }

    private func header(_ entity: HAEntity) -> some View {
        HStack(spacing: 30) {
            Image(systemName: entity.symbolName)
                .font(.system(size: 80))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(entity.tint)
                .frame(width: 120)
            VStack(alignment: .leading, spacing: 6) {
                Text(entity.friendlyName).font(.title2.bold())
                Text(entity.displayState).font(.title3).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func controls(for entity: HAEntity) -> some View {
        switch entity.domain {
        case "light": LightControls(entity: entity)
        case "switch", "input_boolean", "humidifier": PowerControls(entity: entity)
        case "fan": FanControls(entity: entity)
        case "climate", "water_heater": ClimateControls(entity: entity)
        case "media_player": MediaControls(entity: entity)
        case "cover", "valve": CoverControls(entity: entity)
        case "lock": LockControls(entity: entity)
        case "alarm_control_panel": AlarmControls(entity: entity)
        case "vacuum": VacuumControls(entity: entity)
        case "scene", "script", "button", "input_button": RunControls(entity: entity)
        default: EmptyView()
        }
    }
}

// MARK: - Building blocks

/// A labelled row of control buttons.
struct ControlRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 30) { content }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 4)
            }
            .scrollClipDisabled()
        }
    }
}

/// A control button that shows a checkmark when it represents the current state.
struct OptionButton: View {
    let title: String
    var systemImage: String?
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark.circle.fill")
            } else if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
    }
}

private struct PowerRow: View {
    let entity: HAEntity
    var domain = "homeassistant"
    @Environment(HomeStore.self) private var store

    var body: some View {
        ControlRow(title: "Power") {
            OptionButton(title: "On", systemImage: "power", isSelected: entity.state == "on") {
                store.call(domain, "turn_on", on: entity)
            }
            OptionButton(title: "Off", systemImage: "poweroff", isSelected: entity.state == "off") {
                store.call(domain, "turn_off", on: entity)
            }
        }
    }
}

// MARK: - Domain controls

private struct PowerControls: View {
    let entity: HAEntity
    var body: some View { PowerRow(entity: entity) }
}

private struct LightControls: View {
    let entity: HAEntity
    @Environment(HomeStore.self) private var store

    private var colorModes: Set<String> {
        Set(entity.attributes["supported_color_modes"]?.arrayValue?.compactMap(\.stringValue) ?? [])
    }

    private var supportsBrightness: Bool {
        !colorModes.isDisjoint(with: ["brightness", "color_temp", "hs", "xy", "rgb", "rgbw", "rgbww", "white"])
    }

    private var supportsColor: Bool {
        !colorModes.isDisjoint(with: ["hs", "xy", "rgb", "rgbw", "rgbww"])
    }

    private var brightnessPercent: Int? {
        entity.attributes["brightness"]?.doubleValue.map { Int(($0 / 255 * 100).rounded()) }
    }

    var body: some View {
        PowerRow(entity: entity, domain: "light")

        if supportsBrightness {
            ControlRow(title: "Brightness") {
                Button { turnOn(["brightness_step_pct": -10]) } label: { Image(systemName: "minus") }
                Text(brightnessPercent.map { "\($0)%" } ?? "Off")
                    .font(.title3.monospacedDigit())
                    .frame(width: 120)
                Button { turnOn(["brightness_step_pct": 10]) } label: { Image(systemName: "plus") }
                ForEach([10, 25, 50, 75, 100], id: \.self) { percent in
                    OptionButton(title: "\(percent)%", isSelected: brightnessPercent == percent) {
                        turnOn(["brightness_pct": .number(Double(percent))])
                    }
                }
            }
        }

        if colorModes.contains("color_temp") {
            ControlRow(title: "White") {
                ForEach(LightPreset.whites) { preset in
                    Button(preset.name) { turnOn(["color_temp_kelvin": .number(preset.kelvin)]) }
                }
            }
        }

        if supportsColor {
            ControlRow(title: "Color") {
                ForEach(LightPreset.colors) { preset in
                    Button {
                        turnOn(["hs_color": [.number(preset.hue), 100]])
                    } label: {
                        Circle()
                            .fill(Color(hue: preset.hue / 360, saturation: 1, brightness: 1))
                            .frame(width: 50, height: 50)
                            .accessibilityLabel(preset.name)
                    }
                }
            }
        }
    }

    private func turnOn(_ data: [String: JSONValue]) {
        store.call("light", "turn_on", on: entity, data: data)
    }
}

private struct LightPreset: Identifiable {
    let name: String
    var kelvin: Double = 0
    var hue: Double = 0
    var id: String { name }

    static let whites = [
        LightPreset(name: "Warm", kelvin: 2700),
        LightPreset(name: "Soft", kelvin: 3500),
        LightPreset(name: "Neutral", kelvin: 4500),
        LightPreset(name: "Daylight", kelvin: 6000),
    ]

    static let colors = [
        LightPreset(name: "Red", hue: 0),
        LightPreset(name: "Orange", hue: 30),
        LightPreset(name: "Yellow", hue: 55),
        LightPreset(name: "Green", hue: 120),
        LightPreset(name: "Cyan", hue: 185),
        LightPreset(name: "Blue", hue: 230),
        LightPreset(name: "Purple", hue: 275),
        LightPreset(name: "Pink", hue: 320),
    ]
}

private struct FanControls: View {
    let entity: HAEntity
    @Environment(HomeStore.self) private var store

    var body: some View {
        PowerRow(entity: entity, domain: "fan")
        if let current = entity.attributes["percentage"]?.intValue ?? (entity.state == "off" ? 0 : nil) {
            ControlRow(title: "Speed") {
                ForEach([25, 50, 75, 100], id: \.self) { percent in
                    OptionButton(title: "\(percent)%", isSelected: current == percent) {
                        store.call("fan", "set_percentage", on: entity, data: ["percentage": .number(Double(percent))])
                    }
                }
            }
        }
    }
}

private struct ClimateControls: View {
    let entity: HAEntity
    @Environment(HomeStore.self) private var store

    private var step: Double {
        entity.attributes["target_temp_step"]?.doubleValue ?? 0.5
    }

    private func strings(_ key: String) -> [String] {
        entity.attributes[key]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    var body: some View {
        if let current = entity.attributes["current_temperature"]?.doubleValue {
            ControlRow(title: "Current") {
                Text(format(current) + "°").font(.system(size: 64, weight: .light))
            }
        }

        if let target = entity.attributes["temperature"]?.doubleValue {
            temperatureRow("Target", value: target, key: "temperature")
        }
        if let low = entity.attributes["target_temp_low"]?.doubleValue,
           let high = entity.attributes["target_temp_high"]?.doubleValue {
            temperatureRow("Heat to", value: low, key: "target_temp_low", extra: ["target_temp_high": .number(high)])
            temperatureRow("Cool to", value: high, key: "target_temp_high", extra: ["target_temp_low": .number(low)])
        }

        let modes = strings(entity.domain == "climate" ? "hvac_modes" : "operation_list")
        if !modes.isEmpty {
            ControlRow(title: "Mode") {
                ForEach(modes, id: \.self) { mode in
                    OptionButton(title: humanize(mode), isSelected: entity.state == mode) {
                        if entity.domain == "climate" {
                            store.call("climate", "set_hvac_mode", on: entity, data: ["hvac_mode": .string(mode)])
                        } else {
                            store.call("water_heater", "set_operation_mode", on: entity,
                                       data: ["operation_mode": .string(mode)])
                        }
                    }
                }
            }
        }

        let presets = strings("preset_modes")
        if !presets.isEmpty {
            ControlRow(title: "Preset") {
                ForEach(presets, id: \.self) { preset in
                    OptionButton(title: humanize(preset),
                                 isSelected: entity.attributes["preset_mode"]?.stringValue == preset) {
                        store.call("climate", "set_preset_mode", on: entity, data: ["preset_mode": .string(preset)])
                    }
                }
            }
        }

        let fanModes = strings("fan_modes")
        if !fanModes.isEmpty {
            ControlRow(title: "Fan") {
                ForEach(fanModes, id: \.self) { mode in
                    OptionButton(title: humanize(mode),
                                 isSelected: entity.attributes["fan_mode"]?.stringValue == mode) {
                        store.call("climate", "set_fan_mode", on: entity, data: ["fan_mode": .string(mode)])
                    }
                }
            }
        }
    }

    private func temperatureRow(
        _ title: String, value: Double, key: String, extra: [String: JSONValue] = [:]
    ) -> some View {
        ControlRow(title: title) {
            Button { setTemperature(value - step, key: key, extra: extra) } label: { Image(systemName: "minus") }
            Text(format(value) + "°")
                .font(.title2.monospacedDigit())
                .frame(width: 160)
            Button { setTemperature(value + step, key: key, extra: extra) } label: { Image(systemName: "plus") }
        }
    }

    private func setTemperature(_ value: Double, key: String, extra: [String: JSONValue]) {
        var data = extra
        let min = entity.attributes["min_temp"]?.doubleValue ?? -Double.infinity
        let max = entity.attributes["max_temp"]?.doubleValue ?? Double.infinity
        data[key] = .number(Swift.min(Swift.max(value, min), max))
        store.call(entity.domain, "set_temperature", on: entity, data: data)
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

private struct MediaControls: View {
    let entity: HAEntity
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private typealias Feature = HAFeature.MediaPlayer

    var body: some View {
        HStack(alignment: .top, spacing: 50) {
            if let picture = entity.entityPicture {
                AuthorizedImage(path: picture)
                    .frame(width: 300, height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            VStack(alignment: .leading, spacing: 10) {
                if let title = entity.attributes["media_title"]?.stringValue {
                    Text(title).font(.title3.bold())
                }
                if let artist = entity.attributes["media_artist"]?.stringValue
                    ?? entity.attributes["media_series_title"]?.stringValue {
                    Text(artist).foregroundStyle(.secondary)
                }
                if let app = entity.attributes["app_name"]?.stringValue
                    ?? entity.attributes["source"]?.stringValue {
                    Text(app).font(.callout).foregroundStyle(.tertiary)
                }
            }
        }

        ControlRow(title: "Playback") {
            if entity.supports(Feature.previousTrack) {
                media("media_previous_track", "backward.fill")
            }
            if entity.supports(Feature.play) || entity.supports(Feature.pause) {
                media("media_play_pause", entity.state == "playing" ? "pause.fill" : "play.fill")
            }
            if entity.supports(Feature.nextTrack) {
                media("media_next_track", "forward.fill")
            }
            if entity.supports(Feature.stop) {
                media("media_stop", "stop.fill")
            }
        }

        if entity.supports(Feature.volumeSet) || entity.supports(Feature.volumeStep) || entity.supports(Feature.volumeMute) {
            ControlRow(title: "Volume") {
                if entity.supports(Feature.volumeSet) || entity.supports(Feature.volumeStep) {
                    media("volume_down", "speaker.minus.fill")
                    if let level = entity.attributes["volume_level"]?.doubleValue {
                        Text("\(Int((level * 100).rounded()))%")
                            .font(.title3.monospacedDigit())
                            .frame(width: 120)
                    }
                    media("volume_up", "speaker.plus.fill")
                }
                if entity.supports(Feature.volumeMute) {
                    let muted = entity.attributes["is_volume_muted"]?.boolValue ?? false
                    Button {
                        store.call("media_player", "volume_mute", on: entity, data: ["is_volume_muted": .bool(!muted)])
                    } label: {
                        Label(muted ? "Unmute" : "Mute", systemImage: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                }
            }
        }

        if entity.supports(Feature.browseMedia) {
            Button("Browse Library", systemImage: "rectangle.stack") {
                store.mediaPath = [.player(entityId: entity.entityId, contentId: nil, contentType: nil)]
                store.selectedTab = .media
                dismiss()
            }
        }

        if entity.supports(Feature.turnOn) || entity.supports(Feature.turnOff) {
            PowerRow(entity: entity, domain: "media_player")
        }

        let sources = entity.attributes["source_list"]?.arrayValue?.compactMap(\.stringValue) ?? []
        if entity.supports(Feature.selectSource), !sources.isEmpty {
            ControlRow(title: "Source") {
                ForEach(sources, id: \.self) { source in
                    OptionButton(title: source, isSelected: entity.attributes["source"]?.stringValue == source) {
                        store.call("media_player", "select_source", on: entity, data: ["source": .string(source)])
                    }
                }
            }
        }
    }

    private func media(_ service: String, _ symbol: String) -> some View {
        Button {
            store.call("media_player", service, on: entity)
        } label: {
            Image(systemName: symbol).frame(width: 60)
        }
    }
}

private struct CoverControls: View {
    let entity: HAEntity
    @Environment(HomeStore.self) private var store

    private typealias Feature = HAFeature.Cover

    var body: some View {
        let domain = entity.domain
        let noun = domain == "valve" ? "valve" : "cover"
        ControlRow(title: "Position") {
            if entity.supports(Feature.open) {
                OptionButton(title: "Open", systemImage: "arrow.up", isSelected: entity.state == "open") {
                    store.call(domain, "open_\(noun)", on: entity)
                }
            }
            if entity.supports(Feature.stop) {
                OptionButton(title: "Stop", systemImage: "stop.fill") {
                    store.call(domain, "stop_\(noun)", on: entity)
                }
            }
            if entity.supports(Feature.close) {
                OptionButton(title: "Close", systemImage: "arrow.down", isSelected: entity.state == "closed") {
                    store.call(domain, "close_\(noun)", on: entity)
                }
            }
        }
        if entity.supports(Feature.setPosition) {
            ControlRow(title: "Set position") {
                ForEach([0, 25, 50, 75, 100], id: \.self) { position in
                    OptionButton(title: "\(position)%",
                                 isSelected: entity.attributes["current_position"]?.intValue == position) {
                        store.call(domain, "set_\(noun)_position", on: entity,
                                   data: ["position": .number(Double(position))])
                    }
                }
            }
        }
    }
}

private struct LockControls: View {
    let entity: HAEntity
    @Environment(HomeStore.self) private var store

    var body: some View {
        ControlRow(title: "Lock") {
            OptionButton(title: "Lock", systemImage: "lock.fill", isSelected: entity.state == "locked") {
                store.call("lock", "lock", on: entity)
            }
            OptionButton(title: "Unlock", systemImage: "lock.open.fill", isSelected: entity.state == "unlocked") {
                store.call("lock", "unlock", on: entity)
            }
            if entity.supports(1) {
                OptionButton(title: "Open", systemImage: "door.left.hand.open") {
                    store.call("lock", "open", on: entity)
                }
            }
        }
    }
}

private struct AlarmControls: View {
    let entity: HAEntity
    @Environment(HomeStore.self) private var store
    @State private var code = ""

    private var requiresCode: Bool {
        if let format = entity.attributes["code_format"], format != .null { return true }
        return false
    }

    var body: some View {
        if requiresCode {
            SecureField("Alarm code", text: $code)
                .keyboardType(.numberPad)
                .frame(maxWidth: 600)
        }
        ControlRow(title: "Alarm") {
            alarmButton("Disarm", "alarm_disarm", "shield", state: "disarmed")
            alarmButton("Arm Home", "alarm_arm_home", "house.fill", state: "armed_home")
            alarmButton("Arm Away", "alarm_arm_away", "figure.walk", state: "armed_away")
            alarmButton("Arm Night", "alarm_arm_night", "moon.fill", state: "armed_night")
        }
    }

    private func alarmButton(_ title: String, _ service: String, _ symbol: String, state: String) -> some View {
        OptionButton(title: title, systemImage: symbol, isSelected: entity.state == state) {
            let data: [String: JSONValue] = code.isEmpty ? [:] : ["code": .string(code)]
            store.call("alarm_control_panel", service, on: entity, data: data)
            code = ""
        }
    }
}

private struct VacuumControls: View {
    let entity: HAEntity
    @Environment(HomeStore.self) private var store

    var body: some View {
        ControlRow(title: "Vacuum") {
            OptionButton(title: "Start", systemImage: "play.fill", isSelected: entity.state == "cleaning") {
                store.call("vacuum", "start", on: entity)
            }
            OptionButton(title: "Pause", systemImage: "pause.fill", isSelected: entity.state == "paused") {
                store.call("vacuum", "pause", on: entity)
            }
            OptionButton(title: "Return to Dock", systemImage: "house.fill", isSelected: entity.state == "docked") {
                store.call("vacuum", "return_to_base", on: entity)
            }
        }
    }
}

private struct RunControls: View {
    let entity: HAEntity
    @Environment(HomeStore.self) private var store

    var body: some View {
        if case .service(let domain, let service) = entity.primaryAction {
            Button {
                store.call(domain, service, on: entity)
            } label: {
                Label(entity.domain.hasSuffix("button") ? "Press" : "Run", systemImage: "play.fill")
            }
        }
    }
}

/// Raw attributes, for sensors and anything without dedicated controls.
private struct AttributeList: View {
    let entity: HAEntity

    private static let hidden: Set<String> = [
        "friendly_name", "icon", "entity_picture", "supported_features", "supported_color_modes",
        "access_token", "attribution",
    ]

    private struct Row: Identifiable {
        let id: String
        let name: String
        let value: String
    }

    private var rows: [Row] {
        entity.attributes
            .filter { !Self.hidden.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { Row(id: $0.key, name: humanize($0.key), value: describe($0.value)) }
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Attributes").font(.headline).foregroundStyle(.secondary)
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.name).foregroundStyle(.secondary).frame(width: 420, alignment: .leading)
                        Text(row.value).lineLimit(3)
                    }
                    .font(.callout)
                }
            }
            // Make the list reachable with the remote so the sheet can scroll to it.
            .focusable()
        }
    }

    private func describe(_ value: JSONValue) -> String {
        switch value {
        case .string(let text): return text
        case .number(let number):
            return number.rounded() == number ? String(Int(number)) : String(number)
        case .bool(let flag): return flag ? "Yes" : "No"
        case .null: return "—"
        case .array(let items): return items.map(describe).joined(separator: ", ")
        case .object(let object):
            return object.sorted { $0.key < $1.key }.map { "\($0.key): \(describe($0.value))" }.joined(separator: ", ")
        }
    }
}

func humanize(_ value: String) -> String {
    let text = value.replacingOccurrences(of: "_", with: " ")
    return text.prefix(1).uppercased() + text.dropFirst()
}
