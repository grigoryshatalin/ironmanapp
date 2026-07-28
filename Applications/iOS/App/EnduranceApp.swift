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
                .interruptedSessionPrompt(environment)
        }
    }

    /// Build the persistent container, falling back to in-memory on failure so
    /// the app still launches and can surface a recoverable error state rather
    /// than crashing (brief §21: never show raw internal errors / never crash).
    private static func makeContainer() -> ModelContainer {
        let schema = EnduranceSchema.current
        // UI tests need a guaranteed-cold start. The flag is passed only on the
        // FIRST launch of a test, so subsequent relaunches in the same test see
        // real persisted data — which is the whole point of those assertions.
        if CommandLine.arguments.contains(A11y.LaunchArgument.freshInstall) {
            eraseStoreFiles()
        }
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            // A Release 1 store is migrated forward here. The stage is additive
            // and lightweight, so nothing is rewritten and no data is lost;
            // `MigrationTests` proves that against a real on-disk V1 store.
            return try ModelContainer(
                for: schema,
                migrationPlan: EnduranceSchema.migrationPlan,
                configurations: [config])
        } catch {
            // A migration failure must never look like a crash or silently
            // discard the athlete's history (§P). Degrade to an ephemeral store
            // so the app still launches and can explain itself; the on-disk
            // store is left untouched for a later retry.
            AppLog.persistence.error("Persistent store unavailable: \(error). Falling back to in-memory.")
            let mem = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // If even this fails the app genuinely cannot run; that is a true fatal.
            return try! ModelContainer(for: schema, configurations: [mem])
        }
    }

    /// Remove SwiftData's default store so the next launch starts at onboarding.
    private static func eraseStoreFiles() {
        let fm = FileManager.default
        guard let support = try? fm.url(for: .applicationSupportDirectory,
                                        in: .userDomainMask,
                                        appropriateFor: nil,
                                        create: false) else { return }
        // SwiftData writes default.store plus -wal / -shm siblings.
        for name in ["default.store", "default.store-wal", "default.store-shm"] {
            let url = support.appending(path: name)
            if fm.fileExists(atPath: url.path) {
                do { try fm.removeItem(at: url) }
                catch { AppLog.persistence.error("Could not erase \(name, privacy: .public): \(error)") }
            }
        }
    }
}
