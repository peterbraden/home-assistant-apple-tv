import HomeAssistantKit
import SwiftUI

struct OnboardingView: View {
    @Environment(HomeStore.self) private var store
    @State private var discovery = ServerDiscovery()
    @State private var address = ""
    @State private var token = ""
    @State private var isConnecting = false
    @State private var error: String?

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "house.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(.tint)
                Text("Home Assistant")
                    .font(.largeTitle.bold())
                Text("Control your home from the couch. Connect to your Home Assistant server to get started.")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    Text("To create an access token:")
                        .font(.headline)
                    Text("1. Open Home Assistant on your phone or computer.")
                    Text("2. Go to your Profile → Security.")
                    Text("3. Under Long-lived access tokens, choose Create token.")
                    Text("Tip: select the token field and use the keyboard notification on your iPhone to paste it.")
                        .padding(.top, 8)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 24)
            }
            .frame(maxWidth: 700, alignment: .leading)

            VStack(alignment: .leading, spacing: 30) {
                if !discovery.servers.isEmpty {
                    Text("Found on your network")
                        .font(.headline)
                    ForEach(discovery.servers) { server in
                        Button {
                            address = server.url.absoluteString
                        } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(server.name)
                                    Text(server.url.absoluteString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: address == server.url.absoluteString
                                    ? "checkmark.circle.fill" : "house")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                Text("Server")
                    .font(.headline)
                TextField("Address, e.g. homeassistant.local:8123", text: $address)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("Long-lived access token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        if isConnecting {
                            ProgressView()
                        }
                        Text(isConnecting ? "Connecting…" : "Connect")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isConnecting || address.isEmpty || token.isEmpty)
            }
            .frame(maxWidth: 800)
        }
        .padding(80)
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
    }

    private func connect() async {
        isConnecting = true
        error = nil
        defer { isConnecting = false }
        do {
            let config = try HAServerConfig(address: address, accessToken: token)
            try await store.signIn(with: config)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
