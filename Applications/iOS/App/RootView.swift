import SwiftUI
import EnduranceDomain

/// Native 4-tab shell, each tab its own `NavigationStack` (brief §6). Shows
/// onboarding until the plan is configured.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var env = env
        Group {
            if env.store.isConfigured {
                TabView(selection: $env.selectedTab) {
                    NavigationStack {
                        TodayView()
                    }
                    .tabItem {
                        Label("Today", systemImage: Theme.availableSymbol("figure.mixed.cardio", fallback: "sun.max"))
                            .accessibilityIdentifier(A11y.Tab.today)
                    }
                    .tag(AppTab.today)

                    NavigationStack {
                        PlanView()
                    }
                    .tabItem {
                        Label("Plan", systemImage: "calendar")
                            .accessibilityIdentifier(A11y.Tab.plan)
                    }
                    .tag(AppTab.plan)

                    NavigationStack {
                        ProgressDashboardView()
                    }
                    .tabItem {
                        Label("Progress", systemImage: Theme.availableSymbol("chart.xyaxis.line", fallback: "chart.bar"))
                            .accessibilityIdentifier(A11y.Tab.progress)
                    }
                    .tag(AppTab.progress)

                    NavigationStack {
                        SettingsView()
                    }
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                            .accessibilityIdentifier(A11y.Tab.settings)
                    }
                    .tag(AppTab.settings)
                }
            } else {
                OnboardingView()
            }
        }
        .alert(item: $env.alert) { alert in
            switch alert {
            case .dataError:
                return Alert(title: Text("Couldn’t open your data"),
                             message: Text("Your training data couldn’t be loaded. Your information is safe — please relaunch. If this continues, you can reset the app in Settings."),
                             dismissButton: .default(Text("OK")))
            case .exportFailed:
                return Alert(title: Text("Export didn’t finish"),
                             message: Text("The export couldn’t be created. Please try again."),
                             dismissButton: .default(Text("OK")))
            }
        }
    }
}
