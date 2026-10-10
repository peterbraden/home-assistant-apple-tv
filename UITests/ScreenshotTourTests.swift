import XCTest

/// Signs in to a real Home Assistant server and screenshots each tab.
///
/// Only moves focus left/right along the tab bar, so it never operates devices.
/// Run with `TEST_RUNNER_HA_URL`, `TEST_RUNNER_HA_TOKEN` and optionally
/// `TEST_RUNNER_SCREENSHOT_DIR` set in the environment of `xcodebuild test`.
final class ScreenshotTourTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTabTour() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["HA_URL"], let token = environment["HA_TOKEN"] else {
            throw XCTSkip("Set TEST_RUNNER_HA_URL and TEST_RUNNER_HA_TOKEN to run against a server.")
        }

        let app = XCUIApplication()
        app.launchEnvironment = ["HA_URL": url, "HA_TOKEN": token, "HA_AUTOCONNECT": "1"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Never reached the main screen")
        sleep(2)
        XCTAssertEqual(tabBar.buttons.allElementsBoundByIndex.last?.label, "Settings",
                       "Settings must always be reachable; tvOS drops tabs beyond 7")

        // Keep moving right until focus stops changing: the tab bar scrolls,
        // so off-screen tabs aren't counted up front.
        var previous = focusedTabName(in: tabBar)
        save("tab-0-\(previous)")
        for index in 1...20 {
            XCUIRemote.shared.press(.right)
            sleep(3)
            let current = focusedTabName(in: tabBar)
            if current == previous { break }
            save("tab-\(index)-\(current)")
            previous = current
        }
    }

    /// Opens the Dashboards tab and screenshots each view of the first dashboard,
    /// also scrolled down. Select is only pressed after checking a view button
    /// has focus, so the test can't operate a device by accident.
    func testDashboardTour() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["HA_URL"], let token = environment["HA_TOKEN"] else {
            throw XCTSkip("Set TEST_RUNNER_HA_URL and TEST_RUNNER_HA_TOKEN to run against a server.")
        }

        let app = XCUIApplication()
        app.launchEnvironment = ["HA_URL": url, "HA_TOKEN": token, "HA_AUTOCONNECT": "1"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Never reached the main screen")
        sleep(2)
        let remote = XCUIRemote.shared
        remote.press(.right)
        sleep(2)
        try XCTSkipUnless(focusedTabName(in: tabBar) == "Dashboards", "No Dashboards tab")

        // Only focus moves from here on, except the guarded select below.
        let viewButton = "dashboard-view-button"
        func moveFocus(_ button: XCUIRemote.Button, until done: () -> Bool, maxPresses: Int = 6) {
            for _ in 0..<maxPresses where !done() {
                remote.press(button)
                sleep(1)
            }
        }
        moveFocus(.down) { focusedElement(in: app).identifier == viewButton }
        let titles = app.buttons.matching(identifier: viewButton).allElementsBoundByIndex.map(\.label)
            .map { $0.replacingOccurrences(of: "Selected, ", with: "") }
        XCTAssertFalse(titles.isEmpty, "No dashboard view buttons found")

        for (index, title) in titles.enumerated() {
            // Steer left/right along the view row until the wanted button has focus.
            for _ in 0..<titles.count {
                let current = focusedElement(in: app)
                guard current.identifier == viewButton,
                      let position = titles.firstIndex(where: { current.label.hasSuffix($0) })
                else { break }
                if position == index { break }
                remote.press(position < index ? .right : .left)
                sleep(1)
            }

            let focused = focusedElement(in: app)
            // Never press select unless a dashboard view button has focus:
            // anything else could switch a real device.
            guard focused.exists, focused.identifier == viewButton, focused.label.hasSuffix(title) else {
                XCTFail("Expected the “\(title)” view button to have focus, found “\(focused.label)”; not pressing select")
                return
            }
            remote.press(.select)
            sleep(8)
            let name = title.replacingOccurrences(of: " ", with: "_")
            save("dash-\(index)-\(name)")
            remote.press(.down)
            sleep(1)
            remote.press(.down)
            sleep(2)
            save("dash-\(index)-\(name)-scrolled")

            moveFocus(.up) { focusedElement(in: app).identifier == viewButton }
            guard focusedElement(in: app).identifier == viewButton else {
                XCTFail("Couldn't get back to the view buttons")
                return
            }
        }
    }

    /// Opens the Assist tab and types a search. Only moves focus and types:
    /// never presses select, so nothing is sent to Assist and no device is operated.
    func testAssistSearch() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["HA_URL"], let token = environment["HA_TOKEN"] else {
            throw XCTSkip("Set TEST_RUNNER_HA_URL and TEST_RUNNER_HA_TOKEN to run against a server.")
        }

        let app = XCUIApplication()
        app.launchEnvironment = ["HA_URL": url, "HA_TOKEN": token, "HA_AUTOCONNECT": "1"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "Never reached the main screen")
        sleep(2)
        for _ in 0..<6 where focusedTabName(in: tabBar) != "Assist" {
            XCUIRemote.shared.press(.right)
            sleep(2)
        }
        XCTAssertEqual(focusedTabName(in: tabBar), "Assist")
        save("assist-empty")

        XCUIRemote.shared.press(.down)
        sleep(2)
        app.typeText(environment["SEARCH_TEXT"] ?? "light")
        sleep(3)
        save("assist-search")
    }

    /// Highlights the app on the Home screen so tvOS shows its Top Shelf, then
    /// screenshots it. Only moves focus; never presses select.
    func testTopShelf() throws {
        // Launching and then leaving the app makes it ask tvOS to refresh the Top Shelf;
        // otherwise tvOS may wait up to 10 minutes after an install.
        XCUIApplication().launch()
        sleep(8)
        let home = XCUIApplication(bundleIdentifier: "com.apple.HeadBoard")
        home.activate()
        sleep(3)
        let remote = XCUIRemote.shared
        for _ in 0..<10 where !focusedElement(in: home).label.contains("Home Assistant") {
            remote.press(.right)
            sleep(1)
        }
        try XCTSkipUnless(focusedElement(in: home).label.contains("Home Assistant"),
                          "Couldn't find the app in the top row")
        sleep(25)  // The extension fetches data and renders the image.
        save("top-shelf")
    }

    /// The focused element's label and identifier; empty when nothing has focus.
    private func focusedElement(in app: XCUIApplication) -> (exists: Bool, label: String, identifier: String) {
        let element = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        guard element.exists else { return (false, "", "") }
        return (true, element.label, element.identifier)
    }

    private func focusedTabName(in tabBar: XCUIElement) -> String {
        let focused = tabBar.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return focused.exists ? focused.label.replacingOccurrences(of: " ", with: "_") : "unknown"
    }

    private func save(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        if let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
            try? screenshot.pngRepresentation.write(to: url)
        }
    }
}
