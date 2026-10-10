import HomeAssistantKit
import SwiftUI

/// Renders one Lovelace card natively. Unsupported card types show a placeholder.
struct LovelaceCardView: View {
    let card: LovelaceCard
    var isPanel = false

    var body: some View {
        switch card.type {
        case "history-graph":
            HistoryGraphCard(card: card, chartHeight: isPanel ? 640 : 380)
        case "statistics-graph":
            StatisticsGraphCard(card: card, chartHeight: isPanel ? 640 : 380)
        case "statistic":
            StatisticCard(card: card)
        case "sensor":
            SensorCard(card: card)
        case "entities":
            EntitiesCard(card: card)
        case "entity", "gauge":
            EntityValueCard(card: card)
        case "tile", "button", "light", "thermostat", "media-control", "humidifier":
            if let entityId = card.entity {
                EntityTilesCard(title: nil, entityIds: [entityId])
            }
        case "glance":
            EntityTilesCard(title: card.title, entityIds: card.entities.map(\.entityId))
        case "picture-entity", "picture-glance":
            PictureEntityCard(card: card)
        case "markdown":
            MarkdownCard(card: card)
        case "heading":
            Text(card.string("heading") ?? "").font(.title3.bold())
        case "vertical-stack", "grid":
            VStack(alignment: .leading, spacing: 30) {
                ForEach(card.cards) { LovelaceCardView(card: $0) }
            }
        case "horizontal-stack":
            HStack(alignment: .top, spacing: 30) {
                ForEach(card.cards) { LovelaceCardView(card: $0) }
            }
        default:
            CardContainer(title: card.title) {
                Label("“\(card.type)” cards aren't supported on Apple TV yet.", systemImage: "square.dashed")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The background and title shared by all cards. Cards without buttons are made
/// focusable so the remote can scroll to them, with a ring showing focus.
struct CardContainer<Content: View>: View {
    let title: String?
    var focusable = true
    @ViewBuilder let content: Content

    @FocusState private var isFocused: Bool

    var body: some View {
        let body = VStack(alignment: .leading, spacing: 24) {
            if let title, !title.isEmpty {
                Text(title).font(.title3.bold())
            }
            content
        }
        .padding(30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))

        if focusable {
            body
                .focusable()
                .focused($isFocused)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(.white.opacity(isFocused ? 0.8 : 0), lineWidth: 4)
                )
                .scaleEffect(isFocused ? 1.01 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        } else {
            body
        }
    }
}

// MARK: - Entity cards

private struct EntitiesCard: View {
    let card: LovelaceCard
    @Environment(HomeStore.self) private var store
    @State private var selection: EntitySelection?

    var body: some View {
        CardContainer(title: card.title, focusable: false) {
            VStack(spacing: 12) {
                ForEach(card.entities, id: \.entityId) { ref in
                    if let entity = store.entity(ref.entityId) {
                        EntityRow(entity: entity, name: ref.name) {
                            selection = EntitySelection(id: entity.entityId)
                        }
                    }
                }
            }
        }
        .sheet(item: $selection) { selection in
            EntityDetailView(entityId: selection.id).environment(store)
        }
    }
}

/// A full-width row: icon, name and state. Clicking runs the primary action.
private struct EntityRow: View {
    let entity: HAEntity
    let name: String?
    let showDetails: () -> Void

    @Environment(HomeStore.self) private var store

    var body: some View {
        Button {
            if !store.performPrimaryAction(on: entity) { showDetails() }
        } label: {
            HStack(spacing: 24) {
                Image(systemName: entity.symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(entity.tint)
                    .frame(width: 50)
                Text(name ?? entity.friendlyName)
                    .lineLimit(1)
                Spacer()
                Text(entity.displayState)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .opacity(entity.isUnavailable ? 0.5 : 1)
        }
        .contextMenu {
            Button("Details", systemImage: "info.circle", action: showDetails)
        }
    }
}

private struct EntityTilesCard: View {
    let title: String?
    let entityIds: [String]
    @Environment(HomeStore.self) private var store
    @State private var selection: EntitySelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let title { Text(title).font(.title3.bold()) }
            ScrollView(.horizontal) {
                HStack(spacing: 40) {
                    ForEach(entityIds.compactMap(store.entity), id: \.entityId) { entity in
                        EntityTile(entity: entity) { selection = EntitySelection(id: entity.entityId) }
                    }
                }
                .padding(20)
            }
            .scrollClipDisabled()
        }
        .sheet(item: $selection) { selection in
            EntityDetailView(entityId: selection.id).environment(store)
        }
    }
}

/// A single entity's state, large.
private struct EntityValueCard: View {
    let card: LovelaceCard
    @Environment(HomeStore.self) private var store

    var body: some View {
        let entity = card.entity.flatMap(store.entity)
        CardContainer(title: card.string("name") ?? entity.map { store.registry.name(for: $0).name }) {
            if let entity {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Image(systemName: entity.symbolName)
                        .font(.title2)
                        .foregroundStyle(entity.tint)
                    Text(entity.displayState)
                        .font(.system(size: 64, weight: .light))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            } else {
                Text("Entity not found").foregroundStyle(.secondary)
            }
        }
    }
}

private struct PictureEntityCard: View {
    let card: LovelaceCard
    @Environment(HomeStore.self) private var store
    @State private var showCamera = false

    var body: some View {
        let entity = card.entity.flatMap(store.entity)
        Button {
            if entity?.domain == "camera", entity?.isUnavailable == false { showCamera = true }
        } label: {
            ZStack(alignment: .bottomLeading) {
                if let entity, !entity.isUnavailable,
                   let path = entity.entityPicture ?? (entity.domain == "camera" ? "/api/camera_proxy/\(entity.entityId)" : nil) {
                    AuthorizedImage(path: path, contentMode: .fill, refreshInterval: .seconds(10))
                } else {
                    Color.black.opacity(0.3)
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                if let entity {
                    VStack(alignment: .leading) {
                        Text(card.string("name") ?? entity.friendlyName).font(.headline)
                        if card.config["show_state"]?.boolValue != false {
                            Text(entity.displayState).font(.callout).opacity(0.8)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(30)
                }
            }
            .frame(height: 420)
            .clipped()
        }
        .buttonStyle(.card)
        .fullScreenCover(isPresented: $showCamera) {
            if let entityId = card.entity {
                CameraView(entityId: entityId).environment(store)
            }
        }
    }
}

private struct MarkdownCard: View {
    let card: LovelaceCard

    var body: some View {
        let lines = (card.string("content") ?? "").components(separatedBy: "\n")
        let content = VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("#") {
                    Text(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces))
                        .font(.title2.bold())
                } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(Self.inline(line))
                }
            }
        }
        if card.config["text_only"]?.boolValue == true {
            content
        } else {
            CardContainer(title: card.title) { content }
        }
    }

    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
