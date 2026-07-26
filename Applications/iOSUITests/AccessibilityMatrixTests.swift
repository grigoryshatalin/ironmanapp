import XCTest

/// Automated coverage of the accessibility / appearance matrix (§8 of the
/// refinement pass, `QA_CHECKLIST.md`).
///
/// Each case launches the app with the corresponding system setting forced on
/// and asserts that the critical Today content is still present and reachable —
/// i.e. that nothing is clipped away, hidden, or made unhittable. These are
/// smoke-level guarantees; they do not replace looking at the screen, and the
/// manual column of `QA_CHECKLIST.md` still applies.
@MainActor
final class AccessibilityMatrixTests: XCTestCase {

    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
    }

    private func el(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func launch(_ extra: [String]) {
        app.launchArguments = [
            A11y.LaunchArgument.freshInstall,
            A11y.LaunchArgument.suppressNotificationPrompt,
            A11y.LaunchArgument.startDayOffset, "29",
        ] + extra
        app.launch()
    }

    private func completeOnboarding(file: StaticString = #filePath, line: UInt = #line) {
        let cont = el(A11y.Onboarding.continueButton)
        XCTAssertTrue(cont.waitForExistence(timeout: 20), "Onboarding should show.", file: file, line: line)
        for _ in 0..<5 {
            XCTAssertTrue(waitUntilHittable(cont), "Continue not hittable.")
            cont.tap()
        }
        let ack = el(A11y.Onboarding.safetyAcknowledge)
        XCTAssertTrue(ack.waitForExistence(timeout: 10), file: file, line: line)
        ack.tap()
        cont.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 25),
                      "Should reach the tab bar.", file: file, line: line)
    }

    /// The invariant every configuration must hold: the athlete can still see
    /// what day it is, what the day's status is, and open the first session.
    private func assertTodayRemainsUsable(_ configuration: String,
                                          file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(el(A11y.Today.date).waitForExistence(timeout: 15),
                      "\(configuration): date header missing.", file: file, line: line)
        XCTAssertTrue(el(A11y.Today.status).exists,
                      "\(configuration): status line missing.", file: file, line: line)

        let row = el(A11y.Today.row(0))
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "\(configuration): first session row missing.", file: file, line: line)
        XCTAssertTrue(row.isHittable,
                      "\(configuration): first session row is not tappable.", file: file, line: line)

        // And the session must actually open.
        row.tap()
        XCTAssertTrue(el(A11y.Detail.scheduledDate).waitForExistence(timeout: 10),
                      "\(configuration): workout detail did not open.", file: file, line: line)
    }

    // MARK: - Appearance

    func testLightMode() {
        launch(["-UIUserInterfaceStyle", "Light"])
        completeOnboarding()
        assertTodayRemainsUsable("Light Mode")
    }

    func testDarkMode() {
        launch(["-UIUserInterfaceStyle", "Dark"])
        completeOnboarding()
        assertTodayRemainsUsable("Dark Mode")
    }

    // MARK: - Accessibility settings

    func testReduceMotion() {
        launch(["-UIAccessibilityReduceMotionEnabled", "true"])
        completeOnboarding()
        assertTodayRemainsUsable("Reduce Motion")
    }

    func testIncreasedContrast() {
        launch(["-UIAccessibilityDarkerSystemColorsEnabled", "true"])
        completeOnboarding()
        assertTodayRemainsUsable("Increased Contrast")
    }

    func testDifferentiateWithoutColor() {
        launch(["-UIAccessibilityShouldDifferentiateWithoutColor", "true"])
        completeOnboarding()
        assertTodayRemainsUsable("Differentiate Without Color")
    }

    func testBoldText() {
        launch(["-UIAccessibilityBoldTextEnabled", "true"])
        completeOnboarding()
        assertTodayRemainsUsable("Bold Text")
    }

    // MARK: - Dynamic Type extremes

    func testSmallestDynamicType() {
        launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXS"])
        completeOnboarding()
        assertTodayRemainsUsable("Smallest Dynamic Type")
    }

    func testLargestDynamicType() {
        launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        completeOnboarding()
        assertTodayRemainsUsable("Largest Dynamic Type")
    }

    // MARK: - VoiceOver labelling

    /// VoiceOver reads `accessibilityLabel`, not the identifier. This asserts the
    /// row exposes a meaningful, localized, multi-part label rather than a bare
    /// title or an automation string leaking through.
    func testWorkoutRowsExposeMeaningfulVoiceOverLabels() {
        launch([])
        completeOnboarding()

        let row = el(A11y.Today.row(0))
        XCTAssertTrue(row.waitForExistence(timeout: 15))

        let label = row.label
        XCTAssertFalse(label.isEmpty, "Row must carry a VoiceOver label.")
        XCTAssertFalse(label.contains("today.row"), "Automation identifier must not leak into the label.")
        XCTAssertTrue(label.contains(","),
                      "Label should read as sport, title, time and metrics — got: \(label)")
        // Duration is safety-relevant and must be spoken.
        XCTAssertTrue(label.contains("m") || label.contains("h"),
                      "Label should include the session duration — got: \(label)")
    }
}
