import SwiftUI
import TVServices

@main
struct HomeAssistantTVApp: App {
    @State private var store = HomeStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .onOpenURL { store.open($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                store.resumeIfNeeded()
            case .background:
                // Ask tvOS to redraw the Top Shelf graphs with fresh data.
                TVTopShelfContentProvider.topShelfContentDidChange()
            default:
                break
            }
        }
    }
}

struct RootView: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        if store.config == nil {
            OnboardingView()
        } else {
            HomeTabView()
        }
    }
}
