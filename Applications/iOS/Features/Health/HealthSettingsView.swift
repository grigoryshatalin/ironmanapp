import SwiftUI
import UIKit
import EnduranceDomain
import EnduranceHealth

/// The Health section (§C, §M).
///
/// The system permission sheet is never the first thing the athlete sees: this
/// screen explains what is read, what is written, why each helps, and that the
/// plan works without any of it — *before* offering to connect.
struct HealthSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    private var health: HealthCoordinator { env.health }
    private var export: HealthExportCoordinator { env.healthExport }

    var body: some View {
        List {
            statusSection
            if health.connection != .unavailable {
                explanationSection
                controlsSection
                inboxSection
                manageSection
            }
            reassuranceSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Health")
        .navigationBarTitleDisplayMode(.inline)
        .task { await health.refreshConnectionState() }
        .refreshable { await health.runImport() }
    }

    // MARK: - Status

    @ViewBuilder private var statusSection: some View {
        Section {
            switch health.connection {
            case .unavailable:
                Label("Health data isn’t available on this device", systemImage: "heart.slash")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(A11y.Health.status)
            case .notConnected:
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Label("Not connected", systemImage: "heart")
                        .foregroundStyle(.secondary)
                    Text("Connect Health to have completed workouts appear against your plan automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier(A11y.Health.status)
            case .connected:
                Label("Connected", systemImage: "heart.text.square")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(A11y.Health.status)
            case .importPaused:
                Label("Connected · importing paused", systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(A11y.Health.status)
            }

            if let last = health.lastSuccessfulImport {
                LabeledContent("Last import") {
                    Text(last, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier(A11y.Health.lastImport)
            }
            if health.lastErrorCode != nil {
                Label("Last import didn’t finish. Your training data is unchanged — pull down to try again.",
                      systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(A11y.Health.errorState)
            }
        }
    }

    // MARK: - What and why

    private var explanationSection: some View {
        Section {
            ForEach(HealthCapabilityPlan.coreImport, id: \.self) { capability in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                    Image(systemName: symbol(for: capability))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(capability.localizedName)
                        Text(reason(for: capability))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("What Endurance reads")
        } footer: {
            Text("Endurance only writes workouts you log here, and only if you turn that on. It never edits workouts created by other apps.")
        }
    }

    // MARK: - Controls

    @ViewBuilder private var controlsSection: some View {
        Section {
            if health.connection == .notConnected {
                Button("Connect Health") {
                    Task { await health.connect() }
                }
                .accessibilityIdentifier(A11y.Health.connect)
            } else {
                Toggle("Import completed workouts", isOn: importBinding)
                    .accessibilityIdentifier(A11y.Health.importToggle)
                Toggle("Save my logged workouts to Health", isOn: exportBinding)
                    .accessibilityIdentifier(A11y.Health.exportToggle)
                LabeledContent("Saving") {
                    Text(exportStateDescription)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .font(.footnote)
                .accessibilityIdentifier(A11y.Health.exportState)
                if export.writeStatus == .denied {
                    Button("Open Health permissions") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .accessibilityIdentifier(A11y.Health.exportOpenSettings)
                }
            }
        } footer: {
            Text("Both are optional and independent. Endurance writes only the workouts you log here — never invented heart rate, power, or route data — and never re-saves a workout that came from Health.")
        }
    }

    /// A truthful state, never an implied permission (§4).
    private var exportStateDescription: String {
        guard export.isAutoExportEnabled else { return String(localized: "Off") }
        if !health.connection.isUsable { return String(localized: "Saving unavailable") }
        switch export.writeStatus {
        case .authorized: return String(localized: "Ready to save")
        case .denied: return String(localized: "Permission needed")
        case .notDetermined: return String(localized: "Permission needed")
        case .unknowable: return String(localized: "Partially available")
        }
    }

    private var importBinding: Binding<Bool> {
        Binding(
            get: { health.isImportEnabled },
            set: { on in
                health.isImportEnabled = on
                Task { if on { await health.runImport() } else { await health.refreshConnectionState() } }
            })
    }

    /// Enabling export is what triggers the write-authorization request — never
    /// at launch, and never bundled with the read request (§4).
    private var exportBinding: Binding<Bool> {
        Binding(
            get: { export.isAutoExportEnabled },
            set: { on in
                health.isExportEnabled = on
                if on {
                    Task { await export.enableExport() }
                } else {
                    export.isAutoExportEnabled = false
                }
            })
    }

    // MARK: - Inbox

    @ViewBuilder private var inboxSection: some View {
        Section {
            NavigationLink {
                HealthInboxView()
            } label: {
                HStack {
                    Label("Health Inbox", systemImage: "tray")
                    Spacer()
                    if !health.inbox.isEmpty {
                        Text("\(health.inbox.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier(A11y.Health.inboxLink)
        } footer: {
            Text("Workouts Endurance couldn’t match on its own wait here for you to decide.")
        }
    }

    // MARK: - Manage

    private var manageSection: some View {
        Section {
            Button("Open Health permissions") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .accessibilityIdentifier(A11y.Health.openSystemSettings)

            Button(role: .destructive) {
                health.disconnect()
            } label: {
                Text("Disconnect Health")
            }
            .accessibilityIdentifier(A11y.Health.disconnect)
        } footer: {
            Text("Disconnecting stops importing and removes Endurance’s import records. Your training history stays, and workouts owned by other apps are never touched.")
        }
    }

    private var reassuranceSection: some View {
        Section {
            Text("Health data is processed only on this device. Endurance has no account and no server, and never uploads your health or workout data.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Copy

    private func symbol(for capability: HealthCapability) -> String {
        switch capability {
        case .workouts: return "figure.mixed.cardio"
        case .heartRate, .restingHeartRate: return "heart"
        case .runningDistance: return "figure.run"
        case .cyclingDistance: return "bicycle"
        case .swimmingDistance: return "figure.pool.swim"
        case .activeEnergy: return "flame"
        case .cyclingPower, .runningPower: return "bolt"
        case .workoutRoute: return "map"
        }
    }

    /// Why each capability helps — specific, so the athlete can judge it.
    private func reason(for capability: HealthCapability) -> String {
        switch capability {
        case .workouts:
            return String(localized: "Matches finished sessions to your plan, so you don’t log them twice.")
        case .heartRate:
            return String(localized: "Shows the effort you actually held, alongside the session’s target.")
        case .runningDistance:
            return String(localized: "Fills in how far you ran.")
        case .cyclingDistance:
            return String(localized: "Fills in how far you rode.")
        case .swimmingDistance:
            return String(localized: "Fills in how far you swam.")
        case .activeEnergy:
            return String(localized: "Used for your weekly summary.")
        case .restingHeartRate, .cyclingPower, .runningPower, .workoutRoute:
            return String(localized: "Not requested yet — only when a feature uses it.")
        }
    }
}
