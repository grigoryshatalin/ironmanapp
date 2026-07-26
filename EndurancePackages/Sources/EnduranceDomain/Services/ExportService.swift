import Foundation

/// A portable, human-readable export of the athlete's mutable state — schedule,
/// completions, modifications, settings. Separate from the immutable plan so a
/// plan update never erases history (§12 Data management, §22, §28.12).
public struct TrainingHistoryExport: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var exportedAt: Date
    public var planID: UUID?
    public var scheduleConfiguration: ScheduleConfiguration
    public var notificationPreferences: NotificationPreferences
    public var units: MeasurementSystem
    public var scheduledWorkouts: [ScheduledWorkout]

    public init(
        schemaVersion: Int = 1,
        exportedAt: Date,
        planID: UUID?,
        scheduleConfiguration: ScheduleConfiguration,
        notificationPreferences: NotificationPreferences,
        units: MeasurementSystem,
        scheduledWorkouts: [ScheduledWorkout]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.planID = planID
        self.scheduleConfiguration = scheduleConfiguration
        self.notificationPreferences = notificationPreferences
        self.units = units
        self.scheduledWorkouts = scheduledWorkouts
    }
}

/// Encodes/decodes exports (JSON) and produces a CSV of completion history for
/// spreadsheet use (§12 "optionally CSV for history").
public enum ExportService {

    public static func encode(_ export: TrainingHistoryExport) throws -> Data {
        try PlanCodec.makeEncoder().encode(export)
    }

    public static func decode(_ data: Data) throws -> TrainingHistoryExport {
        try PlanCodec.makeDecoder().decode(TrainingHistoryExport.self, from: data)
    }

    /// CSV of completed sessions. Values are quoted/escaped to stay valid when
    /// notes contain commas or quotes.
    public static func completionCSV(_ workouts: [ScheduledWorkout]) -> String {
        let header = ["week", "date", "sport", "title", "status",
                      "planned_min", "actual_min", "distance_m", "rpe", "source"]
        var rows = [header.joined(separator: ",")]
        let iso = ISO8601DateFormatter()
        for w in workouts.sorted(by: { $0.dayIndex < $1.dayIndex || ($0.dayIndex == $1.dayIndex && $0.order < $1.order) })
        where w.status.countsAsDone || w.status == .skipped {
            let c = w.completion
            let fields: [String] = [
                "\(w.weekNumber)",
                iso.string(from: w.scheduledDate),
                w.sport.rawValue,
                w.title,
                w.status.rawValue,
                "\(w.effectivePlannedMinutes)",
                c?.actualDurationMinutes.map(String.init) ?? "",
                c?.actualDistanceMeters.map { String(format: "%.0f", $0) } ?? "",
                c?.perceivedExertion.map(String.init) ?? "",
                c?.source.rawValue ?? ""
            ]
            rows.append(fields.map(csvEscape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private static func csvEscape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
