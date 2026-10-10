import HomeAssistantKit
import SwiftUI

/// Search devices, or send the same words to Home Assistant's Assist.
/// Holding the Siri Remote's mic button in the search field dictates.
/// Text is only sent to Assist when "Ask Assist" is pressed, so searching
/// for a device by name never operates it.
struct AssistView: View {
    @Environment(HomeStore.self) private var store
    @State private var query = ""
    @State private var exchanges: [Exchange] = []
    @State private var conversationId: String?
    @State private var isAsking = false

    struct Exchange: Identifiable {
        let id = UUID()
        let question: String
        var answer: String?
        var isError = false
    }

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = store.search(trimmed)

        NavigationStack {
            SectionedGridView(
                sections: results.isEmpty ? [] : [EntitySection(id: "results", title: "Devices", entities: results)]
            ) {
                VStack(alignment: .leading, spacing: 30) {
                    if !trimmed.isEmpty {
                        Button {
                            ask(trimmed)
                        } label: {
                            Label("Ask Assist: “\(trimmed)”", systemImage: "waveform")
                        }
                        .disabled(isAsking)
                    } else if exchanges.isEmpty {
                        Text("Search for a device, or ask Home Assistant to do something, like “turn off the lights” or “what's the temperature outside?”. Hold the mic button on the remote to dictate.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 1200, alignment: .leading)
                    }

                    ForEach(exchanges.reversed()) { exchange in
                        ExchangeView(exchange: exchange)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search or ask Home Assistant")
        }
    }

    private func ask(_ text: String) {
        let index = exchanges.count
        exchanges.append(Exchange(question: text))
        isAsking = true
        Task {
            defer { isAsking = false }
            do {
                let response = try await store.ask(text, conversationId: conversationId)
                conversationId = response.conversationId
                exchanges[index].answer = response.speech.isEmpty ? "Done." : response.speech
                exchanges[index].isError = response.kind == .error
                query = ""
            } catch {
                exchanges[index].answer = error.localizedDescription
                exchanges[index].isError = true
            }
        }
    }
}

private struct ExchangeView: View {
    let exchange: AssistView.Exchange

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(exchange.question)
                .font(.headline)
                .foregroundStyle(.secondary)
            if let answer = exchange.answer {
                Label(answer, systemImage: exchange.isError ? "exclamationmark.bubble" : "bubble.left")
                    .font(.title3)
                    .foregroundStyle(exchange.isError ? .orange : .primary)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: 1200, alignment: .leading)
    }
}
