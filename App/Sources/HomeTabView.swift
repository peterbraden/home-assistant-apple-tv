import HomeAssistantKit
import SwiftUI

struct HomeTabView: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        @Bindable var store = store
        ZStack(alignment: .top) {
            if store.entities.isEmpty {
                ConnectionStatusView()
            } else {
                TabView(selection: $store.selectedTab) {
                    if !store.rooms.isEmpty {
                        SectionedGridView(sections: store.rooms)
                            .tabItem { Label("Rooms", systemImage: "house.fill") }
                            .tag(HomeStore.Tab.rooms)
                    }
                    if !store.dashboards.isEmpty {
                        DashboardsView()
                            .tabItem { Label("Dashboards", systemImage: "chart.xyaxis.line") }
                            .tag(HomeStore.Tab.dashboards)
                    }
                    MediaTab()
                        .tabItem { Label("Media", systemImage: "play.rectangle.fill") }
                        .tag(HomeStore.Tab.media)
                    AssistView()
                        .tabItem { Label("Assist", systemImage: "waveform") }
                        .tag(HomeStore.Tab.assist)
                    if !store.availableCategories.isEmpty {
                        DevicesView()
                            .tabItem { Label("Devices", systemImage: "square.grid.2x2.fill") }
                            .tag(HomeStore.Tab.devices)
                    }
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                        .tag(HomeStore.Tab.settings)
                }
            }

            StatusBanner()
        }
        .sheet(item: $store.presentedEntity) { selection in
            EntityDetailView(entityId: selection.id).environment(store)
        }
        .fullScreenCover(isPresented: Binding(
            get: { store.playback.isPlayerPresented },
            set: { if !$0 { store.playback.playerDismissed() } }
        )) {
            PlayerView(playback: store.playback).ignoresSafeArea()
        }
        .fullScreenCover(isPresented: Binding(
            get: { store.playback.presentedImage != nil },
            set: { if !$0 { store.playback.presentedImage = nil } }
        )) {
            if let path = store.playback.presentedImage {
                MediaImageView(path: path).environment(store)
            }
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

/// Every entity by category, with a row of category buttons at the top.
/// One tab for all categories keeps the tab bar within tvOS's limit of 7 tabs.
private struct DevicesView: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        let categories = store.availableCategories
        let selected = categories.contains(store.selectedCategory) ? store.selectedCategory : categories.first
        SectionedGridView(sections: selected.map { store.sections(for: store.entities(in: $0)) } ?? []) {
            ControlRow(title: "Category") {
                ForEach(categories) { category in
                    OptionButton(title: category.title, systemImage: category.symbol, isSelected: category == selected) {
                        store.selectedCategory = category
                    }
                    // Lets UI tests confirm focus is on a category button before pressing select.
                    .accessibilityIdentifier("category-button")
                }
            }
        }
    }
}

struct SectionedGridView<Header: View>: View {
    let sections: [EntitySection]
    /// Content shown above the sections, scrolling with them.
    @ViewBuilder let header: Header

    @Environment(HomeStore.self) private var store
    @State private var selection: EntitySelection?
    @State private var cameraSelection: EntitySelection?

    private let columns = [GridItem(.adaptive(minimum: 340, maximum: 400), spacing: 48)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 50) {
                header
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

extension SectionedGridView where Header == EmptyView {
    init(sections: [EntitySection]) {
        self.init(sections: sections) { EmptyView() }
    }
}

struct EntitySelection: Identifiable, Hashable {
    let id: String
}
