import SwiftUI
import UIKit
import UserNotifications
import EnduranceDomain

/// Per-category reminder toggles + authorization status (brief §12/§13).
struct NotificationSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    private var store: WorkoutStore { env.store }

    @State private var prefs = NotificationPreferences()
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    #if DEBUG
    @State private var diagnosticState: DiagnosticState = .idle

    enum DiagnosticState: Equatable {
        case idle, scheduling, scheduled(String), failed(String)
    }
    #endif

    var body: some View {
        List {
            authSection

            Section("Categories") {
                ForEach(NotificationCategory.allCases, id: \.self) { cat in
                    Toggle(isOn: binding(for: cat)) {
                        Label(cat.localizedName, systemImage: cat.symbolName)
                    }
                    .accessibilityIdentifier(A11y.Notifications.category(cat.rawValue))
                }
            }

            // `Section` has no (title, content:, footer:) initializer — a string
            // title and a footer are mutually exclusive, so use the explicit
            // header/footer form.
            Section {
                Stepper("Workout reminder: \(prefs.workoutLeadMinutes) min before",
                        value: bindingInt(\.workoutLeadMinutes), in: 0...240, step: 15)
                Stepper("Scheduling window: \(prefs.schedulingWindowDays) days",
                        value: bindingInt(\.schedulingWindowDays), in: 7...35, step: 7)
            } header: {
                Text("Timing")
            } footer: {
                Text("iOS keeps at most 64 pending reminders. \(AppConfig.productName) schedules the soonest ones and refreshes them automatically.")
            }
            #if DEBUG
            diagnosticSection
            #endif
        }
        .navigationTitle("Notifications")
        .task {
            prefs = store.notificationPreferences
            authStatus = await env.notifications.authorizationStatus()
        }
    }

    #if DEBUG
    /// Developer-only. Fires a real reminder for a real session in five seconds,
    /// through the production payload path, so the tap-handling behaviour can be
    /// exercised on demand instead of waiting for a scheduled reminder.
    @ViewBuilder private var diagnosticSection: some View {
        Section {
            Button("Send test reminder (5s)") {
                Task { await sendDiagnostic() }
            }
            .disabled(authStatus != .authorized || diagnosticState == .scheduling)
            .accessibilityIdentifier(A11y.Notifications.sendTest)

            NavigationLink("Pending reminders…") {
                NotificationDiagnosticsView()
            }
            .accessibilityIdentifier(A11y.Notifications.diagnostics)

            switch diagnosticState {
            case .idle:
                EmptyView()
            case .scheduling:
                Text("Scheduling…").font(.footnote).foregroundStyle(.secondary)
            case .scheduled(let title):
                Text("Sent for “\(title)”. Lock the phone or leave this screen, then tap the banner.")
                    .font(.footnote).foregroundStyle(.secondary)
            case .failed(let reason):
                Text(reason).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("Debug builds only. Uses the same payload and deep link as a real workout reminder.")
        }
    }

    private func sendDiagnostic() async {
        diagnosticState = .scheduling
        // Prefer an upcoming session; fall back to any session so the deep link
        // always points at something that genuinely exists.
        let all = store.allWorkouts.sorted { $0.plannedStart < $1.plannedStart }
        guard let workout = all.first(where: { $0.plannedStart >= Date() }) ?? all.first else {
            diagnosticState = .failed(String(localized: "No sessions scheduled yet."))
            return
        }
        let ok = await env.notifications.scheduleDiagnosticReminder(for: workout)
        diagnosticState = ok
            ? .scheduled(workout.title)
            : .failed(String(localized: "Couldn’t schedule — check notification permission."))
    }
    #endif

    @ViewBuilder private var authSection: some View {
        Section {
            switch authStatus {
            case .authorized, .provisional, .ephemeral:
                // Status is stated in words; the symbol reinforces it. No
                // color-only signalling.
                Label("Notifications are allowed", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(A11y.Notifications.authStatus)
            case .denied:
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Label("Notifications are turned off", systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .accessibilityIdentifier(A11y.Notifications.openSettings)
                }
                .accessibilityIdentifier(A11y.Notifications.authStatus)
            case .notDetermined:
                Button("Enable notifications") {
                    Task {
                        _ = await env.notifications.requestAuthorization()
                        authStatus = await env.notifications.authorizationStatus()
                        await env.refreshSideEffects()
                    }
                }
                .accessibilityIdentifier(A11y.Notifications.authStatus)
            @unknown default:
                EmptyView()
            }
        }
    }

    private func binding(for cat: NotificationCategory) -> Binding<Bool> {
        Binding(
            get: { prefs.enabledCategories.contains(cat) },
            set: { on in
                if on { prefs.enabledCategories.insert(cat) } else { prefs.enabledCategories.remove(cat) }
                save()
            })
    }

    private func bindingInt(_ keyPath: WritableKeyPath<NotificationPreferences, Int>) -> Binding<Int> {
        Binding(get: { prefs[keyPath: keyPath] }, set: { prefs[keyPath: keyPath] = $0; save() })
    }

    private func save() {
        Task {
            do {
                try store.updatePreferences(prefs)
                // Enabling a category for the first time prompts for permission.
                if !prefs.enabledCategories.isEmpty, authStatus == .notDetermined {
                    _ = await env.notifications.requestAuthorization()
                    authStatus = await env.notifications.authorizationStatus()
                }
                await env.refreshSideEffects()
            } catch { env.alert = .dataError }
        }
    }

}
