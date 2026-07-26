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

    var body: some View {
        List {
            planSection
            Section("Reminders") {
                NavigationLink { NotificationSettingsView() } label: {
                    Label("Notifications", systemImage: "bell")
                }
            }
            Section("Training") {
                NavigationLink { TrainingZonesView() } label: { Label("Training zones", systemImage: "gauge.with.dots.needle.33percent") }
                Label("Health access — available in a later update", systemImage: "heart")
                    .foregroundStyle(.secondary)
            }
            dataSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .task { exportURL = writeExport() }
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
                ForEach(MeasurementSystem.allCases, id: \.self) { Text($0.englishName).tag($0) }
            }
            NavigationLink { PlanDatesView() } label: { Label("Adjust start / race date", systemImage: "calendar") }
        }
    }

    private var dataSection: some View {
        Section("Data") {
            if let exportURL {
                ShareLink(item: exportURL) { Label("Export training data (JSON)", systemImage: "square.and.arrow.up") }
            }
            Button(role: .destructive) { confirmingReset = true } label: { Label("Reset completion history", systemImage: "arrow.counterclockwise") }
            Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete all data", systemImage: "trash") }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
            Text("\(AppConfig.productName) keeps your data on this device. There are no accounts, ads, or analytics.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("This app is educational and general. It is not medical advice or a substitute for a qualified coach or clinician. Seek professional guidance for pain, illness, or unusual symptoms.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func writeExport() -> URL? {
        guard let export = store.makeExport(), let data = try? ExportService.encode(export) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Endurance-Export.json")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    private func perform(_ work: @escaping () throws -> Void) {
        Task {
            do { try work(); await env.refreshSideEffects(); exportURL = writeExport() }
            catch { AppLog.app.error("Settings action failed: \(error)"); env.alert = .dataError }
        }
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
            } footer: {
                Text("Changing this recalculates future planned dates only. Completed sessions keep their dates, and outdated reminders are refreshed automatically.")
            }
            Section {
                Button("Apply new dates") {
                    let cfg = ScheduleConfiguration(
                        anchor: .startDate(startDate),
                        startWeekday: store.configuration?.startWeekday ?? 2,
                        weekdayDefaultTime: store.configuration?.weekdayDefaultTime ?? .defaultWeekday,
                        weekendDefaultTime: store.configuration?.weekendDefaultTime ?? .defaultWeekend,
                        timeZoneIdentifier: store.configuration?.timeZoneIdentifier)
                    Task {
                        do { try store.changeAnchor(to: cfg); await env.refreshSideEffects(); dismiss() }
                        catch { env.alert = .dataError }
                    }
                }
            }
        }
        .navigationTitle("Adjust dates")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if case let .startDate(d)? = store.configuration?.anchor { startDate = d }
        }
    }
}

/// Placeholder for configurable zones — the app is fully usable on RPE alone.
struct TrainingZonesView: View {
    var body: some View {
        List {
            Section {
                Text("The app works on perceived exertion (RPE) with no sensors required. Heart-rate, power, pace, and swim-pace zones are configurable in a later update.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Perceived exertion") {
                ForEach(IntensityZone.allCases, id: \.self) { z in
                    LabeledContent(z.englishName, value: "RPE \(z.rpeRange.lowerBound)–\(z.rpeRange.upperBound)")
                }
            }
        }
        .navigationTitle("Training zones")
    }
}
