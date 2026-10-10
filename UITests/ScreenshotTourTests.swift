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
