import XCTest

/// The welcome tour's profile step saves the connected displays as a profile.
///
/// Driven through the real popover because the risk is in the wiring, not the
/// store call: the tour's Next button is the default action, so Return in the
/// name field could advance the tour instead of saving, and only the running
/// app shows which one wins.
///
/// Profiles go to a scratch directory and the tour is forced on through the
/// argument domain, so the run leaves the user's catalog and preferences alone.
@MainActor
final class OnboardingProfileStepTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-VibeRes.OnboardingShown", "NO"]
        // The sandboxed runner cannot access /private/tmp, and the app cannot
        // write into the runner's container. Let the app create its scratch
        // directory; leave it in /private/tmp for the system to clear.
        app.launchEnvironment["VIBERES_PROFILE_DIR"] = "/private/tmp/VibeResUITests-onboarding-\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        app?.terminate()
        app = nil
    }

    func testSaveButtonSavesTheCurrentDisplaysAndTheTourShowsThePill() throws {
        let popover = try openProfileStep()
        let field = popover.textFields.firstMatch
        let name = try XCTUnwrap(field.value as? String)
        XCTAssertFalse(name.isEmpty, "the name field should come prefilled with a suggestion")

        popover.buttons["Save profile"].click()
        XCTAssertTrue(
            savedNote(in: popover).waitForExistence(timeout: 5),
            "no confirmation after Save. Popover contains:\n\(popover.debugDescription)"
        )

        finishTourAndAssertProfilePill(name, in: popover)
    }

    func testReturnInTheNameFieldSavesAndStaysOnTheStep() throws {
        let popover = try openProfileStep()
        let field = popover.textFields.firstMatch
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("Desk\r")

        XCTAssertTrue(
            savedNote(in: popover).waitForExistence(timeout: 5),
            "Return in the name field did not save. Popover contains:\n\(popover.debugDescription)"
        )
        XCTAssertTrue(staticText(in: popover, beginningWith: "Step 2 of 3").exists, "Return also advanced the tour")
        finishTourAndAssertProfilePill("Desk", in: popover)
    }

    func testFailedSaveShowsAnErrorWithoutAConfirmation() throws {
        // The app cannot create a catalog on the read-only system volume.
        app.launchEnvironment["VIBERES_PROFILE_DIR"] = "/System/VibeResUITests-unwritable-\(UUID().uuidString)"
        let popover = try openProfileStep()
        popover.buttons["Save profile"].click()

        XCTAssertTrue(
            staticText(in: popover, beginningWith: "The profile could not be saved.").waitForExistence(timeout: 5),
            "no inline error after the catalog write failed"
        )
        XCTAssertFalse(savedNote(in: popover).exists, "a failed save must not announce success")
        XCTAssertTrue(popover.textFields.firstMatch.isEnabled, "a failed save must allow retry")
    }

    // MARK: - Helpers

    private func openProfileStep() throws -> XCUIElement {
        app.launch()
        let item = app.statusItems.firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 15), "the menu-bar item never appeared")
        try XCTSkipUnless(item.waitUntilHittable(timeout: 5), "a menu bar manager is hiding the Debug build's item")
        item.click()

        let popover = app.dialogs.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 10), "the popover never opened")
        XCTAssertTrue(popover.buttons["Next"].waitForExistence(timeout: 5), "the welcome tour is not on screen")
        popover.buttons["Next"].click()
        XCTAssertTrue(
            popover.textFields.firstMatch.waitForExistence(timeout: 5),
            "no name field on the profile step. Popover contains:\n\(popover.debugDescription)"
        )
        XCTAssertFalse(savedNote(in: popover).exists, "an unsaved profile must not announce success")
        XCTAssertFalse(
            staticText(in: popover, beginningWith: "Some monitors report the same identity.").exists,
            "an unsaved profile must not announce an ambiguity warning"
        )
        return popover
    }

    private func finishTourAndAssertProfilePill(_ name: String, in popover: XCUIElement) {
        popover.buttons["Next"].click()
        // Clicked at once, like a person double-stepping through the tour:
        // the tour keeps one height on every step so Done is where Next was.
        popover.buttons["Done"].click()
        XCTAssertTrue(popover.exists, "finishing the tour closed the popover")
        XCTAssertTrue(
            // The pill's label also carries its icon ("Selected" when active).
            popover.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
                .waitForExistence(timeout: 5),
            "the saved profile's pill is not on the root view. Popover contains:\n\(popover.debugDescription)"
        )
    }

    private func savedNote(in popover: XCUIElement) -> XCUIElement {
        staticText(in: popover, beginningWith: "Saved as")
    }

    /// SwiftUI text on macOS reaches accessibility as a static text whose
    /// *value* carries the string; its label is empty.
    private func staticText(in popover: XCUIElement, beginningWith prefix: String) -> XCUIElement {
        popover.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", prefix)).firstMatch
    }
}
