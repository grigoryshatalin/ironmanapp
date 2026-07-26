import SwiftUI
import EnduranceDomain

/// A short, native onboarding flow (brief §7). Six calm steps — no marketing
/// carousel. Requests notification permission only after the user enables at
/// least one category.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env

    /// Matches the bundled 36-week plan (36 × 7 days). Used only to show the
    /// derived date immediately; real scheduling uses the loaded plan.
    private static let planTotalDays = 252

    enum Step: Int, CaseIterable { case purpose, schedule, structure, capability, notifications, safety }

    @State private var step: Step = .purpose
    @State private var draft = Draft()
    @State private var isFinishing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.top, Theme.Space.s)

                ScrollView {
                    content
                        .padding(Theme.Space.l)
                }

                footer
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            // Standard back placement and affordance rather than a bespoke
            // control in the footer (§11). The wizard has no navigation stack to
            // pop, so this drives the step state directly while looking and
            // reading exactly like system back.
            .toolbar {
                if step != .purpose {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .purpose }
                        } label: {
                            Label("Back", systemImage: "chevron.backward")
                        }
                        .accessibilityIdentifier(A11y.Onboarding.backButton)
                    }
                }
            }
        }
    }

    // MARK: - Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .purpose:
            stepBody(icon: "figure.mixed.cardio",
                     heading: "Your 36-week plan",
                     text: "\(AppConfig.productName) organizes a complete 36-week full-distance triathlon plan and sends reminders you choose. The goal is to finish safely and consistently.\n\nThis app is not medical advice or a replacement for a qualified coach or clinician.")
        case .schedule:
            scheduleStep
        case .structure:
            structureStep
        case .capability:
            capabilityStep
        case .notifications:
            notificationsStep
        case .safety:
            safetyStep
        }
    }

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("Anchor your plan to a date. We’ll calculate the other for you.")
                .font(.body)
            Picker("Anchor", selection: $draft.anchorMode) {
                Text("Start date").tag(Draft.AnchorMode.startDate)
                Text("Race date").tag(Draft.AnchorMode.raceDate)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(A11y.Onboarding.anchorPicker)

            if draft.anchorMode == .startDate {
                DatePicker("Start date", selection: $draft.startDate, displayedComponents: .date)
                    .accessibilityIdentifier(A11y.Onboarding.startDatePicker)
                LabeledContent("Race date (calculated)", value: DisplayFormatter.longDate(derivedRaceDate))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(A11y.Onboarding.derivedDate)
            } else {
                DatePicker("Race date", selection: $draft.raceDate, displayedComponents: .date)
                    .accessibilityIdentifier(A11y.Onboarding.raceDatePicker)
                LabeledContent("Start date (calculated)", value: DisplayFormatter.longDate(derivedStartDate))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(A11y.Onboarding.derivedDate)
            }
        }
    }

    private var structureStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("Pick default times and your key days. You can change these anytime.")
                .font(.body)
            timeRow("Weekday workout time", $draft.weekdayTime)
                .accessibilityIdentifier(A11y.Onboarding.weekdayTime)
            timeRow("Weekend workout time", $draft.weekendTime)
                .accessibilityIdentifier(A11y.Onboarding.weekendTime)
            weekdayPicker("Long ride day", $draft.longBikeDay)
                .accessibilityIdentifier(A11y.Onboarding.longBikeDay)
            weekdayPicker("Long run day", $draft.longRunDay)
                .accessibilityIdentifier(A11y.Onboarding.longRunDay)
            weekdayPicker("Rest day", $draft.restDay)
                .accessibilityIdentifier(A11y.Onboarding.restDay)
            Picker("Units", selection: $draft.units) {
                ForEach(MeasurementSystem.allCases, id: \.self) { Text($0.localizedName).tag($0) }
            }
            .accessibilityIdentifier(A11y.Onboarding.units)
        }
    }

    private var capabilityStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Optional — a quick sense of where you’re starting. This informs gentle guidance later and never silently rewrites your plan.")
                .font(.body).foregroundStyle(.secondary)
            Toggle("I have regular pool access", isOn: $draft.hasPool)
            Toggle("I have open-water access", isOn: $draft.hasOpenWater)
            Toggle("I have an indoor trainer", isOn: $draft.hasTrainer)
            Toggle("I can do strength training", isOn: $draft.hasStrength)
        }
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Reminders are optional and off by default. Turn on only what’s useful — we’ll ask for permission only if you enable at least one.")
                .font(.body).foregroundStyle(.secondary)
            ForEach(NotificationCategory.allCases, id: \.self) { cat in
                Toggle(isOn: Binding(
                    get: { draft.enabledCategories.contains(cat) },
                    set: { on in if on { draft.enabledCategories.insert(cat) } else { draft.enabledCategories.remove(cat) } }
                )) {
                    Label(cat.localizedName, systemImage: cat.symbolName)
                }
                .accessibilityIdentifier(A11y.Onboarding.category(cat.rawValue))
            }
        }
    }

    private var safetyStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Label("A note on safety", systemImage: "heart.text.square")
                .font(.headline)
            Text("Training for a full-distance triathlon places substantial stress on the body. Seek professional guidance when appropriate. Don’t ignore pain, illness, dizziness, chest symptoms, or unusual fatigue. This app does not provide medical diagnosis.")
                .font(.body)
            Toggle("I understand", isOn: $draft.acknowledgedSafety)
                .font(.callout)
                .accessibilityIdentifier(A11y.Onboarding.safetyAcknowledge)
        }
    }

    // MARK: - Footer / navigation

    private var footer: some View {
        HStack {
            Spacer()
            Button(step == .safety ? "Start training" : "Continue") {
                advance()
            }
            .buttonStyle(.borderedProminent)
            .disabled(step == .safety && !draft.acknowledgedSafety)
            .accessibilityIdentifier(A11y.Onboarding.continueButton)
        }
        .padding(Theme.Space.l)
        .background(.bar)
    }

    private func advance() {
        if step == .safety {
            Task { await finish() }
        } else if let next = Step(rawValue: step.rawValue + 1) {
            withAnimation { step = next }
        }
    }

    private func finish() async {
        guard !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }

        let anchor: PlanAnchor = draft.anchorMode == .startDate ? .startDate(draft.startDate) : .raceDate(draft.raceDate)
        let config = ScheduleConfiguration(
            anchor: anchor,
            startWeekday: 2,
            weekdayDefaultTime: draft.weekdayTime,
            weekendDefaultTime: draft.weekendTime,
            timeZoneIdentifier: TimeZone.current.identifier,
            preferredLongBikeWeekday: draft.longBikeDay,
            preferredLongRunWeekday: draft.longRunDay,
            preferredRestWeekday: draft.restDay)
        let prefs = NotificationPreferences(enabledCategories: draft.enabledCategories)

        do {
            try env.store.completeOnboarding(configuration: config, units: draft.units, preferences: prefs, raceName: nil, raceLocation: nil)
            // The system permission alert is owned by SpringBoard and cannot be
            // dismissed reliably from XCUITest across OS versions, so tests opt
            // out of the prompt rather than the app skipping it silently.
            let suppressPrompt = CommandLine.arguments.contains(A11y.LaunchArgument.suppressNotificationPrompt)
            if !draft.enabledCategories.isEmpty && !suppressPrompt {
                _ = await env.notifications.requestAuthorization()
            }
            await env.refreshSideEffects()
        } catch {
            AppLog.app.error("Onboarding failed: \(error)")
            env.alert = .dataError
        }
    }

    // MARK: - Derived dates

    private var derivedRaceDate: Date {
        Calendar.current.date(byAdding: .day, value: Self.planTotalDays - 1, to: draft.startDate) ?? draft.startDate
    }
    private var derivedStartDate: Date {
        Calendar.current.date(byAdding: .day, value: -(Self.planTotalDays - 1), to: draft.raceDate) ?? draft.raceDate
    }

    // MARK: - Small helpers

    private var title: String {
        switch step {
        case .purpose: return "Welcome"
        case .schedule: return "Schedule"
        case .structure: return "Weekly structure"
        case .capability: return "Where you’re at"
        case .notifications: return "Reminders"
        case .safety: return "Safety"
        }
    }

    private func stepBody(icon: String, heading: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.tint)
            Text(heading).font(.title2).bold()
            Text(text).font(.body)
        }
    }

    private func timeRow(_ label: String, _ binding: Binding<TimeOfDay>) -> some View {
        DatePicker(label, selection: Binding(
            get: { dateFrom(binding.wrappedValue) },
            set: { binding.wrappedValue = timeOfDay(from: $0) }
        ), displayedComponents: .hourAndMinute)
    }

    private func weekdayPicker(_ label: String, _ binding: Binding<Int>) -> some View {
        Picker(label, selection: binding) {
            ForEach(1...7, id: \.self) { Text(weekdayName($0)).tag($0) }
        }
    }

    private func dateFrom(_ t: TimeOfDay) -> Date {
        Calendar.current.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: Date()) ?? Date()
    }
    private func timeOfDay(from date: Date) -> TimeOfDay {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: c.hour ?? 6, minute: c.minute ?? 30)
    }
    private func weekdayName(_ n: Int) -> String {
        Calendar.current.weekdaySymbols[(n - 1) % 7]
    }
    /// Normally today, so the plan begins now. In DEBUG a launch argument can
    /// backdate it, which is how screenshot capture lands on a specific day of
    /// the plan (a recovery day, a two-session day) deterministically. Release
    /// builds always start today.
    /// `nonisolated` because it is used as a default value inside `Draft`, which
    /// is constructed outside the main actor. It touches nothing mutable.
    nonisolated static var defaultStartDate: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        #if DEBUG
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: A11y.LaunchArgument.startDayOffset),
           args.index(after: flag) < args.endIndex,
           let offset = Int(args[args.index(after: flag)]) {
            return calendar.date(byAdding: .day, value: -offset, to: today) ?? today
        }
        #endif
        return today
    }

    // MARK: - Draft model

    struct Draft {
        enum AnchorMode { case startDate, raceDate }
        var anchorMode: AnchorMode = .startDate
        var startDate: Date = OnboardingView.defaultStartDate
        var raceDate: Date = Calendar.current.date(byAdding: .day, value: 251, to: Date()) ?? Date()
        var weekdayTime: TimeOfDay = .defaultWeekday
        var weekendTime: TimeOfDay = .defaultWeekend
        var longBikeDay = 7   // Saturday
        var longRunDay = 1    // Sunday
        var restDay = 2       // Monday
        var units: MeasurementSystem = .metric
        var hasPool = false
        var hasOpenWater = false
        var hasTrainer = false
        var hasStrength = false
        var enabledCategories: Set<NotificationCategory> = []
        var acknowledgedSafety = false
    }
}
