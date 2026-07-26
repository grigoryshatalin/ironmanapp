import Foundation
import EnduranceDomain

// Content pipeline: generate the 36‑week plan, validate it, and write JSON.
// Usage: swift run enduranceplan [output.json]
// Fails (non‑zero) if the generated plan does not validate, so CI never ships an
// invalid bundled plan.

let defaultOut = "Sources/EnduranceTrainingPlans/Resources/Endurance36Week.json"
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultOut

let plan = PlanGenerator.make36Week()
let result = PlanValidator().validate(plan)

if !result.warnings.isEmpty {
    FileHandle.standardError.write(Data(("warnings:\n" + result.warnings.map { "  - \($0.description)" }.joined(separator: "\n") + "\n").utf8))
}

guard result.isValid else {
    FileHandle.standardError.write(Data(("ERROR: generated plan is invalid:\n" + result.errors.map { "  - \($0.description)" }.joined(separator: "\n") + "\n").utf8))
    exit(1)
}

do {
    let data = try PlanCodec.encode(plan)
    let url = URL(fileURLWithPath: outPath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
    let days = plan.allDays.count
    let workouts = plan.weeks.flatMap { $0.days }.reduce(0) { $0 + $1.workouts.count }
    print("Wrote \(data.count) bytes → \(outPath)")
    print("Plan: \(plan.weeks.count) weeks · \(days) days · \(workouts) workouts · valid=\(result.isValid) · warnings=\(result.warnings.count)")
} catch {
    FileHandle.standardError.write(Data("ERROR writing plan: \(error)\n".utf8))
    exit(1)
}
