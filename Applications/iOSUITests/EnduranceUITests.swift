import XCTest

/// Deterministic end-to-end tests for the Release 1 acceptance criteria.
///
/// These replace the earlier smoke tests, which asserted only that the app
/// reached the foreground and passed whether onboarding *or* the Today tab was
/// showing — i.e. they could not fail for any product reason. Everything here
/// matches on accessibility identifiers from `A11y`, never on user-facing text,
/// so the suite survives localization.
final class EnduranceUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app = nil
    }


    // MARK: - Element lookup

    /// SwiftUI maps a given view onto different XCUIElement types depending on
    /// context (button vs cell vs staticText vs other), so every lookup goes
    /// through the whole descendant tree by identifier.
    private func el(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func exists(_ identifier: String, _ timeout: TimeInterval = 10) -> Bool {
        el(identifier).waitForExistence(timeout: timeout)
    }


    /// Tabs are the one place identifiers are unreliable: SwiftUI does not always
    /// forward `.accessibilityIdentifier` onto the UITabBar button. Fall back to
    /// position, which is fixed by `RootView` and independent of language.
    private func selectTab(_ identifier: String, index: Int) {
        let byIdentifier = el(identifier)
        if byIdentifier.waitForExistence(timeout: 3) {
            byIdentifier.tap()
            return
        }
        let button = app.tabBars.buttons.element(boundBy: index)
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Tab \(index) not found.")
        button.tap()
    }

    private enum TabIndex {
        static let today = 0, plan = 1, progress = 2, settings = 3
    }

    // MARK: - Launch helpers

    /// First launch of a test: wipe persisted state so we always start at
    /// onboarding, and suppress the system notification prompt (owned by
    /// SpringBoard, not dismissible reliably from XCUITest).
    private func launchFresh() {
        app.launchArguments = [
            A11y.LaunchArgument.freshInstall,
            A11y.LaunchArgument.suppressNotificationPrompt,
        ]
        app.launch()
    }

    /// Relaunch WITHOUT the fresh-install flag, so real persisted data loads.
    /// This is the whole point of the persistence assertions.
    private func relaunch() {
        app.terminate()
        app.launchArguments = [A11y.LaunchArgument.suppressNotificationPrompt]
        app.launch()
    }

    // MARK: - Onboarding

    /// Walk all six onboarding steps. Leaves the app on the Today tab.
    @discardableResult
    private func completeOnboarding(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let continueButton = el(A11y.Onboarding.continueButton)
        XCTAssertTrue(continueButton.waitForExistence(timeout: 15),
                      "Onboarding should be showing on a fresh install.", file: file, line: line)

        // Steps: purpose → schedule → structure → capability → notifications → safety.
        for step in 0..<5 {
            XCTAssertTrue(continueButton.waitForExistence(timeout: 5),
                          "Continue missing on step \(step)", file: file, line: line)
            continueButton.tap()
        }

        // Safety step gates Continue behind the acknowledgement toggle.
        let acknowledge = el(A11y.Onboarding.safetyAcknowledge)
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 5),
                      "Safety acknowledgement missing.", file: file, line: line)
        XCTAssertFalse(continueButton.isEnabled,
                       "Start training must stay disabled until safety is acknowledged.",
                       file: file, line: line)
        acknowledge.tap()
        XCTAssertTrue(continueButton.isEnabled, file: file, line: line)
        continueButton.tap()

        let arrived = app.tabBars.firstMatch.waitForExistence(timeout: 20)
        XCTAssertTrue(arrived, "Should land on the tab bar after onboarding.", file: file, line: line)
        return arrived
    }

    // MARK: - 1 & 2. Onboarding produces a real 36-week schedule

    func testOnboardingGeneratesFullThirtySixWeekSchedule() {
        launchFresh()
        completeOnboarding()

        // The Plan tab renders phases and weeks.
        selectTab(A11y.Tab.plan, index: TabIndex.plan)
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 10),
                      "Plan list should appear.")
        XCTAssertTrue(exists(A11y.Plan.week(1)), "Week 1 should be listed.")

        // Strongest available evidence that the *whole* plan was scheduled: the
        // export summary is produced by encoding and decoding the real store.
        selectTab(A11y.Tab.settings, index: TabIndex.settings)
        let summary = el(A11y.Settings.exportSummary)
        XCTAssertTrue(summary.waitForExistence(timeout: 15), "Export summary should be shown.")

        let sessions = Self.leadingInt(in: summary.label)
        XCTAssertEqual(sessions, 382,
                       "The bundled 36-week plan schedules 382 sessions; got \(summary.label).")
    }

    // MARK: - 3. Today shows the correct date and workout

    func testTodayShowsTodaysDateAndSessions() {
        launchFresh()
        completeOnboarding()

        let dateLabel = el(A11y.Today.date)
        XCTAssertTrue(dateLabel.waitForExistence(timeout: 10), "Today should show a date header.")

        // Onboarding anchors the plan to today, so the header must read today.
        let expected = Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
        XCTAssertEqual(dateLabel.label, expected,
                       "Today's header should be today's date.")

        // Day 1 of the plan has work, so a row must exist and carry a status line.
        XCTAssertTrue(exists(A11y.Today.row(0)),
                      "Today should list at least one session on day one of the plan.")
        XCTAssertTrue(el(A11y.Today.status).exists, "A calm status line should be present.")
    }

    // MARK: - 4, 5, 6. Completion survives relaunch

    func testCompletionPersistsAcrossRelaunch() {
        launchFresh()
        completeOnboarding()

        openFirstWorkout()

        let complete = el(A11y.Detail.complete)
        XCTAssertTrue(complete.waitForExistence(timeout: 10), "Detail should offer Complete.")
        complete.tap()

        let save = el(A11y.Completion.save)
        XCTAssertTrue(save.waitForExistence(timeout: 10), "Completion sheet should appear.")
        save.tap()

        let status = el(A11y.Detail.status)
        XCTAssertTrue(status.waitForExistence(timeout: 10),
                      "A status should be shown immediately after completing.")
        let before = status.label
        XCTAssertFalse(before.isEmpty)

        relaunch()

        openFirstWorkout()
        let after = el(A11y.Detail.status)
        XCTAssertTrue(after.waitForExistence(timeout: 15),
                      "Completion must survive a terminate + relaunch.")
        XCTAssertEqual(after.label, before, "The persisted status should match what was saved.")
    }

    // MARK: - 7, 8, 9. Rescheduling survives relaunch

    func testReschedulePersistsAcrossRelaunch() {
        launchFresh()
        completeOnboarding()

        let row = firstWorkoutRow()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.press(forDuration: 1.2) // context menu

        let reschedule = el(A11y.Today.rescheduleAction)
        XCTAssertTrue(reschedule.waitForExistence(timeout: 10), "Context menu should offer Reschedule.")
        reschedule.tap()

        XCTAssertTrue(el(A11y.Reschedule.confirm).waitForExistence(timeout: 10),
                      "Reschedule sheet should appear.")
        selectFutureDate(in: el(A11y.Reschedule.datePicker))
        el(A11y.Reschedule.confirm).tap()

        // Moving it off today removes it from Today's list.
        let movedAway = el(A11y.Today.empty).waitForExistence(timeout: 10)
            || !el(A11y.Today.row(0)).exists
            || el(A11y.Today.rowStatus(0)).exists
        XCTAssertTrue(movedAway, "Today should reflect the move immediately.")

        let todayStateBefore = todaySignature()
        relaunch()
        XCTAssertTrue(el(A11y.Today.date).waitForExistence(timeout: 15))
        XCTAssertEqual(todaySignature(), todayStateBefore,
                       "The new scheduled date must survive a terminate + relaunch.")
    }

    // MARK: - 10 & 11. Changing the anchor regenerates future workouts

    func testChangingStartDateRegeneratesFutureWorkouts() {
        launchFresh()
        completeOnboarding()

        XCTAssertTrue(el(A11y.Today.date).waitForExistence(timeout: 10))
        let sessionsBefore = app.buttons.matching(identifier: A11y.Today.row(0)).count
            + app.cells.matching(identifier: A11y.Today.row(0)).count

        selectTab(A11y.Tab.settings, index: TabIndex.settings)
        let planDates = el(A11y.Settings.planDates)
        XCTAssertTrue(planDates.waitForExistence(timeout: 10))
        planDates.tap()

        let picker = el(A11y.PlanDates.startDate)
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "Start-date picker should appear.")
        selectFutureDate(in: picker)

        let apply = el(A11y.PlanDates.apply)
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        apply.tap()

        // With the plan pushed into the future, today has nothing scheduled and
        // the Up Next section takes over — that is the regeneration, visible.
        selectTab(A11y.Tab.today, index: TabIndex.today)
        let emptyAppeared = el(A11y.Today.empty).waitForExistence(timeout: 15)
            || el(A11y.Today.empty).waitForExistence(timeout: 5)
        let upNextAppeared = el(A11y.Today.upNext).waitForExistence(timeout: 10)
            || el(A11y.Today.upNext).waitForExistence(timeout: 5)

        XCTAssertTrue(emptyAppeared || upNextAppeared,
                      "Moving the start date forward should clear today and surface Up Next. "
                      + "Sessions before the change: \(sessionsBefore).")
    }

    // MARK: - 12 & 13. Export round-trips through the UI

    func testExportIsWrittenAndParsesBack() {
        launchFresh()
        completeOnboarding()

        selectTab(A11y.Tab.settings, index: TabIndex.settings)

        // The share control must exist — that is the user-facing export path.
        XCTAssertTrue(el(A11y.Settings.export).waitForExistence(timeout: 15),
                      "Export control should be available.")

        // And the summary is derived by decoding the file just written, so its
        // presence proves the export parses back (§31).
        let summary = el(A11y.Settings.exportSummary)
        XCTAssertTrue(summary.waitForExistence(timeout: 10),
                      "Export summary is only rendered when the written file decodes.")
        XCTAssertEqual(Self.leadingInt(in: summary.label), 382,
                       "Round-tripped export should contain the full schedule; got \(summary.label).")
    }

    // MARK: - Accessibility smoke at the largest Dynamic Type size

    func testCriticalScreensSurviveLargestDynamicType() {
        app.launchArguments = [
            A11y.LaunchArgument.freshInstall,
            A11y.LaunchArgument.suppressNotificationPrompt,
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        completeOnboarding()

        // The date header and status must remain present (not clipped away) at
        // the largest accessibility text size.
        XCTAssertTrue(el(A11y.Today.date).waitForExistence(timeout: 15))
        XCTAssertTrue(el(A11y.Today.status).exists)

        selectTab(A11y.Tab.settings, index: TabIndex.settings)
        XCTAssertTrue(el(A11y.Settings.planDates).waitForExistence(timeout: 10),
                      "Settings rows should stay reachable at accessibility sizes.")
    }

    // MARK: - Helpers

    private func firstWorkoutRow() -> XCUIElement { el(A11y.Today.row(0)) }

    private func openFirstWorkout() {
        let row = firstWorkoutRow()
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Today should have a session to open.")
        row.tap()
        XCTAssertTrue(el(A11y.Detail.scheduledDate).waitForExistence(timeout: 10)
                      || el(A11y.Detail.complete).waitForExistence(timeout: 5),
                      "Workout detail should open.")
    }

    /// A cheap fingerprint of Today's visible state, used to prove persistence
    /// rather than merely that the screen rendered.
    private func todaySignature() -> String {
        let date = el(A11y.Today.date).exists ? el(A11y.Today.date).label : "-"
        let status = el(A11y.Today.status).exists ? el(A11y.Today.status).label : "-"
        return "\(date)|\(status)"
    }

    /// Move a compact `DatePicker` to a deterministic future date: open its
    /// calendar, go forward one month, and pick the 15th — a day that exists in
    /// every month and is always ahead of today.
    private func selectFutureDate(in picker: XCUIElement) {
        guard picker.waitForExistence(timeout: 10) else {
            XCTFail("Date picker not found.")
            return
        }
        picker.tap()

        // Wait for the month control before scoping anything: the calendar is
        // presented as a second DatePicker element, and counting pickers before
        // it exists silently scopes back to the collapsed one.
        let nextMonth = app.buttons["DatePicker.NextMonth"]
        XCTAssertTrue(nextMonth.waitForExistence(timeout: 8), "Calendar did not open.")
        nextMonth.tap()

        // Now the calendar is definitely present, so scope day lookup to it and
        // a stray "15" elsewhere on screen can never be tapped by mistake. Each
        // day is a button labelled "Wednesday, July 15" wrapping a static text
        // of just the number; the 15th exists in every month and is always
        // ahead of today.
        let calendar = app.datePickers.element(boundBy: max(app.datePickers.count - 1, 0))
        let scopedDay = calendar.staticTexts["15"]
        let day = scopedDay.waitForExistence(timeout: 5) ? scopedDay : app.staticTexts["15"]
        XCTAssertTrue(day.waitForExistence(timeout: 5),
                      "Could not find a day cell to select in the calendar.")
        day.tap()

        // Collapse the calendar so the confirm button becomes hittable again.
        // While the popover is up the picker reports as not hittable, so tap its
        // coordinate directly — that lands outside the popover and dismisses it.
        if app.buttons["DatePicker.NextMonth"].exists {
            picker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertFalse(app.buttons["DatePicker.NextMonth"].waitForExistence(timeout: 3),
                       "Calendar should have collapsed after choosing a date.")
    }

    /// First integer in a label such as "382 sessions · 1 logged".
    private static func leadingInt(in label: String) -> Int? {
        let digits = label.prefix { $0.isNumber || $0 == "," || $0 == "." }
            .filter(\.isNumber)
        return Int(digits)
    }
}
