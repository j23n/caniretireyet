import XCTest

/// Opens each screen of the app with a made-up library and keeps a
/// screenshot of it, which CI uploads (.github/workflows/ci.yml, "UI tests
/// and screenshots"). Each screen is one launch: `-uiTestLibrary` and
/// `-uiTestScreen`, read by the app's `UITestLaunch` (Debug builds), pick
/// the library, kept in memory, and the screen to start on; the main plan
/// is calculated with the real planner. A screen that crashes, or never
/// shows, fails its test.
///
/// XCTest rather than Swift Testing: UI tests need it.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOverview() {
        let app = launch(library: "example", screen: "overview")
        waitForScreen(app, showing: text("Net worth", in: app), named: "overview")
        keepScreenshot(of: app, named: "overview")
    }

    @MainActor
    func testPlan() {
        let app = launch(library: "example", screen: "plan")
        waitForScreen(app, showing: answer(in: app), named: "plan", timeout: 240, settle: 30)
        keepScreenshot(of: app, named: "plan")
        scrollDown(app)
        keepScreenshot(of: app, named: "plan-chapter")
    }

    @MainActor
    func testWhatIf() {
        let app = launch(library: "example", screen: "whatIf")
        waitForScreen(app, showing: text("What if…", in: app), named: "what-if", settle: 30)
        pause(seconds: 5)
        keepScreenshot(of: app, named: "what-if")
    }

    @MainActor
    func testProgress() {
        let app = launch(library: "example", screen: "progress")
        waitForScreen(app, showing: text("Year by year", in: app), named: "progress")
        keepScreenshot(of: app, named: "progress")
        scrollDown(app)
        scrollDown(app)
        keepScreenshot(of: app, named: "progress-year")
    }

    /// A savings plan since 2018 and check-ins from October 2025: the years
    /// before are valued from prices. Then 2018, chosen with ‹, its card
    /// and its details.
    @MainActor
    func testProgressWithALongHistory() {
        let app = launch(library: "longHistory", screen: "progress")
        waitForScreen(app, showing: text("Year by year", in: app), named: "progress-long")
        keepScreenshot(of: app, named: "progress-long")
        #if os(iOS)
        // On iPhone ‹ is in the chosen year's header, under the strip.
        scrollDown(app)
        #endif
        let earlier = app.buttons["Earlier"].firstMatch
        if earlier.waitForExistence(timeout: 10) {
            for _ in 0..<8 where earlier.isHittable && earlier.isEnabled {
                earlier.tap()
            }
        }
        pause(seconds: 2)
        #if os(iOS)
        scrollUp(app)
        #endif
        keepScreenshot(of: app, named: "progress-long-2018")
        scrollDown(app)
        scrollDown(app)
        keepScreenshot(of: app, named: "progress-long-2018-year")
        XCTAssertTrue(app.state == .runningForeground, "The app stopped after going back to 2018.")
    }

    /// Progress on a device set to German in Germany. The app is in English
    /// only, so its sentences are English: their month names should be too,
    /// while amounts follow the region ("1.234 €").
    @MainActor
    func testProgressInGermany() {
        let app = launch(library: "example", screen: "progress",
                         arguments: ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"])
        waitForScreen(app, showing: text("Year by year", in: app), named: "progress-germany")
        keepScreenshot(of: app, named: "progress-germany")
        scrollDown(app)
        scrollDown(app)
        keepScreenshot(of: app, named: "progress-germany-year")
    }

    // MARK: Helpers

    @MainActor
    private func launch(library: String, screen: String, arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestLibrary", library, "-uiTestScreen", screen] + arguments
        #if os(macOS)
        // No windows restored from the launch before, nor an offer to.
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        #endif
        app.launch()
        return app
    }

    /// A text on screen: its words are its label on iPhone, its value on the Mac.
    @MainActor
    private func text(_ words: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", words, words)).firstMatch
    }

    /// The plan's answer, once it's calculated.
    @MainActor
    private func answer(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["plan.answer"].firstMatch
    }

    /// Waits for the screen: on iPhone for `element`; on the Mac, whose
    /// texts the tests can't always find, for the window, then `settle`
    /// seconds for it to fill in. Fails the test (with a screenshot,
    /// `missing-<name>`) when it never shows or the app stopped.
    @MainActor
    private func waitForScreen(_ app: XCUIApplication, showing element: XCUIElement, named name: String,
                               timeout: TimeInterval = 60, settle: TimeInterval = 8,
                               file: StaticString = #filePath, line: UInt = #line) {
        #if os(macOS)
        let window = app.windows.firstMatch
        let shown = window.waitForExistence(timeout: timeout)
        if shown { pause(seconds: settle) }
        #else
        let shown = element.waitForExistence(timeout: timeout)
        #endif
        if !shown, app.windows.firstMatch.exists { keepScreenshot(of: app, named: "missing-\(name)") }
        XCTAssertTrue(app.state == .runningForeground, "\(name): the app isn't running.", file: file, line: line)
        XCTAssertTrue(shown, "\(name): \(element) never showed.", file: file, line: line)
    }

    /// Lets the screen settle for `seconds`.
    @MainActor
    private func pause(seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "The screen settles")], timeout: seconds)
    }

    /// Scrolls the page down, to what's under the strip: on iPhone a drag
    /// from above the strip, so it moves the page, not a card's read-out.
    @MainActor
    private func scrollDown(_ app: XCUIApplication) {
        #if os(macOS)
        app.windows.firstMatch.scroll(byDeltaX: 0, deltaY: -700)
        #else
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)))
        #endif
    }

    /// Scrolls the page back up.
    @MainActor
    private func scrollUp(_ app: XCUIApplication) {
        #if os(macOS)
        app.windows.firstMatch.scroll(byDeltaX: 0, deltaY: 700)
        #else
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        #endif
    }

    /// The app's window on the Mac, the screen on iPhone, kept with the
    /// test's results.
    @MainActor
    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        #if os(macOS)
        let screenshot = app.windows.firstMatch.screenshot()
        #else
        let screenshot = XCUIScreen.main.screenshot()
        #endif
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
