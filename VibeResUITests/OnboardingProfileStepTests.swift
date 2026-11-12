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
    private var profileDirectory: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        profileDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeResUITests-onboarding-\(UUID().uuidString)", isDirectory: true)
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-VibeRes.OnboardingShown", "NO"]
        app.launchEnvironment["VIBERES_PROFILE_DIR"] = profileDirectory.path
        app.launch()
    }

    override func tearDown() async throws {
        app?.terminate()
        app = nil
        if let profileDirectory { try? FileManager.default.removeItem(at: profileDirectory) }
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
    }

    // MARK: - Helpers

    private func openProfileStep() throws -> XCUIElement {
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
        return popover
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
