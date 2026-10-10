import Foundation
import Testing
@testable import HomeAssistantKit

private func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

@Suite struct MediaTests {
    @Test func parsesBrowseTree() throws {
        let root = HAMediaItem(try json(#"""
        {"title": "Radio Browser", "media_class": "channel", "media_content_type": "music",
         "media_content_id": "media-source://radio_browser", "can_play": false, "can_expand": true,
         "thumbnail": null, "not_shown": 3,
         "children": [
           {"title": "Popular", "media_class": "directory", "media_content_type": "music",
            "media_content_id": "media-source://radio_browser/popular", "can_play": false, "can_expand": true},
           {"title": "Cool FM", "media_class": "music", "media_content_type": "audio/mpeg",
            "media_content_id": "media-source://radio_browser/a3c9", "can_play": true, "can_expand": false,
            "thumbnail": "https://example.com/logo.png"}]}
        """#))
        #expect(root.title == "Radio Browser")
        #expect(root.canExpand && !root.canPlay)
        #expect(root.notShown == 3)
        #expect(root.children.map(\.title) == ["Popular", "Cool FM"])
        let station = root.children[1]
        #expect(station.isMediaSource)
        #expect(station.kind == .audio)
        #expect(station.thumbnail == "https://example.com/logo.png")
    }

    @Test func classifiesMedia() {
        #expect(HAMediaKind(mediaClass: "video", contentType: "image/jpeg") == .image)
        #expect(HAMediaKind(mediaClass: "movie", contentType: "") == .video)
        #expect(HAMediaKind(mediaClass: "directory", contentType: "video/mp4") == .video)
        #expect(HAMediaKind(mediaClass: "music", contentType: "application/vnd.apple.mpegurl") == .video)
        #expect(HAMediaKind(mediaClass: "track", contentType: "music") == .audio)
        #expect(HAMediaKind(mediaClass: "image", contentType: "") == .image)
    }

    @Test func parsesResolvedMedia() throws {
        let media = try #require(HAResolvedMedia(try json(#"{"url": "/api/tts_proxy/x.mp3", "mime_type": "audio/mpeg"}"#)))
        #expect(media.url == "/api/tts_proxy/x.mp3")
        #expect(media.mimeType == "audio/mpeg")
        #expect(HAResolvedMedia(try json("{}")) == nil)
    }
}
