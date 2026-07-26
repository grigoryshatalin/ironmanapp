import SwiftUI
import EnduranceDomain

/// Native grouped settings (brief §12). Destructive actions use native
/// confirmation; export uses the share sheet.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    private var store: WorkoutStore { env.store }

    @State private var confirmingReset = false
    @State private var confirmingDelete = false
    @State private var exportURL: URL?
    @State private var exportSummary: ExportSummary?
    @State private var exportTick = 0

    var body: some View {
        List {
            planSection
            Section("Reminders") {
                NavigationLink { NotificationSettingsView() } label: {
                    Label("Notifications", systemImage: "bell")
                }
                .accessibilityIdentifier(A11y.Settings.notifications)
            }
            Section("Training") {
                NavigationLink { TrainingZonesView() } label: {
                    Label("Training zones", systemImage: "gauge.with.dots.needle.33percent")
                }
                .accessibilityIdentifier(A11y.Settings.trainingZones)
                Label("Health access — available in a later update", systemImage: "heart")
                    .foregroundStyle(.secondary)
            }
            dataSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .haptic(.exported, trigger: exportTick)
        .task { refreshExport() }
        .confirmationDialog("Reset completion history?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset history", role: .destructive) { perform { try store.resetCompletionHistory() } }
        } message: {
            Text("Your schedule stays; all logged completions and modifications are cleared. This can’t be undone.")
        }
        .confirmationDialog("Delete all local data?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { perform { try store.deleteAllData() } }
        } message: {
            Text("This removes your plan, schedule, history, and settings from this device. This can’t be undone.")
        }
    }

    private var planSection: some View {
        Section("Plan") {
            Picker("Units", selection: Binding(get: { store.units }, set: { u in perform { try store.updateUnits(u) } })) {
                ForEach(MeasurementSystem.allCases, id: \.self) { Text($0.localizedName).tag($0) }
            }
            .accessibilityIdentifier(A11y.Settings.units)
            NavigationLink { PlanDatesView() } label: {
                Label("Adjust start / race date", systemImage: "calendar")
            }
            .accessibilityIdentifier(A11y.Settings.planDates)
            NavigationLink { PreferredDaysView() } label: {
                Label("Preferred training days", systemImage: "calendar.badge.clock")
            }
            .accessibilityIdentifier(A11y.Settings.preferredDays)
        }
    }

    private var dataSection: some View {
        Section {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Export training data (JSON)", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier(A11y.Settings.export)
            }
            // Proving the export is *parseable* belongs in the app, not only in a
            // test: this row is produced by encoding the export and decoding it
            // back, so a corrupt export is visible before it is ever shared (§12,
            // §31 "exported data can be re-imported or parsed").
            if let exportSummary {
                HStack {
                    Text("Export contents")
                    Spacer()
                    // Identifier sits on the value leaf, not the row: an
                    // identifier on a container overrides every descendant's.
                    Text(verbatim: exportSummary.description)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(A11y.Settings.exportSummary)
                }
                .font(.footnote)
            }
            Button(role: .destructive) { confirmingReset = true } label: {
                Label("Reset completion history", systemImage: "arrow.counterclockwise")
            }
            .accessibilityIdentifier(A11y.Settings.resetHistory)
            Button(role: .destructive) { confirmingDelete = true } label: {
                Label("Delete all data", systemImage: "trash")
            }
            .accessibilityIdentifier(A11y.Settings.deleteAll)
        } header: {
            Text("Data")
        } footer: {
            Text("Exports are plain JSON and stay on your device until you share them.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
                .accessibilityIdentifier(A11y.Settings.version)
            Text("\(AppConfig.productName) keeps your data on this device. There are no accounts, ads, or analytics.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("This app is educational and general. It is not medical advice or a substitute for a qualified coach or clinician. Seek professional guidance for pain, illness, or unusual symptoms.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    /// Write the export, then read it back so the summary reflects what a
    /// consumer would actually parse — not what we intended to write.
    private func refreshExport() {
        guard let export = store.makeExport(), let data = try? ExportService.encode(export) else {
            exportURL = nil
            exportSummary = nil
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Endurance-Export.json")
        do {
            try data.write(to: url, options: .atomic)
            let roundTripped = try ExportService.decode(Data(contentsOf: url))
            exportURL = url
            exportSummary = ExportSummary(
                sessions: roundTripped.scheduledWorkouts.count,
                logged: roundTripped.scheduledWorkouts.filter { $0.status.countsAsDone }.count,
                bytes: data.count)
            exportTick += 1
        } catch {
            AppLog.app.error("Export failed: \(error)")
            exportURL = nil
            exportSummary = nil
            env.alert = .exportFailed
        }
    }

    private func perform(_ work: @escaping () throws -> Void) {
        Task {
            do {
                try work()
                await env.refreshSideEffects()
                refreshExport()
            } catch {
                AppLog.app.error("Settings action failed: \(error)")
                env.alert = .dataError
            }
        }
    }
}

/// What a freshly written export actually contains, measured by decoding it.
struct ExportSummary: Equatable {
    let sessions: Int
    let logged: Int
    let bytes: Int

    var description: String {
        String(localized: "\(sessions) sessions · \(logged) logged")
    }
}

/// Adjust the plan anchor. Explains what will change and preserves history.
struct PlanDatesView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    private var store: WorkoutStore { env.store }

    @State private var startDate = Date()

    var body: some View {
        Form {
            Section {
                DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    .accessibilityIdentifier(A11y.PlanDates.startDate)
            } footer: {
                Text("Changing this recalculates future planned dates only. Completed sessions keep their dates, and outdated reminders are refreshed automatically.")
            }
            Section {
                Button("Apply new dates") { apply() }
                    .accessibilityIdentifier(A11y.PlanDates.apply)
            }
        }
        .navigationTitle("Adjust dates")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if case let .startDate(d)? = store.configuration?.anchor { startDate = d }
        }
    }

    private func apply() {
        // Carry every existing preference forward. Rebuilding the configuration
        // from scratch here would silently discard the athlete's preferred
        // long-ride / long-run / rest days.
        guard var cfg = store.configuration else { return }
        cfg.anchor = .startDate(startDate)
        Task {
            do {
                try store.changeAnchor(to: cfg)
                await env.refreshSideEffects()
                dismiss()
            } catch {
                AppLog.app.error("Anchor change failed: \(error)")
                env.alert = .dataError
            }
        }
    }
}

/// Change which weekdays carry the long ride, long run, and rest day. Applying
/// regenerates the future schedule through the same transform onboarding uses.
struct PreferredDaysView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    private var store: WorkoutStore { env.store }

    @State private var longBike = 7
    @State private var longRun = 1
    @State private var rest = 2

    var body: some View {
        Form {
            Section {
                weekdayPicker("Long ride day", $longBike)
                    .accessibilityIdentifier(A11y.PlanDates.longBikeDay)
                weekdayPicker("Long run day", $longRun)
                    .accessibilityIdentifier(A11y.PlanDates.longRunDay)
                weekdayPicker("Rest day", $rest)
                    .accessibilityIdentifier(A11y.PlanDates.restDay)
            } footer: {
                Text("Whole days are moved together, so a brick run stays with its ride and recovery stays after your long run. Completed sessions keep their dates.")
            }
            Section {
                Button("Apply") { apply() }
                    .accessibilityIdentifier(A11y.PlanDates.apply)
            }
        }
        .navigationTitle("Preferred days")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let c = store.configuration {
                longBike = c.preferredLongBikeWeekday ?? 7
                longRun = c.preferredLongRunWeekday ?? 1
                rest = c.preferredRestWeekday ?? 2
            }
        }
    }

    private func weekdayPicker(_ label: LocalizedStringKey, _ binding: Binding<Int>) -> some View {
        Picker(label, selection: binding) {
            ForEach(1...7, id: \.self) { n in
                Text(Calendar.current.weekdaySymbols[(n - 1) % 7]).tag(n)
            }
        }
    }

    private func apply() {
        guard var cfg = store.configuration else { return }
        cfg.preferredLongBikeWeekday = longBike
        cfg.preferredLongRunWeekday = longRun
        cfg.preferredRestWeekday = rest
        Task {
            do {
                try store.applyPreferredDays(cfg)
                await env.refreshSideEffects()
                dismiss()
            } catch {
                AppLog.app.error("Preferred-day change failed: \(error)")
                env.alert = .dataError
            }
        }
    }
}

/// Placeholder for configurable zones — the app is fully usable on RPE alone.
struct TrainingZonesView: View {
    var body: some View {
        List {
            Section {
                Text("The app works on perceived exertion (RPE) with no sensors required. Heart-rate, power, pace, and swim-pace zones are configurable in a later update.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Perceived exertion") {
                ForEach(IntensityZone.allCases, id: \.self) { z in
                    LabeledContent {
                        Text("RPE \(z.rpeRange.lowerBound)–\(z.rpeRange.upperBound)")
                    } label: {
                        Text(verbatim: z.localizedName)
                    }
                }
            }
        }
        .navigationTitle("Training zones")
    }
}
