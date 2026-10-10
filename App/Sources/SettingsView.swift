import HomeAssistantKit
import SwiftUI

struct SettingsView: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        Form {
            Section("Server") {
                LabeledContent("Home", value: store.locationName)
                LabeledContent("Address", value: store.config?.baseURL.absoluteString ?? "—")
                if !store.serverVersion.isEmpty {
                    LabeledContent("Version", value: store.serverVersion)
                }
                LabeledContent("Status", value: statusText)
                LabeledContent("Entities", value: "\(store.entities.count)")
            }

            Section {
                Button("Reconnect") { store.connect() }
                Button("Sign Out", role: .destructive) { store.signOut() }
            }
        }
        .frame(maxWidth: 1200)
    }

    private var statusText: String {
        switch store.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .reconnecting: return "Reconnecting…"
        case .failed(let message): return message
        case .signedOut: return "Signed out"
        }
    }
}
