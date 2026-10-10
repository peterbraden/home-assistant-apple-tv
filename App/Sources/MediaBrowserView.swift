import HomeAssistantKit
import SwiftUI

/// Browses Home Assistant's media sources (radio, local media, cameras, Jellyfin,
/// DLNA…) and the libraries of media players.
struct MediaTab: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.mediaPath) {
            MediaFolderView(location: .source(nil)) {
                NowPlayingBar()
                if !store.browsablePlayers.isEmpty {
                    ControlRow(title: "Speakers & TVs") {
                        ForEach(store.browsablePlayers) { player in
                            NavigationLink(value: MediaLocation.player(entityId: player.entityId, contentId: nil, contentType: nil)) {
                                Label(player.friendlyName, systemImage: player.symbolName)
                            }
                            .accessibilityIdentifier("media-folder")
                        }
                    }
                }
            }
            .navigationDestination(for: MediaLocation.self) { location in
                MediaFolderView(location: location) { EmptyView() }
            }
        }
    }
}

/// One level of a media tree, as a grid of tiles.
struct MediaFolderView<Header: View>: View {
    let location: MediaLocation
    @ViewBuilder let header: Header

    @Environment(HomeStore.self) private var store
    @State private var folder: HAMediaItem?
    @State private var error: String?

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 340), spacing: 48)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                header
                if let folder {
                    if folder.title != "Media sources", !folder.title.isEmpty {
                        Text(folder.title).font(.title2.bold())
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 48) {
                        ForEach(folder.children) { child in
                            MediaTile(item: child, location: location)
                        }
                    }
                    if folder.children.isEmpty {
                        Text("Nothing here.").foregroundStyle(.secondary)
                    }
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 40)
        }
        .task(id: location) {
            do {
                folder = try await store.browseMedia(location)
                error = nil
            } catch {
                self.error = Self.describe(error)
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        // Home Assistant explains why a source can't be browsed, e.g. "Jellyfin integration not loaded".
        if case HAError.commandFailed(_, let message) = error { return message }
        return error.localizedDescription
    }
}

/// A folder opens; anything playable plays on the Apple TV when it can, or is
/// offered to the player it belongs to. Long-press to send it to another player.
private struct MediaTile: View {
    let item: HAMediaItem
    let location: MediaLocation

    @Environment(HomeStore.self) private var store
    @State private var confirmPlayer: HAEntity?

    /// The media player whose library this item came from, if any.
    private var owner: HAEntity? {
        if case .player(let entityId, _, _) = location { return store.entity(entityId) }
        return nil
    }

    var body: some View {
        Group {
            if item.canExpand {
                NavigationLink(value: childLocation) { label }
                    .accessibilityIdentifier("media-folder")
            } else {
                Button(action: activate) { label }
                    .accessibilityIdentifier("media-play")
            }
        }
        .buttonStyle(.card)
        .contextMenu {
            if item.canPlay {
                if owner == nil, item.isMediaSource {
                    Button("Play on Apple TV", systemImage: "appletv") { Task { await store.playHere(item) } }
                }
                ForEach(owner.map { [$0] } ?? store.mediaTargets) { player in
                    Button("Play on \(player.friendlyName)", systemImage: player.symbolName) {
                        store.play(item, on: player)
                    }
                }
            }
        }
        .confirmationDialog("Play “\(item.title)”?", isPresented: Binding(
            get: { confirmPlayer != nil }, set: { if !$0 { confirmPlayer = nil } }
        ), presenting: confirmPlayer) { player in
            Button("Play on \(player.friendlyName)") { store.play(item, on: player) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var childLocation: MediaLocation {
        switch location {
        case .source:
            return .source(item.contentId)
        case .player(let entityId, _, _):
            return .player(entityId: entityId, contentId: item.contentId, contentType: item.contentType)
        }
    }

    private func activate() {
        guard item.canPlay else { return }
        if let owner {
            // Playing from a speaker's library makes noise in the house: confirm first.
            confirmPlayer = owner
        } else if item.isMediaSource {
            Task { await store.playHere(item) }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color.secondary.opacity(0.15)
                if let thumbnail = item.thumbnail {
                    AuthorizedImage(path: thumbnail, contentMode: .fit)
                        .padding(item.mediaClass == "app" ? 40 : 0)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 300, height: 200)
            .clipped()

            Text(item.title)
                .font(.callout)
                .lineLimit(2)
                .frame(width: 270, height: 80, alignment: .topLeading)
                .padding(.horizontal, 15)
                .padding(.top, 12)
        }
        .frame(width: 300)
    }

    private var symbol: String {
        if item.canExpand { return "folder.fill" }
        switch item.kind {
        case .video: return "film"
        case .image: return "photo"
        case .audio: return item.mediaClass == "channel" || item.contentId.contains("radio") ? "radio" : "music.note"
        }
    }
}

/// What's playing on the Apple TV, with buttons to show the player or stop.
private struct NowPlayingBar: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        if let nowPlaying = store.playback.nowPlaying {
            HStack(spacing: 30) {
                Label(nowPlaying.title, systemImage: nowPlaying.kind == .video ? "film" : "waveform")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button("Show Player", systemImage: "play.rectangle") { store.playback.isPlayerPresented = true }
                Button("Stop", systemImage: "stop.fill") { store.playback.stop() }
            }
            .padding(30)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

/// A picture from a media source, full screen.
struct MediaImageView: View {
    let path: String

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AuthorizedImage(path: path, contentMode: .fit).ignoresSafeArea()
        }
    }
}
