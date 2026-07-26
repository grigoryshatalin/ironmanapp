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
    ]
)
