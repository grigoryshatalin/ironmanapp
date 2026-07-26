import Foundation

/// Where a completion record originated. Distinguishes manually logged sessions
/// from device-recorded ones (§28.3 "clearly distinguish manually logged
/// workouts from device-recorded workouts").
public enum CompletionSource: String, Codable, Sendable, Hashable, CaseIterable {
    case manual         // athlete tapped "complete" and typed values
    case appTimer       // recorded by an in-app timer
    case healthKit      // imported from HealthKit
    case appleWatch     // recorded by the watch companion
    case external       // imported from Garmin/Strava/etc.

    public var localizationKey: String { "completionsource.\(rawValue)" }
}

/// Actuals recorded when a session is completed. Every metric is optional — the
/// app is fully usable logging nothing but "done", and richer data is layered on
/// when sensors or Health access are present.
public struct WorkoutCompletion: Codable, Sendable, Hashable {
    public var completedAt: Date
    public var actualDurationMinutes: Int?
    public var actualDistanceMeters: Double?
    public var averageHeartRate: Double?
    public var averagePower: Double?
    /// Perceived exertion on the 1–10 scale (the sensor-free fallback metric).
    public var perceivedExertion: Int?
    /// Subjective fatigue 1–5.
    public var fatigue: Int?
    /// Subjective soreness 1–5.
    public var soreness: Int?
    public var notes: String?
    public var source: CompletionSource

    public init(
        completedAt: Date,
        actualDurationMinutes: Int? = nil,
        actualDistanceMeters: Double? = nil,
        averageHeartRate: Double? = nil,
        averagePower: Double? = nil,
        perceivedExertion: Int? = nil,
        fatigue: Int? = nil,
        soreness: Int? = nil,
        notes: String? = nil,
        source: CompletionSource = .manual
    ) {
        self.completedAt = completedAt
        self.actualDurationMinutes = actualDurationMinutes
        self.actualDistanceMeters = actualDistanceMeters
        self.averageHeartRate = averageHeartRate
        self.averagePower = averagePower
        self.perceivedExertion = perceivedExertion
        self.fatigue = fatigue
        self.soreness = soreness
        self.notes = notes
        self.source = source
    }
}
