import Foundation
import SwiftData
import EnduranceDomain

/// SwiftData record for a scheduled workout. Query fields (date/week/status) are
/// stored as columns for efficient fetching; the full domain `ScheduledWorkout`
/// is kept as an encoded payload so the domain value type remains the single
/// source of truth (no field duplication drift). See DECISIONS.md §3.
@Model
final class SDScheduledWorkout {
    @Attribute(.unique) var id: UUID
    var scheduledDate: Date
    var weekNumber: Int
    var dayIndex: Int
    var order: Int
    var statusRaw: String
    var payload: Data

    init(domain: ScheduledWorkout) throws {
        self.id = domain.id
        self.scheduledDate = domain.scheduledDate
        self.weekNumber = domain.weekNumber
        self.dayIndex = domain.dayIndex
        self.order = domain.order
        self.statusRaw = domain.status.rawValue
        self.payload = try Self.encoder.encode(domain)
    }

    func toDomain() throws -> ScheduledWorkout {
        try Self.decoder.decode(ScheduledWorkout.self, from: payload)
    }

    func update(_ domain: ScheduledWorkout) throws {
        scheduledDate = domain.scheduledDate
        weekNumber = domain.weekNumber
        dayIndex = domain.dayIndex
        order = domain.order
        statusRaw = domain.status.rawValue
        payload = try Self.encoder.encode(domain)
    }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}

/// Single-row settings record (the `singletonKey` keeps it unique).
@Model
final class SDAppSettings {
    @Attribute(.unique) var singletonKey: String
    var onboarded: Bool
    var planID: UUID?
    var unitsRaw: String
    var configData: Data?
    var prefsData: Data?
    var raceName: String?
    var raceLocation: String?

    init() {
        self.singletonKey = "settings"
        self.onboarded = false
        self.planID = nil
        self.unitsRaw = MeasurementSystem.metric.rawValue
        self.configData = nil
        self.prefsData = nil
    }

    var units: MeasurementSystem {
        get { MeasurementSystem(rawValue: unitsRaw) ?? .metric }
        set { unitsRaw = newValue.rawValue }
    }

    var configuration: ScheduleConfiguration? {
        get { configData.flatMap { try? SDScheduledWorkout.decoder.decode(ScheduleConfiguration.self, from: $0) } }
        set { configData = newValue.flatMap { try? SDScheduledWorkout.encoder.encode($0) } }
    }

    var preferences: NotificationPreferences {
        get { prefsData.flatMap { try? SDScheduledWorkout.decoder.decode(NotificationPreferences.self, from: $0) } ?? NotificationPreferences() }
        set { prefsData = try? SDScheduledWorkout.encoder.encode(newValue) }
    }
}
