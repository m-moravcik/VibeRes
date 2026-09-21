import XCTest

/// Drives the real app through the accessibility API.
///
/// These exist because of one defect no unit test could have caught: the
/// resolution row — the app's primary action, and the *only* control in Simple
/// Mode, which is the default — was an `.onTapGesture` on an `HStack`. That is
/// not an accessibility element with an action, so VoiceOver announced a static
/// group and keyboard focus never reached it. Nothing in-process can tell that
/// apart from a `Button`; an assistive client sees nothing else.
///
/// XCTest rather than Swift Testing: `XCUIApplication` has no Swift Testing
/// equivalent.
///
/// Running these locally needs Accessibility permission for the test runner
/// (System Settings › Privacy & Security › Accessibility).
@MainActor
final class PopoverAccessibilityTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDown() async throws {
        app?.terminate()
        app = nil
    }

    /// Footer rows, which are the same on every machine whatever is plugged in.
    private static let footerLabels = ["Refresh", "Settings…", "About VibeRes", "Quit"]

    /// The menu-bar icon: VibeRes is `LSUIElement`, so there is no window and
    /// no Dock icon to go through. A `MenuBarExtra` status item is exposed as
    /// `StatusItem`, not as a `MenuBarItem` of the app's main menu.
    private var statusItem: XCUIElement {
        let item = app.statusItems.firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 15), "the menu-bar item never appeared")
        return item
    }

    /// Opens the popover and returns it.
    ///
    /// `MenuBarExtra(.window)` is an `NSPanel`, which the accessibility tree
    /// reports as a dialog rather than a window — `app.windows` is empty even
    /// with the popover on screen.
    @discardableResult
    private func openPopover() -> XCUIElement {
        statusItem.click()
        let popover = app.dialogs.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 10), "the popover never opened")
        dismissOnboardingIfPresent(in: popover)
        XCTAssertTrue(
            popover.buttons["Quit"].waitForExistence(timeout: 5),
            // Printed rather than described: the first CI run failed here with
            // the tour on screen, and a bare "not found" cost a round trip to
            // work that out.
            "the root view is not on screen. Popover contains:\n\(popover.debugDescription)"
        )
        return popover
    }

    /// A fresh account has never seen the welcome tour, and the tour takes over
    /// the whole popover until it is answered — which is why every test here
    /// failed the first time they ran on a CI runner and passed on a machine
    /// that had already dismissed it.
    ///
    /// Clicking Skip is the same thing a person would do, and it leaves the
    /// preference set exactly as their first launch would.
    private func dismissOnboardingIfPresent(in popover: XCUIElement) {
        let skip = popover.buttons["Skip"]
        guard skip.waitForExistence(timeout: 2) else { return }
        skip.click()
        XCTAssertTrue(
            popover.buttons["Quit"].waitForExistence(timeout: 5),
            "skipping the welcome tour should reveal the root view"
        )
    }

    /// Drills into the first display, or skips when this machine reports no
    /// display card to open.
    private func openFirstDisplay(in popover: XCUIElement) throws {
        // The card carries the display's name and its current mode, so its
        // label is the one containing a multiplication sign: profile pills are
        // just names and the footer rows are fixed verbs.
        let card = popover.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", "×")
        ).firstMatch
        try XCTSkipUnless(card.waitForExistence(timeout: 5), "no display card on this machine")
        card.click()
        XCTAssertTrue(
            popover.buttons["Back"].waitForExistence(timeout: 5),
            "clicking a display card did not drill in"
        )
    }

    /// The rows of the detail view. They carry their tooltip as the
    /// accessibility value — "Scaled (HiDPI) · 3600×2338 pixels · +12% screen
    /// space" — and nothing else on that screen does.
    private func resolutionRows(in popover: XCUIElement) -> [XCUIElement] {
        popover.buttons.allElementsBoundByIndex.filter {
            ($0.value as? String)?.contains("pixels") == true
        }
    }

    // MARK: The popover opens at all

    func testTheMenuBarItemOpensThePopover() throws {
        let popover = openPopover()
        XCTAssertTrue(
            popover.buttons["Quit"].waitForExistence(timeout: 5),
            "the root view should be on screen"
        )
    }

    func testFooterActionsAreButtons() throws {
        let popover = openPopover()
        for label in Self.footerLabels {
            XCTAssertTrue(
                popover.buttons[label].exists,
                "\(label) should be a button, not a decorated row"
            )
        }
    }

    func testSavingAProfileIsReachableWithoutAMouse() throws {
        let popover = openPopover()
        XCTAssertTrue(
            popover.buttons["Save current displays into a profile"].exists,
            "the Save pill should carry a label a screen reader can announce"
        )
    }

    // MARK: The regression guard

    func testResolutionRowsAreButtons() throws {
        let popover = openPopover()
        try openFirstDisplay(in: popover)

        XCTAssertFalse(
            resolutionRows(in: popover).isEmpty,
            "no resolution row is exposed as a button — the row is a tap gesture again"
        )
    }

    func testResolutionRowsAnnounceTheSizeTheyApply() throws {
        let popover = openPopover()
        try openFirstDisplay(in: popover)

        let rows = resolutionRows(in: popover)
        try XCTSkipIf(rows.isEmpty, "covered by testResolutionRowsAreButtons")

        for row in rows {
            // "1800 by 1169, 120 hertz" — a size, not "button".
            XCTAssertTrue(
                row.label.contains(" by "),
                "a resolution row announces \(row.label.isEmpty ? "nothing" : row.label)"
            )
        }
    }

    /// The tour is the first thing a new user meets, and it is the one screen
    /// that can trap them: it covers the popover entirely, so a Skip that does
    /// not work leaves the app with no reachable controls at all.
    func testTheWelcomeTourCanBeSkippedWhenItAppears() throws {
        let popover = openPopover()
        // `openPopover` already skipped it if this account had never seen it.
        // Either way the root view has to be what is on screen now.
        XCTAssertTrue(popover.buttons["Quit"].exists)
        XCTAssertFalse(popover.buttons["Skip"].exists, "the tour should not come back")
    }

    func testTheDetailViewCanBeLeftAgain() throws {
        let popover = openPopover()
        try openFirstDisplay(in: popover)

        let back = popover.buttons["Back"]
        XCTAssertTrue(back.isEnabled)
        back.click()
        XCTAssertTrue(
            popover.buttons["Quit"].waitForExistence(timeout: 5),
            "Back should return to the root view"
        )
    }
}
