import HomeAssistantKit
import SwiftUI
import UIKit

/// Doorbell rings and new Home Assistant notifications, shown over the app.
struct AlertsOverlay: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        ZStack {
            if let alert = store.doorbellAlert {
                DoorbellCard(alert: alert)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
            }
            if let notification = store.notificationBanner {
                NotificationBanner(notification: notification)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(60)
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring, value: store.doorbellAlert)
        .animation(.spring, value: store.notificationBanner)
        .task(id: store.notificationBanner) {
            guard store.notificationBanner != nil else { return }
            try? await Task.sleep(for: .seconds(8))
            store.notificationBanner = nil
        }
        .task(id: store.doorbellAlert) {
            guard let alert = store.doorbellAlert else { return }
            store.playback.showDoorbellActions(for: alert, store: store)
            try? await Task.sleep(for: .seconds(120))
            if store.doorbellAlert == alert { store.doorbellAlert = nil }
        }
        .onChange(of: store.doorbellAlert) { _, alert in
            if alert == nil { store.playback.clearDoorbellActions() }
        }
    }
}

private struct DoorbellCard: View {
    let alert: DoorbellAlert

    @Environment(HomeStore.self) private var store
    @FocusState private var focusDismiss: Bool

    var body: some View {
        VStack(spacing: 30) {
            Label("Doorbell", systemImage: "bell.and.waves.left.and.right.fill")
                .font(.title2.bold())
                .symbolEffect(.bounce, options: .repeat(3))
            Text(alert.name).font(.title3).foregroundStyle(.secondary)
            HStack(spacing: 30) {
                ForEach(store.doorLocks) { lock in
                    // Opening a door is deliberate: focus starts on Dismiss, never here.
                    Button("Open \(lock.friendlyName)", systemImage: "lock.open.fill") {
                        store.call("lock", "unlock", on: lock)
                        store.doorbellAlert = nil
                    }
                }
                if let camera = store.availableCameras.first {
                    Button("Show Camera", systemImage: "video.fill") {
                        store.doorbellAlert = nil
                        store.presentedCamera = EntitySelection(id: camera.entityId)
                    }
                }
                Button("Dismiss", systemImage: "xmark") { store.doorbellAlert = nil }
                    .focused($focusDismiss)
            }
        }
        .padding(50)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 36))
        .shadow(radius: 40)
        .focusSection()
        .defaultFocus($focusDismiss, true)
        .onAppear { focusDismiss = true }
        .onExitCommand { store.doorbellAlert = nil }
    }
}

private struct NotificationBanner: View {
    let notification: HAPersistentNotification

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            Image(systemName: "bell.badge.fill").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text(notification.title ?? "Home Assistant").font(.headline)
                Text(notification.message).font(.callout).foregroundStyle(.secondary).lineLimit(4)
            }
        }
        .padding(36)
        .frame(maxWidth: 700, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .shadow(radius: 30)
    }
}

extension MediaPlayback {
    /// While a doorbell alert is up, the full-screen player shows its actions as buttons.
    func showDoorbellActions(for alert: DoorbellAlert, store: HomeStore) {
        var actions = store.doorLocks.map { lock in
            UIAction(title: "Open \(lock.friendlyName)", image: UIImage(systemName: "lock.open.fill")) { _ in
                store.call("lock", "unlock", on: lock)
                store.doorbellAlert = nil
            }
        }
        actions.append(UIAction(title: "Dismiss Doorbell", image: UIImage(systemName: "bell.slash")) { _ in
            store.doorbellAlert = nil
        })
        controller.contextualActions = actions
    }

    func clearDoorbellActions() {
        controller.contextualActions = []
    }
}
