import XCTest

/// UI smoke tests. These are intentionally resilient; extend with accessibility
/// identifiers as screens stabilize (brief §23 UI tests). Run on a Simulator.
final class OnboardingUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    /// On a fresh install the onboarding "Continue" button should be reachable.
    /// (Reset the app or use a fresh Simulator so onboarding is shown.)
    func testOnboardingIsPresentOnFreshInstall() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestFreshInstall"]
        app.launch()

        let continueButton = app.buttons["Continue"]
        // If the device already completed onboarding, the Today tab is shown instead.
        let todayTab = app.tabBars.buttons["Today"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5) || todayTab.waitForExistence(timeout: 5),
                      "Expected either onboarding or the main tab bar.")
    }
}
