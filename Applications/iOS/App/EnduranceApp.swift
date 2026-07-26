import SwiftUI
import SwiftData

/// App entry point. Builds the SwiftData container and the app environment, and
/// installs the notification delegate before the UI appears so cold-start
/// notification taps are delivered.
@main
struct EnduranceApp: App {
    @State private var environment: AppEnvironment

    init() {
        let container = Self.makeContainer()
        _environment = State(initialValue: AppEnvironment(modelContainer: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .task { await environment.start() }
        }
    }

    /// Build the persistent container, falling back to in-memory on failure so
    /// the app still launches and can surface a recoverable error state rather
    /// than crashing (brief §21: never show raw internal errors / never crash).
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([SDScheduledWorkout.self, SDAppSettings.self])
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Log and degrade to an ephemeral store; the UI shows a data-error state.
            AppLog.persistence.error("Persistent store unavailable: \(error). Falling back to in-memory.")
            let mem = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // If even this fails the app genuinely cannot run; that is a true fatal.
            return try! ModelContainer(for: schema, configurations: [mem])
        }
    }
}
