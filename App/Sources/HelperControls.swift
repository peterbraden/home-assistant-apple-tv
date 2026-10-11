import HomeAssistantKit
import SwiftUI

/// Enable, disable or run an automation.
struct AutomationControls: View {
    let entity: HAEntity
    @Environment(HomeStore.self) private var store

    var body: some View {
        ControlRow(title: "Automation") {
            OptionButton(title: "Enabled", systemImage: "checkmark.circle", isSelected: entity.state == "on") {
                store.call("automation", "turn_on", on: entity)
            }
            OptionButton(title: "Disabled", systemImage: "xmark.circle", isSelected: entity.state == "off") {
                store.call("automation", "turn_off", on: entity)
            }
            // Runs the actions now, skipping the triggers but still checking conditions.
            Button("Run Now", systemImage: "play.fill") {
                store.call("automation", "trigger", on: entity)
            }
        }
        if let last = entity.attributes["last_triggered"]?.stringValue,
           let date = HADate.parse(last) {
            Text("Last triggered \(date, format: .relative(presentation: .named))")
                .foregroundStyle(.secondary)
        }
    }
}

/// Choose an option of a `select` or `input_select`.
struct SelectControls: View {
    let entity: HAEntity
    @Environment(HomeStore.self) private var store

    var body: some View {
        let options = entity.attributes["options"]?.arrayValue?.compactMap(\.stringValue) ?? []
        if !options.isEmpty {
            ControlRow(title: "Option") {
                ForEach(options, id: \.self) { option in
                    OptionButton(title: option, isSelected: entity.state == option) {
                        store.call(entity.domain, "select_option", on: entity, data: ["option": .string(option)])
                    }
                }
            }
        }
    }
}

/// Step a `number` or `input_number` up and down within its range.
struct NumberControls: View {
    let entity: HAEntity
    @Environment(HomeStore.self) private var store

    private var minimum: Double { entity.attributes["min"]?.doubleValue ?? 0 }
    private var maximum: Double { entity.attributes["max"]?.doubleValue ?? 100 }
    private var step: Double { max(entity.attributes["step"]?.doubleValue ?? 1, 0.001) }

    var body: some View {
        if let value = Double(entity.state) {
            ControlRow(title: "Value") {
                Button { set(value - step) } label: { Image(systemName: "minus").frame(width: 60) }
                    .disabled(value - step < minimum - step / 2)
                Text(entity.displayState)
                    .font(.title3.monospacedDigit())
                    .frame(minWidth: 160)
                Button { set(value + step) } label: { Image(systemName: "plus").frame(width: 60) }
                    .disabled(value + step > maximum + step / 2)
                // Quick jumps across the range, when it's wide enough to need them.
                if (maximum - minimum) / step > 10 {
                    ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { fraction in
                        let target = (minimum + (maximum - minimum) * fraction) / step
                        let snapped = target.rounded() * step
                        OptionButton(title: HAEntity.format(snapped), isSelected: abs(value - snapped) < step / 2) {
                            set(snapped)
                        }
                    }
                }
            }
            Text("Range \(HAEntity.format(minimum)) – \(HAEntity.format(maximum))")
                .foregroundStyle(.secondary)
        }
    }

    private func set(_ value: Double) {
        let clamped = min(max(value, minimum), maximum)
        store.call(entity.domain, "set_value", on: entity, data: ["value": .number(clamped)])
    }
}

/// Versions of an update entity, with a confirmed Install button.
struct UpdateControls: View {
    let entity: HAEntity
    @Environment(HomeStore.self) private var store
    @State private var confirming = false

    var body: some View {
        let installed = entity.attributes["installed_version"]?.stringValue
        let latest = entity.attributes["latest_version"]?.stringValue
        VStack(alignment: .leading, spacing: 12) {
            if let installed { LabeledContent("Installed", value: installed) }
            if let latest { LabeledContent("Latest", value: latest) }
            if let summary = entity.attributes["release_summary"]?.stringValue, !summary.isEmpty {
                Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(6)
            }
        }
        .frame(maxWidth: 900, alignment: .leading)

        if entity.attributes["in_progress"]?.boolValue == true {
            Label("Installing…", systemImage: "arrow.down.circle")
        } else if entity.state == "on", entity.supports(1) {
            Button("Install \(latest ?? "Update")", systemImage: "arrow.down.circle") { confirming = true }
                .confirmationDialog("Install \(entity.friendlyName) \(latest ?? "")?", isPresented: $confirming) {
                    Button("Install") { store.call("update", "install", on: entity) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Home Assistant may restart the device or itself while it installs.")
                }
        }
    }
}
