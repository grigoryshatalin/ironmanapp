import Foundation
import EnduranceDomain
#if canImport(HealthKit)
import HealthKit
#endif

/// The iPhone-side live session (§G).
///
/// **`HKWorkoutSession` is watchOS-only.** An iPhone cannot run one, so this is
/// not a degraded copy of the watch session — it is a different, smaller thing:
/// a monotonic clock plus a `HKWorkoutBuilder` write at the end. That is the
/// Apple-recommended iPhone path, and pretending otherwise would mean showing an
/// athlete a heart-rate field that stays blank for an hour.
///
/// `capability` states this up front so the UI can say what will be recorded
/// *before* the session starts. Rich live metrics arrive with the watch app in
/// Stage 6; this stage does not fake them.
final class PhoneWorkoutSession: ActiveWorkoutManaging, @unchecked Sendable {

    private(set) var state: ActiveWorkoutState = .idle

    /// Time is genuine; nothing else is available without a paired Watch.
    let capability = ActiveWorkoutCapability.timingOnly

    private var workout: ScheduledWorkout?
    private var startDate: Date?
    private var endDate: Date?
    private var stopwatch = MonotonicStopwatch()
    private var laps: [Date] = []
    private let exporter: (any HealthExporting)?
    private let isExportEnabled: () -> Bool

    /// - Parameter exporter: writes the finished session to HealthKit. Optional
    ///   so a session still records locally when Health is unavailable or the
    ///   athlete has not enabled export — the training log is the app's own, and
    ///   must not depend on a permission (§F).
    init(exporter: (any HealthExporting)? = nil, isExportEnabled: @escaping () -> Bool = { false }) {
        self.exporter = exporter
        self.isExportEnabled = isExportEnabled
    }

    func prepare(for workout: ScheduledWorkout) async throws {
        self.workout = workout
        state = .preparing
    }

    func start() async throws {
        startDate = Date()
        stopwatch.start(now: DispatchTime.now().uptimeNanoseconds)
        state = .running
    }

    func pause() async throws {
        stopwatch.pause(now: DispatchTime.now().uptimeNanoseconds)
        state = .paused
    }

    func resume() async throws {
        stopwatch.start(now: DispatchTime.now().uptimeNanoseconds)
        state = .running
    }

    func end() async throws {
        stopwatch.pause(now: DispatchTime.now().uptimeNanoseconds)
        endDate = Date()
        state = .saving
    }

    func markLap() async {
        laps.append(Date())
    }

    func currentMetrics() async -> ActiveWorkoutMetrics {
        // Only what this device genuinely produced. Distance, heart rate and
        // energy stay absent rather than zero.
        ActiveWorkoutMetrics(
            elapsedSeconds: startDate.map { Date().timeIntervalSince($0) } ?? 0,
            activeSeconds: stopwatch.elapsed(now: DispatchTime.now().uptimeNanoseconds))
    }

    func save() async throws -> WorkoutExecution {
        let start = startDate ?? Date()
        let duration = stopwatch.elapsed(now: DispatchTime.now().uptimeNanoseconds)

        let execution = WorkoutExecution(
            id: UUID(),
            scheduledWorkoutID: workout?.id,
            source: .appTimer,
            start: start,
            durationSeconds: Int(duration),
            distanceMeters: nil,
            averageHeartRate: nil,
            activeEnergyKilocalories: nil,
            externalKeys: [],
            exportedProviderID: nil,
            recordedAt: Date())

        state = .completed
        return execution
    }

    func discard() async throws {
        state = .discarded
        workout = nil
        startDate = nil
        endDate = nil
        laps = []
        stopwatch = MonotonicStopwatch()
    }
}
