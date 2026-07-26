import Foundation

/// Namespace + build metadata for the Endurance domain layer.
///
/// The product name is intentionally isolated here (and in `project.yml`) so the
/// app can be renamed later without touching feature code. UI code should read
/// the display name from configuration, never hard-code the string "Endurance".
public enum EnduranceDomain {
    /// Human-facing product name. Single source of truth; overridable by the app
    /// layer if the bundle display name diverges.
    public static let productName = "Endurance"

    /// Schema version this build of the domain layer understands. Bundled plan
    /// files declare their own `schemaVersion`; `PlanValidator` reconciles them.
    public static let currentPlanSchemaVersion = 1
}
