import AVFoundation
import AVKit
import HomeAssistantKit
import Observation
import OSLog
import SwiftUI
import UIKit

private let logger = Logger(subsystem: "HomeAssistantTV", category: "Playback")

/// Plays media on the Apple TV itself. Uses the system player, which brings the
/// Siri Remote controls, Now Playing in Control Center and Picture in Picture.
/// Audio keeps playing while you browse the rest of the app.
@MainActor
@Observable
final class MediaPlayback: NSObject {
    struct NowPlaying: Equatable {
        let title: String
        let kind: HAMediaKind
    }

    private(set) var nowPlaying: NowPlaying?
    /// Cover art or station logo, drawn over the player for audio.
    private(set) var artwork: UIImage?
    /// Whether the full-screen player is showing.
    var isPlayerPresented = false
    /// A picture being shown full screen, as a server path or URL.
    var presentedImage: String?

    private(set) var isPictureInPictureActive = false
    @ObservationIgnored private(set) lazy var controller: AVPlayerViewController = {
        let controller = AVPlayerViewController()
        controller.delegate = self
        controller.allowsPictureInPicturePlayback = true
        // Audio has no picture of its own: show the artwork and title instead of black.
        if let overlay = controller.contentOverlayView {
            let host = UIHostingController(rootView: AudioArtworkView(playback: self))
            host.view.backgroundColor = .clear
            host.view.frame = overlay.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.addSubview(host.view)
        }
        return controller
    }()

    var player: AVPlayer? { controller.player }

    func play(url: URL, title: String, kind: HAMediaKind, artwork: Data? = nil) {
        guard kind != .image else {
            presentedImage = url.absoluteString
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: kind == .video ? .moviePlayback : .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logger.error("Audio session: \(error.localizedDescription)")
        }

        let item = AVPlayerItem(url: url)
        item.externalMetadata = Self.metadata(title: title, artwork: artwork)
        let player = AVPlayer(playerItem: item)
        controller.player?.pause()
        controller.player = player
        player.play()
        nowPlaying = NowPlaying(title: title, kind: kind)
        self.artwork = artwork.flatMap(UIImage.init(data:))
        isPlayerPresented = true
        logger.notice("Playing \(kind == .video ? "video" : "audio") \(title, privacy: .public)")
    }

    /// Adds artwork once it has loaded, so playback doesn't wait for it.
    func setArtwork(_ data: Data) {
        guard let item = player?.currentItem, let title = nowPlaying?.title else { return }
        item.externalMetadata = Self.metadata(title: title, artwork: data)
        artwork = UIImage(data: data)
    }

    /// Called when the full-screen player is closed with the Menu button.
    func playerDismissed() {
        isPlayerPresented = false
        // Video stops unless it moved into Picture in Picture; audio carries on.
        if nowPlaying?.kind == .video, !isPictureInPictureActive {
            stop()
        }
    }

    func stop() {
        controller.player?.pause()
        controller.player = nil
        nowPlaying = nil
        artwork = nil
        isPlayerPresented = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    var isPlaying: Bool { (player?.rate ?? 0) > 0 }

    func togglePause() {
        guard let player else { return }
        if player.rate > 0 { player.pause() } else { player.play() }
    }

    private static func metadata(title: String, artwork: Data?) -> [AVMetadataItem] {
        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = title as NSString
        titleItem.extendedLanguageTag = "und"
        var items: [AVMetadataItem] = [titleItem]
        if let artwork {
            let artworkItem = AVMutableMetadataItem()
            artworkItem.identifier = .commonIdentifierArtwork
            artworkItem.value = artwork as NSData
            artworkItem.dataType = kCMMetadataBaseDataType_JPEG as String
            artworkItem.extendedLanguageTag = "und"
            items.append(artworkItem)
        }
        return items
    }
}

extension MediaPlayback: AVPlayerViewControllerDelegate {
    nonisolated func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        MainActor.assumeIsolated {
            isPictureInPictureActive = true
            // Close the full-screen player so the rest of the app is usable under the PiP window.
            isPlayerPresented = false
        }
    }

    nonisolated func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        MainActor.assumeIsolated {
            isPictureInPictureActive = false
            if !isPlayerPresented { stop() }
        }
    }

    nonisolated func playerViewController(
        _ playerViewController: AVPlayerViewController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        MainActor.assumeIsolated {
            isPlayerPresented = true
        }
        completionHandler(true)
    }
}

/// Artwork and title shown over the player while audio plays.
private struct AudioArtworkView: View {
    let playback: MediaPlayback

    var body: some View {
        if let nowPlaying = playback.nowPlaying, nowPlaying.kind == .audio {
            VStack(spacing: 40) {
                Group {
                    if let artwork = playback.artwork {
                        Image(uiImage: artwork).resizable().scaledToFit()
                    } else {
                        Image(systemName: "radio").font(.system(size: 160)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 500, height: 500)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(radius: 30)
                Text(nowPlaying.title).font(.title2.bold())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: [Color(white: 0.15), .black], startPoint: .top, endPoint: .bottom))
            .environment(\.colorScheme, .dark)
        }
    }
}

/// Shows the shared player controller full screen.
struct PlayerView: UIViewControllerRepresentable {
    let playback: MediaPlayback

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        playback.controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
}
