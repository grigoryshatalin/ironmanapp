// swift-tools-version: 6.0
//
// EndurancePackages — the shared, platform-agnostic core of the Endurance app.
//
// Design intent (see /DECISIONS.md and /EXPANSION_ARCHITECTURE.md):
//   * `EnduranceDomain` is Foundation-only. It contains NO SwiftUI, UIKit,
//     HealthKit, or WidgetKit. This is what lets the iOS app, the watchOS app,
//     the widgets, App Intents, and the tests all share one source of truth —
//     and it is why this package compiles and its tests run on any Swift
//     toolchain, not just inside Xcode.
//   * `EnduranceTrainingPlans` bundles the generated, validated plan JSON.
//   * `enduranceplan` is a build-time tool that (re)generates that JSON.
//   * The SwiftUI app, watch app, and extensions live in /Applications and are
//     assembled by XcodeGen (project.yml). They depend ON this package; nothing
//     in this package depends on them.
//
import PackageDescription

let package = Package(
    name: "EndurancePackages",
    platforms: [
        .iOS(.v18),
        .watchOS(.v10),
        .macOS(.v14), // Host platform for `swift test`. Not a shipping target.
    ],
    products: [
        .library(name: "EnduranceDomain", targets: ["EnduranceDomain"]),
        .library(name: "EnduranceTrainingPlans", targets: ["EnduranceTrainingPlans"]),
        .library(name: "EnduranceHealth", targets: ["EnduranceHealth"]),
        .library(name: "EnduranceWorkoutKit", targets: ["EnduranceWorkoutKit"]),
        .executable(name: "enduranceplan", targets: ["enduranceplan"]),
    ],
    targets: [
        .target(
            name: "EnduranceDomain",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "EnduranceTrainingPlans",
            dependencies: ["EnduranceDomain"],
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The HealthKit adapter (§B). HealthKit itself is reachable only on iOS
        // and watchOS, so every file that imports it is guarded by
        // `#if canImport(HealthKit)`. The *mapping* and *eligibility* logic is
        // deliberately kept HealthKit-free so it compiles — and is tested — on
        // the macOS host under `swift test`, with no device or entitlement.
        .target(
            name: "EnduranceHealth",
            dependencies: ["EnduranceDomain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // WorkoutKit is isolated from the Foundation-only domain just like
        // HealthKit. The adapter accepts the domain's pure representation and
        // is compiled only where the framework is present.
        .target(
            name: "EnduranceWorkoutKit",
            dependencies: ["EnduranceDomain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "enduranceplan",
            dependencies: ["EnduranceDomain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "EnduranceDomainTests",
            dependencies: ["EnduranceDomain", "EnduranceTrainingPlans"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "EnduranceHealthTests",
            dependencies: ["EnduranceHealth", "EnduranceDomain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
