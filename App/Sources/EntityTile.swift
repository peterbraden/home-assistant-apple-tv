import HomeAssistantKit
import SwiftUI

/// A focusable card for one entity. Clicking runs its primary action
/// (toggle, run scene) or opens details; long-press always offers details.
struct EntityTile: View {
    let entity: HAEntity
    let showDetails: () -> Void

    @Environment(HomeStore.self) private var store

    var body: some View {
        Button(action: primaryAction) {
            if entity.domain == "camera" {
                CameraTileContent(entity: entity)
            } else {
                StandardTileContent(entity: entity, name: store.registry.name(for: entity))
            }
        }
        .buttonStyle(.card)
        .contextMenu {
            Button("Details", systemImage: "info.circle", action: showDetails)
            if case .service(domain: "homeassistant", service: _) = entity.primaryAction {
                Button("Turn On", systemImage: "power") {
                    store.call("homeassistant", "turn_on", on: entity)
                }
                Button("Turn Off", systemImage: "poweroff") {
                    store.call("homeassistant", "turn_off", on: entity)
                }
            }
        }
    }

    private func primaryAction() {
        if !store.performPrimaryAction(on: entity) {
            showDetails()
        }
    }
}

private struct StandardTileContent: View {
    let entity: HAEntity
    let name: HAEntityName

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: entity.symbolName)
                .font(.system(size: 44, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(entity.tint)
                .frame(height: 50)
            Spacer(minLength: 0)
            if let device = name.device {
                Text(device)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Text(name.name)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.primary)
            Text(entity.displayState)
                .font(.callout)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 340, height: 260, alignment: .leading)
        .background(entity.isActive ? entity.tint.opacity(0.18) : .clear)
        .opacity(entity.isUnavailable ? 0.5 : 1)
    }
}

private struct CameraTileContent: View {
    let entity: HAEntity

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if entity.isUnavailable {
                Color.black.opacity(0.3)
                Image(systemName: "video.slash.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AuthorizedImage(
                    path: entity.entityPicture ?? "/api/camera_proxy/\(entity.entityId)",
                    contentMode: .fill,
                    refreshInterval: .seconds(10)
                )
                .frame(width: 340, height: 260)
                .clipped()
            }

            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                Text(entity.friendlyName)
                    .font(.headline)
                    .lineLimit(1)
                if entity.isUnavailable {
                    Text(entity.displayState).font(.callout).opacity(0.7)
                }
            }
            .foregroundStyle(.white)
            .padding(24)
        }
        .frame(width: 340, height: 260)
    }
}

extension HAEntity {
    /// Accent color for the entity's icon; lights use their actual color.
    var tint: Color {
        guard isActive else { return .secondary }
        switch domain {
        case "light":
            if let rgb = attributes["rgb_color"]?.arrayValue?.compactMap(\.doubleValue), rgb.count == 3 {
                return Color(red: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255)
            }
            return .yellow
        case "climate":
            switch state {
            case "cool": return .cyan
            case "heat": return .orange
            default: return .green
            }
        case "lock": return .red
        case "alarm_control_panel": return state == "triggered" ? .red : .green
        case "media_player": return .purple
        case "cover", "valve", "binary_sensor": return .orange
        default: return .yellow
        }
    }
}
