import Foundation

/// Lifecycle status of a *scheduled* workout (mutable user state), distinct from
/// the immutable plan template it derives from.
public enum WorkoutStatus: String, Codable, CaseIterable, Sendable, Hashable {
    case planned
    case inProgress
    case completed
    case partiallyCompleted
    case skipped
    case rescheduled
    case replaced

    public var localizationKey: String { "status.\(rawValue)" }

    public var englishName: String {
        switch self {
        case .planned: return "Planned"
        case .inProgress: return "In progress"
        case .completed: return "Completed"
        case .partiallyCompleted: return "Partially completed"
        case .skipped: return "Skipped"
        case .rescheduled: return "Rescheduled"
        case .replaced: return "Replaced"
        }
    }

    /// SF Symbol conveying status *in addition to* text — never color alone.
    public var preferredSymbolName: String {
        switch self {
        case .planned: return "circle"
        case .inProgress: return "record.circle"
        case .completed: return "checkmark.circle.fill"
        case .partiallyCompleted: return "circle.bottomhalf.filled"
        case .skipped: return "minus.circle"
        case .rescheduled: return "arrow.right.circle"
        case .replaced: return "arrow.triangle.2.circlepath.circle"
        }
    }

    public var fallbackSymbolName: String {
        switch self {
        case .planned: return "circle"
        case .inProgress: return "smallcircle.filled.circle"
        case .completed: return "checkmark.circle.fill"
        case .partiallyCompleted: return "circle.lefthalf.filled"
        case .skipped: return "minus.circle"
        case .rescheduled: return "arrow.right.circle"
        case .replaced: return "arrow.2.circlepath.circle"
        }
    }

    /// Counts toward "done" in weekly summaries. Partially-completed counts as
    /// done (the athlete trained) but is tracked separately for honesty.
    public var countsAsDone: Bool {
        switch self {
        case .completed, .partiallyCompleted: return true
        case .planned, .inProgress, .skipped, .rescheduled, .replaced: return false
        }
    }

    /// Whether pending workout reminders should be cancelled on entering this
    /// state (completing/skipping/replacing a session cancels its reminders;
    /// rescheduling regenerates them elsewhere).
    public var shouldCancelReminders: Bool {
        switch self {
        case .completed, .partiallyCompleted, .skipped, .replaced: return true
        case .planned, .inProgress, .rescheduled: return false
        }
    }
}
