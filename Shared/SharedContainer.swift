import Foundation

/// State shared between the app and the Top Shelf extension through the App Group.
enum SharedContainer {
    static let appGroup = "group.uk.co.peterbraden.HomeAssistantTV"

    /// URL the Top Shelf item opens; the app shows the Dashboards tab.
    static let dashboardsURL = URL(string: "homeassistanttv://dashboards")!

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// The dashboard view shown on the Top Shelf, as "<dashboard id>/<view id>".
    /// nil picks the first view that has a graph.
    static var topShelfView: String? {
        get { defaults.string(forKey: "topShelfView") }
        set { defaults.set(newValue, forKey: "topShelfView") }
    }

    static var directory: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.temporaryDirectory
    }
}
