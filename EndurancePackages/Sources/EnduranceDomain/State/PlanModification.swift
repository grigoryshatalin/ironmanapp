import Foundation

/// The kind of change an athlete made to a scheduled session. Recorded as an
/// audit trail (§9 "Modification history", §15 `PlanModification`) so the
/// original plan and the adapted plan stay separately auditable.
public enum ModificationType: String, Codable, Sendable, Hashable, CaseIterable {
    case reschedule
    case shorten
    case replaceWithRecovery
    case skip
    case restore        // undo a prior status change
    case note
    case adaptation     // applied from an adaptive recommendation (§28.13)

    public var localizationKey: String { "modification.\(rawValue)" }
}

/// One immutable audit entry describing a change to a `ScheduledWorkout`.
public struct PlanModification: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var type: ModificationType
    public var createdAt: Date
    public var oldDate: Date?
    public var newDate: Date?
    public var oldDurationMinutes: Int?
    public var newDurationMinutes: Int?
    /// Free-text or an explanation string from an adaptation recommendation.
    public var reason: String?

    public init(
        id: UUID = UUID(),
        type: ModificationType,
        createdAt: Date,
        oldDate: Date? = nil,
        newDate: Date? = nil,
        oldDurationMinutes: Int? = nil,
        newDurationMinutes: Int? = nil,
        reason: String? = nil
    ) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.oldDate = oldDate
        self.newDate = newDate
        self.oldDurationMinutes = oldDurationMinutes
        self.newDurationMinutes = newDurationMinutes
        self.reason = reason
    }
}
