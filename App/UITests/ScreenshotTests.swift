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
        waitFor(text("Net worth", in: app), in: app, named: "overview")
        keepScreenshot(of: app, named: "overview")
    }

    @MainActor
    func testPlan() {
        let app = launch(library: "example", screen: "plan")
        waitFor(answer(in: app), in: app, named: "plan", timeout: 240)
        keepScreenshot(of: app, named: "plan")
        scrollDown(app)
        keepScreenshot(of: app, named: "plan-chapter")
    }

    @MainActor
    func testWhatIf() {
        let app = launch(library: "example", screen: "whatIf")
        waitFor(text("What if…", in: app), in: app, named: "what-if")
        _ = answer(in: app).waitForExistence(timeout: 240)
        keepScreenshot(of: app, named: "what-if")
    }

    @MainActor
    func testProgress() {
        let app = launch(library: "example", screen: "progress")
        waitFor(text("Year by year", in: app), in: app, named: "progress")
        keepScreenshot(of: app, named: "progress")
        scrollDown(app)
        keepScreenshot(of: app, named: "progress-year")
    }

    /// A savings plan since 2018 and check-ins from October 2025: the years
    /// before are valued from prices. Then the early years, laid out and
    /// scrolled to, and the first one chosen.
    @MainActor
    func testProgressWithALongHistory() {
        let app = launch(library: "longHistory", screen: "progress")
        waitFor(text("Year by year", in: app), in: app, named: "progress-long")
        keepScreenshot(of: app, named: "progress-long")
        let years = app.scrollViews["progress.years"].firstMatch
        scrollToStart(years)
        let show = app.buttons["Show"].firstMatch
        if show.waitForExistence(timeout: 5), !show.isHittable {
            scrollDown(app)
        }
        if show.exists, show.isHittable {
            show.tap()
            scrollToStart(years)
        }
        keepScreenshot(of: app, named: "progress-long-early")
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "2018")).firstMatch
        if first.waitForExistence(timeout: 5), first.isHittable {
            first.tap()
            scrollDown(app)
            keepScreenshot(of: app, named: "progress-long-2018")
        }
        XCTAssertTrue(app.state == .runningForeground, "The app stopped after scrolling back.")
    }

    // MARK: Helpers

    @MainActor
    private func launch(library: String, screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestLibrary", library, "-uiTestScreen", screen]
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

    /// Scrolls a strip back to its first card.
    @MainActor
    private func scrollToStart(_ strip: XCUIElement) {
        guard strip.waitForExistence(timeout: 5) else { return }
        #if os(macOS)
        strip.scroll(byDeltaX: 6_000, deltaY: 0)
        #else
        for _ in 0..<6 { strip.swipeRight(velocity: .fast) }
        #endif
    }

    /// Scrolls the page down, to what's under the strip.
    @MainActor
    private func scrollDown(_ app: XCUIApplication) {
        #if os(macOS)
        app.windows.firstMatch.scroll(byDeltaX: 0, deltaY: -700)
        #else
        app.swipeUp(velocity: .slow)
        #endif
    }

    /// Waits for `element`, failing the test (with a screenshot, `missing-<name>`)
    /// when it never shows or the app stopped.
    @MainActor
    private func waitFor(_ element: XCUIElement, in app: XCUIApplication, named name: String,
                         timeout: TimeInterval = 60, file: StaticString = #filePath, line: UInt = #line) {
        let shown = element.waitForExistence(timeout: timeout)
        if !shown { keepScreenshot(of: app, named: "missing-\(name)") }
        XCTAssertTrue(app.state == .runningForeground, "The app isn't running.", file: file, line: line)
        XCTAssertTrue(shown, "\(name): \(element) never showed.", file: file, line: line)
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
