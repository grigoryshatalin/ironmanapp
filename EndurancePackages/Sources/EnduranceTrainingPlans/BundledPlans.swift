import Foundation
import EnduranceDomain

/// Access to the plan content the app bundles. The 36‑week plan is generated
/// deterministically by `PlanGenerator` (in `EnduranceDomain`) and encoded to
/// `Resources/Endurance36Week.json` by the `enduranceplan` tool at build time.
/// The app loads and validates the JSON on first launch (brief §18); it never
/// runs the generator at runtime.
public enum BundledPlans {

    public static let bundled36WeekResource = "Endurance36Week"

    public enum LoadError: Error, CustomStringConvertible {
        case missingResource(String)
        case invalid([PlanValidator.Issue])
        public var description: String {
            switch self {
            case .missingResource(let n): return "Bundled plan resource '\(n).json' was not found."
            case .invalid(let issues): return "Bundled plan failed validation: " + issues.map(\.description).joined(separator: "; ")
            }
        }
    }

    /// Decode and validate the bundled 36‑week plan.
    public static func load36Week() throws -> TrainingPlanDefinition {
        guard let url = Bundle.module.url(forResource: bundled36WeekResource, withExtension: "json") else {
            throw LoadError.missingResource(bundled36WeekResource)
        }
        let data = try Data(contentsOf: url)
        let plan = try PlanCodec.decode(data)
        let result = PlanValidator().validate(plan)
        guard result.isValid else { throw LoadError.invalid(result.errors) }
        return plan
    }

    /// The generator output — the source of truth the JSON is built from. Useful
    /// for tests and previews without touching the bundle.
    public static func generated36Week() -> TrainingPlanDefinition {
        PlanGenerator.make36Week()
    }
}
