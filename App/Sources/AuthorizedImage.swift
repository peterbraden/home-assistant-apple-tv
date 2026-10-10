import HomeAssistantKit
import SwiftUI
import UIKit

/// Loads an image from Home Assistant with the bearer token, optionally refreshing it.
struct AuthorizedImage: View {
    let path: String
    var contentMode: ContentMode = .fit
    var refreshInterval: Duration?

    @Environment(HomeStore.self) private var store
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .task(id: path) {
            await load()
        }
    }

    private func load() async {
        guard let client = store.client else { return }
        while !Task.isCancelled {
            do {
                let data = try await client.data(at: path)
                if let loaded = UIImage(data: data) {
                    image = loaded
                    failed = false
                }
            } catch {
                if image == nil { failed = true }
            }
            guard let refreshInterval else { return }
            try? await Task.sleep(for: refreshInterval)
        }
    }
}
