import SwiftUI
import AVFoundation

extension View {
    func turnNudge(
        isMyTurn: Bool,
        playSound: Bool = true
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
    private static var audioPlayer: AVAudioPlayer?

    static func fire(playSound: Bool = true) {
        // Beat 1 — soft
        let soft = UIImpactFeedbackGenerator(
            style: .soft)
        soft.prepare()
        soft.impactOccurred(intensity: 0.6)

        // Beat 2 — medium, delayed
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.14) {
            let medium = UIImpactFeedbackGenerator(
                style: .medium)
            medium.prepare()
            medium.impactOccurred(intensity: 0.85)
        }

        if playSound {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.18) {
                playTurnSound()
            }
        }
    }

    private static func playTurnSound() {
        // Configure audio session to play even
        // when silent switch is ON
        do {
            try AVAudioSession.sharedInstance()
                .setCategory(
                    .ambient,
                    mode: .default,
                    options: [.mixWithOthers]
                )
            try AVAudioSession.sharedInstance()
                .setActive(true)
        } catch {
            print("TurnNudge: audio session " +
                "error — \(error)")
        }

        // Use a built-in system sound file
        // that exists on all iOS devices
        let soundURL = URL(fileURLWithPath:
            "/System/Library/Audio/UISounds/" +
            "Tock.caf")

        do {
            audioPlayer = try AVAudioPlayer(
                contentsOf: soundURL)
            audioPlayer?.volume = 0.5
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            // Fallback to AudioServices
            // if file path fails
            AudioServicesPlaySystemSound(1104)
        }
    }
}
