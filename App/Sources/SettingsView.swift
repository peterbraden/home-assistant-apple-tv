import HomeAssistantKit
import SwiftUI
import TVServices

struct SettingsView: View {
    @Environment(HomeStore.self) private var store
    @State private var topShelfView = SharedContainer.topShelfView ?? ""
    @AppStorage("keepDashboardsAwake") private var keepDashboardsAwake = false
    @AppStorage("assistPipeline") private var assistPipeline = ""

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

            if store.assistPipelines.count > 1 {
                Section {
                    Picker("Assist", selection: $assistPipeline) {
                        Text("Preferred (\(store.preferredAssistPipeline?.name ?? "default"))").tag("")
                        ForEach(store.assistPipelines, id: \.id) { pipeline in
                            Text(pipeline.name).tag(pipeline.id)
                        }
                    }
                } footer: {
                    Text("The voice assistant that answers in the Assist tab.")
                }
            }

            if !store.dashboards.isEmpty {
                Section {
                    Toggle("Keep Dashboards on Screen", isOn: $keepDashboardsAwake)
                } footer: {
                    Text("Stops the screen saver starting while a dashboard is showing.")
                }
            }

            if !store.topShelfChoices.isEmpty {
                Section {
                    Picker("Top Shelf", selection: $topShelfView) {
                        Text("Automatic").tag("")
                        ForEach(store.topShelfChoices, id: \.id) { choice in
                            Text(choice.title).tag(choice.id)
                        }
                    }
                    .onChange(of: topShelfView) { _, newValue in
                        SharedContainer.topShelfView = newValue.isEmpty ? nil : newValue
                        TVTopShelfContentProvider.topShelfContentDidChange()
                    }
                } footer: {
                    Text("The dashboard graphs shown behind the app when it's in the top row of the Home screen.")
                }
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
