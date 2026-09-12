import SwiftUI

extension View {
    func turnNudge(
        isMyTurn: Bool,
        playSound: Bool = false
    ) -> some View {
        self.modifier(TurnNudgeModifier(
            isMyTurn: isMyTurn,
            playSound: playSound
        ))
    }
}

private struct TurnNudgeModifier: ViewModifier {
    let isMyTurn: Bool
    let playSound: Bool
    @State private var lastFiredState = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isMyTurn) { _, newValue in
                if newValue && !lastFiredState {
                    TurnNudgeEngine.fire(
                        playSound: playSound)
                    lastFiredState = true
                } else if !newValue {
                    lastFiredState = false
                }
            }
    }
}

enum TurnNudgeEngine {
    private static let isEnabled = true
    private static var lastFireDate = Date.distantPast
    private static let minimumFireInterval: TimeInterval = 1.25
    private static var delayedImpactTask: Task<Void, Never>?

    @MainActor
    static func fire(playSound: Bool = true) {
        guard isEnabled else { return }
        let now = Date()
        guard now.timeIntervalSince(lastFireDate) >= minimumFireInterval else { return }
        lastFireDate = now

        // Beat 1 — soft
        HapticManager.impact(.soft)

        // Beat 2 — medium, delayed. Keep the delay cancellable so a rapid turn change
        // cannot leave a stale haptic queued after the originating UI is gone.
        delayedImpactTask?.cancel()
        delayedImpactTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                HapticManager.impact(.medium)
            } catch {
                // Cancellation is expected when a newer turn notification supersedes this one.
            }
        }
    }
}
