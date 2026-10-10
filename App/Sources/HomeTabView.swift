import HomeAssistantKit
import SwiftUI

struct HomeTabView: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        ZStack(alignment: .top) {
            if store.entities.isEmpty {
                ConnectionStatusView()
            } else {
                TabView {
                    if !store.rooms.isEmpty {
                        SectionedGridView(sections: store.rooms)
                            .tabItem { Label("Rooms", systemImage: "house.fill") }
                    }
                    ForEach(store.tabCategories) { category in
                        SectionedGridView(sections: store.sections(for: store.entities(in: category)))
                            .tabItem { Label(category.title, systemImage: category.symbol) }
                    }
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                }
            }

            StatusBanner()
        }
        .alert("Couldn't complete action", isPresented: Binding(
            get: { store.actionError != nil },
            set: { if !$0 { store.actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.actionError ?? "")
        }
    }
}

/// Full-screen state shown before the first successful load.
private struct ConnectionStatusView: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        VStack(spacing: 40) {
            switch store.connectionState {
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 100))
                    .foregroundStyle(.yellow)
                Text(message).font(.title2)
                HStack(spacing: 40) {
                    Button("Try Again") { store.connect() }
                    Button("Sign Out", role: .destructive) { store.signOut() }
                }
            case .reconnecting(let message):
                ProgressView()
                Text("Can't reach Home Assistant").font(.title2)
                Text(message).foregroundStyle(.secondary)
                Button("Sign Out", role: .destructive) { store.signOut() }
            default:
                ProgressView()
                Text("Connecting to Home Assistant…").font(.title2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A small banner shown while the live connection is down but cached states are visible.
private struct StatusBanner: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        if !store.entities.isEmpty, case .reconnecting = store.connectionState {
            Label("Reconnecting to Home Assistant…", systemImage: "wifi.exclamationmark")
                .font(.callout)
                .padding(.horizontal, 30)
                .padding(.vertical, 14)
                .background(.thinMaterial, in: Capsule())
                .padding(.top, 20)
                .allowsHitTesting(false)
        }
    }
}

struct SectionedGridView: View {
    let sections: [EntitySection]

    @Environment(HomeStore.self) private var store
    @State private var selection: EntitySelection?
    @State private var cameraSelection: EntitySelection?

    private let columns = [GridItem(.adaptive(minimum: 340, maximum: 400), spacing: 48)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 50) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 24) {
                        if !section.title.isEmpty {
                            Text(section.title)
                                .font(.title3.bold())
                                .foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 48) {
                            ForEach(section.entities) { entity in
                                EntityTile(entity: entity) {
                                    if entity.domain == "camera" {
                                        cameraSelection = EntitySelection(id: entity.entityId)
                                    } else {
                                        selection = EntitySelection(id: entity.entityId)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 40)
        }
        .sheet(item: $selection) { selection in
            EntityDetailView(entityId: selection.id)
                .environment(store)
        }
        .fullScreenCover(item: $cameraSelection) { selection in
            CameraView(entityId: selection.id)
                .environment(store)
        }
    }
}

struct EntitySelection: Identifiable, Hashable {
    let id: String
}
