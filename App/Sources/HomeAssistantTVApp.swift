import SwiftUI

@main
struct HomeAssistantTVApp: App {
    @State private var store = HomeStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.resumeIfNeeded()
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
