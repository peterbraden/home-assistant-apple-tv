import Foundation
import HomeAssistantKit
import Network
import Observation

/// Finds Home Assistant instances on the local network via Bonjour (`_home-assistant._tcp`).
@MainActor
@Observable
final class ServerDiscovery {
    struct Server: Identifiable, Hashable {
        let name: String
        let url: URL
        var id: URL { url }
    }

    private(set) var servers: [Server] = []
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_home-assistant._tcp", domain: nil),
            using: .tcp
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let servers = results.compactMap(Self.server(from:))
            Task { @MainActor in
                self?.servers = Array(Set(servers)).sorted { $0.name < $1.name }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    private nonisolated static func server(from result: NWBrowser.Result) -> Server? {
        guard case .bonjour(let txt) = result.metadata else { return nil }
        let candidates = [txt["internal_url"], txt["base_url"], txt["external_url"]]
        guard let address = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }),
              let url = HAServerConfig.normalizedURL(from: address)
        else { return nil }

        var name = txt["location_name"] ?? ""
        if name.isEmpty, case .service(let serviceName, _, _, _) = result.endpoint {
            name = serviceName
        }
        return Server(name: name.isEmpty ? "Home Assistant" : name, url: url)
    }
}
