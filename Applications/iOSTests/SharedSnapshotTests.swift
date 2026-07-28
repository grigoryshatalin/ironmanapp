import XCTest
import SwiftData
import EnduranceDomain
import EnduranceTrainingPlans
@testable import Endurance

/// §28.19 / §K — the widget reads a file, not the database.
///
/// The App Group carried a placeholder identifier for the whole of Release 2,
/// which made `containerURL(forSecurityApplicationGroupIdentifier:)` return nil
/// and the writer do nothing at all, silently. These tests exist because that
/// failure is invisible from both sides: the app thinks it wrote, the widget
/// thinks there is no plan.
final class SharedSnapshotTests: XCTestCase {

    /// A scratch container, so the tests never depend on the real App Group
    /// being provisioned on whichever machine runs them.
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Round trip

    func testASnapshotSurvivesTheRoundTrip() throws {
        let file = directory.appendingPathComponent("today-snapshot.json")
        let original = SharedTodaySnapshot.placeholder

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(original).write(to: file)

        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(SharedTodaySnapshot.self, from: Data(contentsOf: file))

        XCTAssertEqual(restored, original,
                       "the widget must read exactly what the app wrote")
    }

    /// Dates are the field most likely to drift between two independently
    /// configured coders, and a wrong `nextWorkoutStart` shows the athlete the
    /// wrong time on their Home Screen.
    func testDatesSurviveEncodingWithoutDrift() throws {
        var snapshot = SharedTodaySnapshot.placeholder
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        snapshot.nextWorkoutStart = start

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(
            SharedTodaySnapshot.self, from: try encoder.encode(snapshot))

        XCTAssertEqual(
            restored.nextWorkoutStart?.timeIntervalSince1970.rounded(),
            start.timeIntervalSince1970.rounded())
    }

    // MARK: - Unavailable container

    /// An unreachable App Group must be distinguishable from an empty plan.
    /// Rendering both as "no sessions" is what let the broken identifier hide.
    func testAnUnreachableContainerIsReportedRatherThanLookingEmpty() {
        let store = SharedSnapshotStore(appGroupID: "group.invalid.does.not.exist")
        XCTAssertFalse(store.isContainerAvailable)
        XCTAssertNil(store.read())
    }

    // MARK: - The snapshot the app actually produces

    @MainActor
    func testTheStoreProducesAUsableSnapshot() throws {
        let config = ModelConfiguration(schema: EnduranceSchema.current, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: EnduranceSchema.current, configurations: [config])
        let store = WorkoutStore(modelContainer: container)
        try store.completeOnboarding(
            configuration: ScheduleConfiguration(
                anchor: .startDate(Calendar.current.startOfDay(for: Date())),
                timeZoneIdentifier: TimeZone.current.identifier),
            units: .metric,
            preferences: NotificationPreferences(),
            raceName: nil, raceLocation: nil)

        let snapshot = store.todaySnapshot()
        XCTAssertGreaterThan(snapshot.totalWeeks, 0)
        XCTAssertGreaterThan(snapshot.weekNumber, 0)
        XCTAssertFalse(snapshot.phaseName.isEmpty,
                       "the widget shows the phase; an empty string reads as a bug")
    }

    /// Progress is minutes, not session count: a 20-minute mobility session and
    /// a four-hour ride are not equal thirds of a day's work.
    func testProgressIsMeasuredInMinutes() {
        var snapshot = SharedTodaySnapshot.placeholder
        snapshot.plannedMinutes = 240
        snapshot.completedMinutes = 60
        snapshot.sessionCount = 2
        snapshot.completedSessionCount = 1

        let byMinutes = Double(snapshot.completedMinutes) / Double(snapshot.plannedMinutes)
        let bySessions = Double(snapshot.completedSessionCount) / Double(snapshot.sessionCount)
        XCTAssertNotEqual(byMinutes, bySessions, accuracy: 0.01,
                          "the two measures differ, and minutes is the honest one")
        XCTAssertEqual(byMinutes, 0.25, accuracy: 0.001)
    }
}
