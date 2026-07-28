import SwiftUI
import EnduranceDomain

/// Offers back a session that was still running when the app stopped (§G).
///
/// The three choices are deliberate. **Resume** is right when the athlete is
/// still training and the app died underneath them. **Save** is right when they
/// finished but the app never saw the end — the work happened and keeping it
/// costs nothing. **Discard** exists because a session started by accident
/// should not have to be saved to be dismissed.
///
/// What is *not* offered is doing nothing silently. A recovery record that is
/// neither resolved nor surfaced would sit there and be offered again at every
/// launch, or worse, be re-saved as a duplicate.
private struct InterruptedSessionModifier: ViewModifier {
    let env: AppEnvironment

    func body(content: Content) -> some View {
        content.alert(
            "Unfinished session",
            isPresented: .init(
                get: { env.activeWorkout.recoverable != nil },
                set: { if !$0 { } }),
            presenting: env.activeWorkout.recoverable
        ) { recovery in
            Button("Resume") {
                Task { await env.activeWorkout.recoverInterrupted(recovery) }
            }
            Button("Save it") {
                Task { await env.activeWorkout.saveInterrupted(recovery) }
            }
            Button("Discard", role: .destructive) {
                env.activeWorkout.discardInterrupted(recovery)
            }
        } message: { recovery in
            Text("\(Self.duration(recovery.accumulatedSeconds)) was recorded before \(AppConfig.productName) stopped. What would you like to do with it?")
        }
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60, s = total % 60
        return m > 0 ? "\(m) min \(s) s" : "\(s) s"
    }
}

extension View {
    func interruptedSessionPrompt(_ env: AppEnvironment) -> some View {
        modifier(InterruptedSessionModifier(env: env))
    }
}
