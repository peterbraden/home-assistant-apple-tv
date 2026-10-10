import HomeAssistantKit
import SwiftUI

/// Shows the user's Lovelace dashboards, one view at a time.
struct DashboardsView: View {
    @Environment(HomeStore.self) private var store
    @State private var dashboardID: String?
    @State private var viewID: String?
    @AppStorage("keepDashboardsAwake") private var keepAwake = false

    var body: some View {
        let dashboards = store.dashboards
        let dashboard = dashboards.first { $0.id == dashboardID } ?? dashboards.first
        let views = dashboard?.config.views ?? []
        let view = views.first { $0.id == viewID } ?? views.first

        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                if dashboards.count > 1 {
                    ControlRow(title: "Dashboard") {
                        ForEach(dashboards) { item in
                            OptionButton(title: item.dashboard.title, isSelected: item.id == dashboard?.id) {
                                dashboardID = item.id
                                viewID = nil
                            }
                        }
                    }
                }
                if views.count > 1 {
                    ControlRow(title: "View") {
                        ForEach(views) { item in
                            OptionButton(title: item.title, isSelected: item.id == view?.id) {
                                viewID = item.id
                            }
                            // Lets UI tests confirm focus is on a view button before pressing select.
                            .accessibilityIdentifier("dashboard-view-button")
                        }
                    }
                }
                if let view {
                    LovelaceViewContent(view: view)
                        // Recreate cards when switching views so their data reloads.
                        .id("\(dashboard?.id ?? "")/\(view.id)")
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 40)
        }
        // Optionally hold off the screen saver, so a dashboard can stay up as a wall display.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepAwake }
        .onChange(of: keepAwake) { _, newValue in UIApplication.shared.isIdleTimerDisabled = newValue }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

/// Lays out a view's cards according to its type.
struct LovelaceViewContent: View {
    let view: LovelaceView

    private let columns = [GridItem(.adaptive(minimum: 760), spacing: 40, alignment: .top)]

    var body: some View {
        switch view.layout {
        case .panel:
            if let card = view.cards.first {
                LovelaceCardView(card: card, isPanel: true)
            }
        case .sections:
            VStack(alignment: .leading, spacing: 40) {
                ForEach(view.sections) { section in
                    // Sections spanning several columns use the full width.
                    LazyVGrid(columns: section.columnSpan > 1 ? [GridItem(.flexible())] : columns,
                              alignment: .leading, spacing: 40) {
                        ForEach(section.cards) { card in
                            LovelaceCardView(card: card)
                        }
                    }
                }
            }
        case .masonry, .sidebar:
            LazyVGrid(columns: columns, alignment: .leading, spacing: 40) {
                ForEach(view.cards) { card in
                    LovelaceCardView(card: card)
                }
            }
        }
        if view.allCards.isEmpty {
            Text("This view has no cards.").foregroundStyle(.secondary)
        }
    }
}
