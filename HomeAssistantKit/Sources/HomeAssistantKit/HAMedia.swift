import Foundation

/// A node in Home Assistant's media tree (`media_source/browse_media` or
/// `media_player/browse_media`): a folder to expand, something to play, or both.
public struct HAMediaItem: Sendable, Hashable, Identifiable {
    public let title: String
    public let contentId: String
    public let contentType: String
    /// e.g. "directory", "music", "video", "image", "channel", "podcast".
    public let mediaClass: String
    public let canPlay: Bool
    public let canExpand: Bool
    /// Relative to the server, or an absolute URL on another site.
    public let thumbnail: String?
    public let children: [HAMediaItem]
    /// Items the server left out of `children`.
    public let notShown: Int

    public var id: String { "\(contentId)|\(contentType)|\(title)" }

    public init(_ json: JSONValue) {
        title = json["title"]?.stringValue ?? ""
        contentId = json["media_content_id"]?.stringValue ?? ""
        contentType = json["media_content_type"]?.stringValue ?? ""
        mediaClass = json["media_class"]?.stringValue ?? "directory"
        canPlay = json["can_play"]?.boolValue ?? false
        canExpand = json["can_expand"]?.boolValue ?? false
        thumbnail = json["thumbnail"]?.stringValue
        children = (json["children"]?.arrayValue ?? []).map(HAMediaItem.init)
        notShown = json["not_shown"]?.intValue ?? 0
    }

    /// Media-source IDs can be resolved to a URL the Apple TV can play itself;
    /// other IDs only mean something to the player they came from.
    public var isMediaSource: Bool { contentId.hasPrefix("media-source://") }

    public var kind: HAMediaKind {
        HAMediaKind(mediaClass: mediaClass, contentType: contentType)
    }
}

/// How the app presents playable media.
public enum HAMediaKind: Sendable, Equatable {
    case video, audio, image

    public init(mediaClass: String, contentType: String) {
        let type = contentType.lowercased()
        if type.hasPrefix("image/") || ["image", "photo"].contains(type) { self = .image; return }
        if type.hasPrefix("video/") || type.contains("mpegurl") { self = .video; return }
        if type.hasPrefix("audio/") { self = .audio; return }
        switch mediaClass {
        case "image": self = .image
        case "video", "movie", "episode", "tv_show", "season": self = .video
        default: self = .audio
        }
    }
}

/// A playable URL from `media_source/resolve_media`.
public struct HAResolvedMedia: Sendable, Hashable {
    /// Relative to the server or absolute; already signed when it needs auth.
    public let url: String
    public let mimeType: String

    public init?(_ json: JSONValue) {
        guard let url = json["url"]?.stringValue else { return nil }
        self.url = url
        mimeType = json["mime_type"]?.stringValue ?? ""
    }
}
