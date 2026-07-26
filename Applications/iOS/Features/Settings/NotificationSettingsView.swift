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

    var body: some View {
        List {
            authSection

            Section("Categories") {
                ForEach(NotificationCategory.allCases, id: \.self) { cat in
                    Toggle(isOn: binding(for: cat)) {
                        Label(title(cat), systemImage: cat.symbolName)
                    }
                }
            }

            Section("Timing") {
                Stepper("Workout reminder: \(prefs.workoutLeadMinutes) min before",
                        value: bindingInt(\.workoutLeadMinutes), in: 0...240, step: 15)
                Stepper("Scheduling window: \(prefs.schedulingWindowDays) days",
                        value: bindingInt(\.schedulingWindowDays), in: 7...35, step: 7)
            } footer: {
                Text("iOS keeps at most 64 pending reminders. \(AppConfig.productName) schedules the soonest ones and refreshes them automatically.")
            }
        }
        .navigationTitle("Notifications")
        .task {
            prefs = store.notificationPreferences
            authStatus = await env.notifications.authorizationStatus()
        }
    }

    @ViewBuilder private var authSection: some View {
        Section {
            switch authStatus {
            case .authorized, .provisional, .ephemeral:
                Label("Notifications are allowed", systemImage: "checkmark.circle").foregroundStyle(.green)
            case .denied:
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Label("Notifications are turned off", systemImage: "bell.slash").foregroundStyle(.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            case .notDetermined:
                Button("Enable notifications") {
                    Task {
                        _ = await env.notifications.requestAuthorization()
                        authStatus = await env.notifications.authorizationStatus()
                        await env.refreshSideEffects()
                    }
                }
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

    private func title(_ c: NotificationCategory) -> String {
        switch c {
        case .preparation: return "Preparation (evening before)"
        case .workout: return "Workout reminders"
        case .secondReminder: return "Second reminder"
        case .fueling: return "Long-session fueling"
        case .recovery: return "Recovery check"
        case .weeklyReview: return "Weekly review"
        }
    }
}
