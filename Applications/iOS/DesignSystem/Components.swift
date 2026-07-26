import SwiftUI
import EnduranceDomain

/// Small reusable views. Every one pairs color with a symbol + text so meaning is
/// never carried by color alone (Differentiate Without Color).

struct SportBadge: View {
    let sport: Sport
    var body: some View {
        Image(systemName: Theme.symbol(for: sport))
            .foregroundStyle(Theme.color(for: sport))
            .imageScale(.large)
            .accessibilityLabel(Text(sport.englishName))
    }
}

/// Status shown as symbol + label (never color-only).
struct StatusChip: View {
    let status: WorkoutStatus
    var body: some View {
        Label {
            Text(status.englishName)
        } icon: {
            Image(systemName: Theme.symbol(for: status))
        }
        .font(.caption)
        .foregroundStyle(Theme.color(for: status))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Status: \(status.englishName)"))
    }
}

/// A compact metric pill (duration / distance / intensity).
struct MetricPill: View {
    let systemImage: String
    let text: String
    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, Theme.Space.xs)
            .background(.quaternary, in: Capsule())
    }
}

/// A calm section header used inside grouped content.
struct SectionLabel: View {
    let title: String
    let systemImage: String
    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline).bold()
            .foregroundStyle(.secondary)
    }
}

/// A native-feeling empty state with an optional recovery action.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent)
            }
        }
    }
}
