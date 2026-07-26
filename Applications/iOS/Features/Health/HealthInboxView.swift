import SwiftUI
import EnduranceDomain

/// The Health Inbox (§E).
///
/// Every row states *why* Endurance thinks what it thinks. That is the whole
/// point: a suggestion the athlete cannot interrogate is one they must either
/// accept blindly or ignore, and neither is acceptable when the result changes
/// their training record.
struct HealthInboxView: View {
    @Environment(AppEnvironment.self) private var env
    private var health: HealthCoordinator { env.health }
    private var fmt: DisplayFormatter { DisplayFormatter(units: env.store.units) }

    @State private var choosing: HealthCoordinator.InboxItem?

    var body: some View {
        List {
            if health.inbox.isEmpty {
                Section {
                    EmptyStateView(systemImage: "tray",
                                   title: "Nothing to review",
                                   message: "Imported workouts that Endurance can’t match on its own will appear here.")
                        .accessibilityIdentifier(A11y.Health.inboxEmpty)
                }
            } else {
                ForEach(Array(health.inbox.enumerated()), id: \.element.id) { index, item in
                    Section {
                        activityRow(item, index: index)
                        evidenceRows(item)
                        actionRows(item, index: index)
                    } header: {
                        Text(confidenceHeading(item.match.confidence))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Health Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $choosing) { item in
            SessionPickerView(item: item) { workoutID in
                health.confirm(item, to: workoutID)
            }
        }
    }

    // MARK: - Rows

    private func activityRow(_ item: HealthCoordinator.InboxItem, index: Int) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            SportBadge(sport: item.summary.sport)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(item.summary.start, format: .dateTime.weekday(.abbreviated).month().day().hour().minute())
                    .font(.subheadline)
                MetricLine(parts: metrics(item.summary))
                if let source = item.summary.sourceName {
                    Text(source).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(A11y.Health.inboxRow(index))
    }

    /// The evidence behind the suggestion, in plain words.
    @ViewBuilder private func evidenceRows(_ item: HealthCoordinator.InboxItem) -> some View {
        if let suggestion = item.suggestion {
            LabeledContent("Suggested session") {
                Text(suggestion.title)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            ForEach(item.match.reasons) { reason in
                Label {
                    Text(explain(reason))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: symbol(for: reason.kind))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        } else {
            Text("No planned session looks like this one.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func actionRows(_ item: HealthCoordinator.InboxItem, index: Int) -> some View {
        if item.match.confidence == .conflict {
            Text("That session already has a completion recorded. Confirming would replace what’s there, so Endurance won’t do it automatically.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if let suggestion = item.suggestion, item.match.confidence != .conflict {
            Button {
                health.confirm(item, to: suggestion.id)
            } label: {
                Label("Confirm this match", systemImage: "checkmark.circle")
            }
            .accessibilityIdentifier(A11y.Health.confirmMatch(index))
        }

        Button {
            choosing = item
        } label: {
            Label("Choose another session", systemImage: "list.bullet")
        }
        .accessibilityIdentifier(A11y.Health.chooseOther(index))

        Button {
            health.keepAsUnplanned(item)
        } label: {
            Label("Keep as unplanned training", systemImage: "tray.and.arrow.down")
        }
        .accessibilityIdentifier(A11y.Health.keepUnplanned(index))

        Button(role: .destructive) {
            health.reject(item)
        } label: {
            Label("Not a planned session", systemImage: "xmark.circle")
        }
        .accessibilityIdentifier(A11y.Health.rejectMatch(index))
    }

    // MARK: - Copy

    private func metrics(_ summary: ExternalWorkoutSummary) -> [String] {
        var parts = [fmt.duration(minutes: summary.durationMinutes)]
        if let distance = fmt.distance(summary.distanceMeters, sport: summary.sport) {
            parts.append(distance)
        }
        if let hr = summary.averageHeartRate {
            parts.append(String(localized: "\(Int(hr)) bpm avg"))
        }
        return parts
    }

    private func confidenceHeading(_ confidence: WorkoutMatcher.Confidence) -> String {
        switch confidence {
        case .exact: return String(localized: "Matched")
        case .high: return String(localized: "Probably this session")
        case .possible: return String(localized: "Needs your decision")
        case .conflict: return String(localized: "Already has a completion")
        case .none: return String(localized: "Unmatched")
        case .duplicate: return String(localized: "Already recorded")
        }
    }

    private func explain(_ reason: WorkoutMatcher.Reason) -> String {
        let detail = reason.detail
        switch reason.kind {
        case .providerLinkExists: return String(localized: "Already linked to this session")
        case .sportMatches: return String(localized: "Same sport")
        case .sportDiffers: return String(localized: "Different sport")
        case .startTimeClose: return String(localized: "Started about when planned (\(detail ?? "")）")
        case .startTimeFar: return String(localized: "Started \(detail ?? "") from the planned time")
        case .durationClose: return String(localized: "Duration close to planned (\(detail ?? "")）")
        case .durationFar: return String(localized: "Duration \(detail ?? "") off the plan")
        case .distanceClose: return String(localized: "Distance close to planned")
        case .distanceFar: return String(localized: "Distance \(detail ?? "") off the plan")
        case .alreadyExecuted: return String(localized: "This session already has a completion")
        case .alreadyImported: return String(localized: "Already imported")
        case .outsideWindow: return String(localized: "No planned session nearby")
        }
    }

    private func symbol(for kind: WorkoutMatcher.Reason.Kind) -> String {
        switch kind {
        case .providerLinkExists, .alreadyImported: return "link"
        case .sportMatches: return "checkmark"
        case .sportDiffers: return "xmark"
        case .startTimeClose, .startTimeFar: return "clock"
        case .durationClose, .durationFar: return "timer"
        case .distanceClose, .distanceFar: return "ruler"
        case .alreadyExecuted: return "exclamationmark.triangle"
        case .outsideWindow: return "calendar.badge.exclamationmark"
        }
    }
}

/// Pick a different planned session for an imported activity (§E "choose
/// another planned workout").
private struct SessionPickerView: View {
    let item: HealthCoordinator.InboxItem
    let onPick: (UUID) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private var candidates: [ScheduledWorkout] {
        let window: TimeInterval = 3 * 24 * 60 * 60
        return env.store.allWorkouts
            .filter { abs($0.plannedStart.timeIntervalSince(item.summary.start)) <= window }
            .sorted { $0.plannedStart < $1.plannedStart }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(candidates) { workout in
                        Button {
                            onPick(workout.id)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.title)
                                Text(workout.plannedStart,
                                     format: .dateTime.weekday(.abbreviated).month().day().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("Sessions within three days of this activity.")
                }
            }
            .navigationTitle("Choose session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
