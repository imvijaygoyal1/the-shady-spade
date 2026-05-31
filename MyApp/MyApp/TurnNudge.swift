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

    @MainActor
    static func fire(playSound: Bool = true) {
        guard isEnabled else { return }
        let now = Date()
        guard now.timeIntervalSince(lastFireDate) >= minimumFireInterval else { return }
        lastFireDate = now

        // Beat 1 — soft
        HapticManager.impact(.soft)

        // Beat 2 — medium, delayed
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.14) {
            HapticManager.impact(.medium)
        }
    }
}
