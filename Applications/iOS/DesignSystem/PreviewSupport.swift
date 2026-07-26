#if DEBUG
import SwiftUI
import SwiftData
import EnduranceDomain

/// Preview fixtures. Builds a fully-onboarded, in-memory environment from the
/// real bundled plan — so previews exercise production code paths, and the
/// production app never depends on preview-only data (brief §26).
@MainActor
enum PreviewSupport {
    static func onboardedEnvironment(units: MeasurementSystem = .metric) -> AppEnvironment {
        let schema = Schema([SDScheduledWorkout.self, SDAppSettings.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // In a preview a failure here is a developer error; surfacing it is fine.
        let container = try! ModelContainer(for: schema, configurations: [config])
        let env = AppEnvironment(modelContainer: container)
        let scheduleConfig = ScheduleConfiguration(
            anchor: .startDate(Calendar.current.startOfDay(for: Date())),
            timeZoneIdentifier: TimeZone.current.identifier)
        try? env.store.completeOnboarding(
            configuration: scheduleConfig, units: units,
            preferences: NotificationPreferences(), raceName: "Test Ironman", raceLocation: nil)
        return env
    }

    static func firstWorkoutID(_ env: AppEnvironment) -> UUID {
        env.store.workouts(inWeek: 6).first?.id ?? env.store.allWorkouts.first!.id
    }
}

#Preview("Today") {
    let env = PreviewSupport.onboardedEnvironment()
    return NavigationStack { TodayView() }.environment(env)
}

#Preview("Today — Dark") {
    let env = PreviewSupport.onboardedEnvironment()
    return NavigationStack { TodayView() }.environment(env).preferredColorScheme(.dark)
}

#Preview("Today — Large type") {
    let env = PreviewSupport.onboardedEnvironment(units: .imperial)
    return NavigationStack { TodayView() }
        .environment(env)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Plan") {
    let env = PreviewSupport.onboardedEnvironment()
    return NavigationStack { PlanView() }.environment(env)
}

#Preview("Workout detail") {
    let env = PreviewSupport.onboardedEnvironment()
    let id = PreviewSupport.firstWorkoutID(env)
    return NavigationStack { WorkoutDetailView(workoutID: id) }.environment(env)
}

#Preview("Progress") {
    let env = PreviewSupport.onboardedEnvironment()
    return NavigationStack { ProgressDashboardView() }.environment(env)
}

#Preview("Settings") {
    let env = PreviewSupport.onboardedEnvironment()
    return NavigationStack { SettingsView() }.environment(env)
}

#Preview("Onboarding") {
    let env = PreviewSupport.onboardedEnvironment()
    return OnboardingView().environment(env)
}
#endif
