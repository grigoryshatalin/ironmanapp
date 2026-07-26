import SwiftUI
import UIKit
import EnduranceDomain

/// Small reusable views. Every one pairs color with a symbol + text so meaning is
/// never carried by color alone (Differentiate Without Color).

// MARK: - Sport symbol

/// The single way a sport is ever drawn.
///
/// Standardized deliberately (§14): one scaled frame, one rendering mode, one
/// weight, one alignment, and always an accessibility label.
/// `Theme.symbol(for:)` resolves the SF Symbol and falls back when the preferred
/// name is unavailable on the running OS, so this never renders a blank box.
struct SportBadge: View {
    let sport: Sport
    var size: SymbolSize = .row

    enum SymbolSize {
        case row, detail
        var width: CGFloat { self == .row ? 30 : 36 }
        var style: UIFont.TextStyle { self == .row ? .body : .title3 }
    }

    /// Scales the frame with Dynamic Type so the glyph keeps pace with its text.
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        Image(systemName: Theme.symbol(for: sport))
            .font(.system(size: UIFont.preferredFont(forTextStyle: size.style).pointSize,
                          weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Theme.color(for: sport))
            .frame(width: size.width * scale, alignment: .center)
            .accessibilityLabel(Text(sport.localizedName))
    }
}

// MARK: - Status

/// Status shown as symbol + label (never color-only).
struct StatusChip: View {
    let status: WorkoutStatus

    var body: some View {
        Label {
            Text(status.localizedName)
        } icon: {
            Image(systemName: Theme.symbol(for: status))
                .symbolRenderingMode(.monochrome)
        }
        .font(.caption)
        .foregroundStyle(Theme.color(for: status))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Status: \(status.localizedName)"))
    }
}

// MARK: - Metadata

/// One metadata line — "1 hr 15 min · 29 mi · Zone 3".
///
/// This replaces the previous row of capsule "pills", which truncated on compact
/// widths and at large Dynamic Type, and could silently drop the distance or
/// intensity. Duration, distance and intensity are safety-relevant, so the line
/// wraps rather than truncating (§12).
struct MetricLine: View {
    let parts: [String]
    /// Spoken form, when the visual separator would read poorly.
    var spoken: [String]?

    private var joined: String { parts.filter { !$0.isEmpty }.joined(separator: " · ") }

    var body: some View {
        Text(joined)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(Text((spoken ?? parts).filter { !$0.isEmpty }.joined(separator: ", ")))
    }
}

/// A calm section header used inside grouped content.
struct SectionLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A native-feeling empty state with an optional recovery action.
struct EmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
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

// MARK: - Haptics

/// Meaningful confirmation only — completing, moving, exporting (§5, §16).
///
/// SwiftUI's `sensoryFeedback` already honours the system's haptic settings, so
/// there is nothing to gate by hand; restraint comes from never adding
/// decorative feedback in the first place.
enum Haptic {
    case completed
    case rescheduled
    case exported
    case failed

    var feedback: SensoryFeedback {
        switch self {
        case .completed: return .success
        case .rescheduled: return .impact(weight: .light)
        case .exported: return .success
        case .failed: return .error
        }
    }
}

extension View {
    /// Fire a haptic when `trigger` changes.
    func haptic<T: Equatable>(_ haptic: Haptic, trigger: T) -> some View {
        sensoryFeedback(haptic.feedback, trigger: trigger)
    }
}
