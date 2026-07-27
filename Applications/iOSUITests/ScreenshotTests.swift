import XCTest

/// Captures the deliverable screenshots (§29.15, §20 of the refinement pass).
///
/// Kept separate from the acceptance suite: these assert only enough to prove
/// the right screen was reached, then attach an image. Run explicitly with
/// `-only-testing:EnduranceUITests/ScreenshotTests`; attachments are extracted
/// from the .xcresult bundle by `Tools/capture-screenshots.sh`.
@MainActor
final class ScreenshotTests: XCTestCase {

    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Capture

    private func capture(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func el(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// `startDayOffset` backdates the plan so "today" lands on a chosen plan day.
    private func launch(startDayOffset: Int? = nil, extra: [String] = []) {
        var args = [
            A11y.LaunchArgument.freshInstall,
            A11y.LaunchArgument.suppressNotificationPrompt,
        ]
        if let startDayOffset {
            args += [A11y.LaunchArgument.startDayOffset, String(startDayOffset)]
        }
        app.launchArguments = args + extra
        app.launch()
    }

    private func completeOnboarding() {
        let cont = el(A11y.Onboarding.continueButton)
        XCTAssertTrue(cont.waitForExistence(timeout: 20), "Onboarding should show.")
        for _ in 0..<5 {
            XCTAssertTrue(waitUntilHittable(cont), "Continue not hittable.")
            cont.tap()
        }
        let ack = el(A11y.Onboarding.safetyAcknowledge)
        XCTAssertTrue(ack.waitForExistence(timeout: 10))
        ack.tap()
        cont.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 25))
    }

    private func selectTab(_ index: Int) {
        let button = app.tabBars.buttons.element(boundBy: index)
        XCTAssertTrue(button.waitForExistence(timeout: 15), "Tab \(index) missing.")
        XCTAssertTrue(waitUntilHittable(button), "Tab \(index) never became hittable.")
        button.tap()
    }

    // MARK: - 1. Onboarding

    func testCaptureOnboarding() {
        launch()
        XCTAssertTrue(el(A11y.Onboarding.continueButton).waitForExistence(timeout: 20))
        capture("01-onboarding")

        // Also capture the schedule step, where the derived date is shown.
        el(A11y.Onboarding.continueButton).tap()
        XCTAssertTrue(el(A11y.Onboarding.anchorPicker).waitForExistence(timeout: 10))
        capture("02-onboarding-schedule")
    }

    // MARK: - 2. Today with multiple sessions

    /// Plan day 29 (week 5, Tuesday) carries a bike session plus strength.
    func testCaptureTodayWithMultipleWorkouts() {
        launch(startDayOffset: 29)
        completeOnboarding()
        XCTAssertTrue(el(A11y.Today.date).waitForExistence(timeout: 15))
        XCTAssertTrue(el(A11y.Today.row(1)).waitForExistence(timeout: 10),
                      "Expected a second session on this day.")
        capture("03-today-multiple-workouts")
    }

    // MARK: - 3. Recovery day

    /// Plan day 28 (week 5, Monday) is mobility only — a recovery day.
    func testCaptureRecoveryDay() {
        launch(startDayOffset: 28)
        completeOnboarding()
        XCTAssertTrue(el(A11y.Today.status).waitForExistence(timeout: 15))
        capture("04-today-recovery-day")
    }

    // MARK: - 4. Workout detail

    func testCaptureWorkoutDetail() {
        launch(startDayOffset: 29)
        completeOnboarding()
        let row = el(A11y.Today.row(0))
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertTrue(el(A11y.Detail.scheduledDate).waitForExistence(timeout: 10))
        capture("05-workout-detail")
    }

    // MARK: - 5. Week plan

    func testCaptureWeekPlan() {
        launch(startDayOffset: 29)
        completeOnboarding()
        selectTab(1)
        XCTAssertTrue(el(A11y.Plan.week(1)).waitForExistence(timeout: 15))
        capture("06-plan-weeks")

        el(A11y.Plan.week(1)).tap()
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 10))
        capture("07-plan-week-detail")
    }

    // MARK: - 6. Progress

    func testCaptureProgress() {
        launch(startDayOffset: 29)
        completeOnboarding()
        selectTab(2)
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 15))
        capture("08-progress")
    }

    // MARK: - 7. Settings

    func testCaptureSettings() {
        launch(startDayOffset: 29)
        completeOnboarding()
        selectTab(3)
        XCTAssertTrue(el(A11y.Settings.planDates).waitForExistence(timeout: 15))
        capture("09-settings")
    }

    // MARK: - 8. Dark Mode

    func testCaptureDarkMode() {
        launch(startDayOffset: 29, extra: ["-UIUserInterfaceStyle", "Dark"])
        completeOnboarding()
        XCTAssertTrue(el(A11y.Today.date).waitForExistence(timeout: 15))
        capture("10-today-dark")

        selectTab(1)
        XCTAssertTrue(el(A11y.Plan.week(1)).waitForExistence(timeout: 15))
        capture("11-plan-dark")
    }

    // MARK: - 9. Largest Dynamic Type

    func testCaptureLargestDynamicType() {
        launch(startDayOffset: 29,
               extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        completeOnboarding()
        XCTAssertTrue(el(A11y.Today.date).waitForExistence(timeout: 15))
        capture("12-today-largest-dynamic-type")

        let row = el(A11y.Today.row(0))
        if row.waitForExistence(timeout: 10) {
            row.tap()
            _ = el(A11y.Detail.scheduledDate).waitForExistence(timeout: 10)
            capture("13-workout-detail-largest-dynamic-type")
        }
    }
}
