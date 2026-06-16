import SwiftUI

struct LeaderboardConsentSheet: View {
    var onAllow: () -> Void
    var onDeny: () -> Void
    var disableInteractiveDismiss: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var choiceMade = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(ThemeManager.shared.colours.accentColor)
                    .padding(.top, 32)

                Text("Share Scores to Global Leaderboard?")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.textPrimary)

                Text("If you allow, The Shady Spade uploads your chosen player names, avatars, game mode, bids, scores, and round result to our Firebase server so your stats can appear on the global leaderboard. If you do not allow, you can still play and your scores will not be uploaded.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Comic.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                Link("Privacy Policy", destination: URL(string: "https://shadyspade.vijaygoyal.org/privacy")!)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(ThemeManager.shared.colours.accentColor)
            }
            .padding(.horizontal, 28)

            Spacer().frame(height: 32)

            VStack(spacing: 12) {
                Button("Allow Score Uploads") {
                    choiceMade = true
                    LeaderboardConsentManager.shared.grant()
                    dismiss()
                    onAllow()
                }
                .font(.system(size: 17, weight: .black, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .buttonStyle(ComicButtonStyle(
                    bg: Comic.yellow,
                    fg: Comic.black,
                    borderColor: Comic.black
                ))

                Button("Play Without Uploading Scores") {
                    choiceMade = true
                    LeaderboardConsentManager.shared.deny()
                    dismiss()
                    onDeny()
                }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .buttonStyle(ComicButtonStyle(
                    bg: Comic.containerBG,
                    fg: Comic.textSecondary,
                    borderColor: Comic.containerBorder
                ))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
        }
        .background(Comic.bg)
        .interactiveDismissDisabled(disableInteractiveDismiss)
        .onDisappear {
            if !choiceMade {
                LeaderboardConsentManager.shared.deny()
                onDeny()
            }
        }
    }
}
