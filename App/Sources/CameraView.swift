import AVKit
import HomeAssistantKit
import SwiftUI

/// Full-screen camera view. Plays the live HLS stream when the `stream`
/// integration is available, otherwise refreshes snapshots every second.
struct CameraView: View {
    let entityId: String

    @Environment(HomeStore.self) private var store
    @State private var player: AVPlayer?
    @State private var streamUnavailable = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if streamUnavailable {
                AuthorizedImage(path: "/api/camera_proxy/\(entityId)", refreshInterval: .seconds(1))
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if player == nil, let entity = store.entity(entityId) {
                Text(entity.friendlyName)
                    .font(.title3.bold())
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(60)
            }
        }
        .task {
            do {
                let url = try await store.cameraStreamURL(for: entityId)
                let player = AVPlayer(url: url)
                player.isMuted = true
                player.play()
                self.player = player
            } catch {
                streamUnavailable = true
            }
        }
        .onDisappear {
            player?.pause()
        }
    }
}
