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

    #if os(iOS)
    /// The plan's results are kept on the device and come back when the app
    /// opens again, up to date, without calculating (UI.md, "Calculating"):
    /// calculated in one launch, quit, then shown in the next, which
    /// calculates nothing (`-uiTestNoRun`). On iPhone: on CI's Mac, the app
    /// opened again inside one test ran without a window. The code it checks
    /// is the same on the Mac.
    @MainActor
    func testKeptResultsComeBack() {
        let folder = UUID().uuidString
        let first = launch(library: "example", screen: "plan", arguments: ["-uiTestKeepResults", folder])
        XCTAssertTrue(answer(in: first).waitForExistence(timeout: 240), "The plan was never calculated.")
        // The results are written to the device just after the run.
        pause(seconds: 5)
        first.terminate()

        let app = launch(library: "example", screen: "plan",
                         arguments: ["-uiTestKeepResults", folder, "-uiTestNoRun"])
        let shown = answer(in: app).waitForExistence(timeout: 60)
        pause(seconds: 5)
        keepScreenshot(of: app, named: "plan-kept")
        XCTAssertTrue(shown, "The kept results didn't come back: the plan asks to be calculated.")
        XCTAssertFalse(app.buttons["plan.outOfDate"].exists, "The kept results came back out of date.")
        XCTAssertFalse(app.buttons["plan.calculate"].exists, "The plan asks to be calculated.")
    }
    #endif

    #if os(iOS)
    /// On iPhone a swipe scrolls the plan's chapters sideways, also when it
    /// starts on a card's graph, which a touch and hold reads instead.
    @MainActor
    func testChaptersScrollSideways() {
        let app = launch(library: "example", screen: "plan")
        waitForScreen(app, showing: answer(in: app), named: "plan-swipe", timeout: 240, settle: 5)
        let strip = app.descendants(matching: .any)["plan.chapters"].firstMatch
        let last = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Chapter 6,")).firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 10), "The chapters never showed.")
        XCTAssertTrue(last.exists, "There's no sixth chapter.")
        // Where the card is, not whether it can be hit: XCTest can't tell
        // that of a card off screen.
        let edge = strip.frame.maxX
        XCTAssertGreaterThan(last.frame.minX, edge, "The last chapter is on screen before scrolling.")
        for _ in 0..<6 where last.frame.minX >= edge {
            strip.swipeLeft()
            pause(seconds: 1)
        }
        keepScreenshot(of: app, named: "plan-swiped")
        XCTAssertLessThan(last.frame.minX, edge, "Swiping the chapters didn't scroll them.")
    }
    #endif

    @MainActor
    func testWhatIf() {
        #if os(macOS)
        // As you would: the toolbar's What If, which opens it beside the plan.
        let app = launch(library: "example", screen: "plan")
        waitForScreen(app, showing: text("What if", in: app), named: "what-if", settle: 30)
        click(app.buttons["Show What If"].firstMatch)
        #else
        let app = launch(library: "example", screen: "whatIf")
        waitForScreen(app, showing: text("What if", in: app), named: "what-if", settle: 30)
        #endif
        pause(seconds: 5)
        keepScreenshot(of: app, named: "what-if")
    }

    @MainActor
    func testProgress() {
        let app = launch(library: "example", screen: "progress")
        waitForScreen(app, showing: text("Year by year", in: app), named: "progress")
        chooseProgressOnTheMac(app)
        keepScreenshot(of: app, named: "progress")
        scrollDown(app)
        scrollDown(app, from: belowTheStrip)
        keepScreenshot(of: app, named: "progress-year")
    }

    /// A savings plan since 2018 and check-ins from October 2025: the years
    /// before are valued from prices. Then 2018, chosen with ‹, its card
    /// and its details.
    @MainActor
    func testProgressWithALongHistory() {
        let app = launch(library: "longHistory", screen: "progress")
        waitForScreen(app, showing: text("Year by year", in: app), named: "progress-long")
        chooseProgressOnTheMac(app)
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
        keepScreenshot(of: app, named: "progress-long-2018")
        #if os(macOS)
        scrollDown(app)
        #endif
        scrollDown(app, from: belowTheStrip)
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
        chooseProgressOnTheMac(app)
        keepScreenshot(of: app, named: "progress-germany")
        scrollDown(app)
        scrollDown(app, from: belowTheStrip)
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

    /// On the Mac, chooses Progress in the toolbar's Plan | Progress, as
    /// you would: the launch's request hasn't reached the screen there.
    @MainActor
    private func chooseProgressOnTheMac(_ app: XCUIApplication) {
        #if os(macOS)
        // A segment is a radio button on the Mac; a button, should that change.
        let segment = app.radioButtons["Progress"].firstMatch
        click(segment.waitForExistence(timeout: 10) ? segment : app.buttons["Progress"].firstMatch)
        pause(seconds: 3)
        #endif
    }

    #if os(macOS)
    /// Clicks `element` once it shows; nothing when it doesn't.
    @MainActor
    private func click(_ element: XCUIElement) {
        if element.waitForExistence(timeout: 10), element.isHittable { element.click() }
    }
    #endif

    /// Lets the screen settle for `seconds`.
    @MainActor
    private func pause(seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "The screen settles")], timeout: seconds)
    }

    /// Where on iPhone a drag that moves the page starts, once the page
    /// has moved up by one drag: under the strip of cards, on the chosen
    /// card's details. A drag that starts on a card mostly reads its line.
    private let belowTheStrip: CGFloat = 0.75

    /// Scrolls the page down by about a quarter of the screen: on iPhone a
    /// drag starting `from` that far down the screen, off the strip of cards
    /// (the default is above it, before the page has moved); on the Mac a
    /// scroll over the page's scroll bar, at the window's right edge, where
    /// no strip takes it.
    @MainActor
    private func scrollDown(_ app: XCUIApplication, from start: CGFloat = 0.3) {
        #if os(macOS)
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.6))
            .scroll(byDeltaX: 0, deltaY: -300)
        #else
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start - 0.28)))
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
