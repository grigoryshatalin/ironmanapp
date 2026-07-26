import Foundation
import SwiftData

/// Versioned schemas and the migration path between them (§N).
///
/// Release 1 shipped an *unversioned* `Schema([...])`. Introducing versioning
/// now is safe because SwiftData identifies a store by its entities, not by a
/// recorded version number: a Release 1 store contains exactly the two V1
/// entities, so it is recognised as V1 and migrated forward. That claim is not
/// taken on faith — `MigrationTests` builds a real V1 store on disk, reopens it
/// under the V2 container, and asserts the data survived.
///
/// The migration is **additive only**: no existing entity gains, loses, renames
/// or retypes a property, so it qualifies as a lightweight stage and no data is
/// rewritten. This is the reason Release 2 required no destructive change.

enum EnduranceSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [SDScheduledWorkout.self, SDAppSettings.self]
    }
}

enum EnduranceSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            // Unchanged from V1 — same shape, same identifiers, same payloads.
            SDScheduledWorkout.self,
            SDAppSettings.self,
            // Added in Release 2.
            SDExternalWorkoutRecord.self,
            SDWorkoutExecution.self,
            SDWorkoutMatchDecision.self,
            SDHealthImportCursor.self,
            SDHealthAuthorizationState.self,
            SDWorkoutKitScheduleRecord.self,
            SDWatchSyncRecord.self,
            SDActiveWorkoutRecovery.self,
            SDIntegrationErrorRecord.self,
        ]
    }
}

enum EnduranceMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [EnduranceSchemaV1.self, EnduranceSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    /// Purely additive, so lightweight. If a future release changes an existing
    /// property, this must become a `custom` stage with explicit fixtures —
    /// §28.22 forbids solving migration by asking users to reinstall.
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: EnduranceSchemaV1.self,
        toVersion: EnduranceSchemaV2.self)
}

/// The schema the app runs against today.
enum EnduranceSchema {
    static var current: Schema { Schema(versionedSchema: EnduranceSchemaV2.self) }
    static var migrationPlan: any SchemaMigrationPlan.Type { EnduranceMigrationPlan.self }
}
