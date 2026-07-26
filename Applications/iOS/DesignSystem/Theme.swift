import SwiftUI
import UIKit
import EnduranceDomain

/// The design system. Maps the domain's semantic tokens onto system colors and
/// SF Symbols so the app follows Light/Dark/Increased-Contrast automatically and
/// never conveys meaning by color alone. Colors are restrained sport accents —
/// secondary to content, never full-screen washes.
enum Theme {

    /// Consistent spacing scale (4/8/12/16/20/24/32).
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    static func color(_ token: AccentToken) -> Color {
        switch token {
        case .swim: return .cyan
        case .bike: return .orange
        case .run: return .green
        case .strength: return .indigo
        case .recovery: return .purple
        case .race: return .accentColor
        }
    }

    static func color(for sport: Sport) -> Color { color(sport.accentToken) }

    /// Resolve a sport's SF Symbol, falling back if the preferred symbol is not
    /// available on this OS/SDK (brief §5: verify availability, provide fallback).
    static func symbol(for sport: Sport) -> String {
        availableSymbol(sport.preferredSymbolName, fallback: sport.fallbackSymbolName)
    }

    static func symbol(for status: WorkoutStatus) -> String {
        availableSymbol(status.preferredSymbolName, fallback: status.fallbackSymbolName)
    }

    static func availableSymbol(_ preferred: String, fallback: String) -> String {
        UIImage(systemName: preferred) != nil ? preferred : fallback
    }

    /// Status color — always paired with a symbol + text label elsewhere.
    static func color(for status: WorkoutStatus) -> Color {
        switch status {
        case .completed, .partiallyCompleted: return .green
        case .skipped: return .secondary
        case .rescheduled, .replaced: return .orange
        case .planned, .inProgress: return .accentColor
        }
    }
}
