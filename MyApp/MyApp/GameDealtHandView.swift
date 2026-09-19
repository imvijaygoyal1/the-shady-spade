import SwiftUI

/// What the shared "look at your dealt hand" screen needs from a game.
///
/// Read-only — unlike `MultiplayerCallingState`, this screen writes nothing
/// back, so it does not need `Observable` and takes the game by value.
///
/// The two copies were 185 and 180 lines with a **zero-line** behavioural
/// diff: the only difference was where `Text("Start Bidding")` wrapped
/// (SPADE-02).
@MainActor
protocol MultiplayerDealtHand: AnyObject {
    var roundNumber: Int { get }
    var dealerIndex: Int { get }
    var isHost: Bool { get }
    var myHand: [Card] { get }
    var myHandSorted: [Card] { get }
    func playerName(_ index: Int) -> String
    func startBidding() async
}

extension OnlineGameViewModel: MultiplayerDealtHand {}
extension BluetoothGameViewModel: MultiplayerDealtHand {}

/// The between-deal-and-bidding screen for the two multiplayer modes: your
/// eight cards, what they are worth, and the host's start control.
///
/// Solo keeps `ViewingCardsView`: 75 of its 158 presentation lines differ. It
/// has no host concept — the human always starts bidding itself — and resumes
/// an async continuation rather than calling a view-model method.
struct GameDealtHandView<Game: MultiplayerDealtHand>: View {
    var game: Game
    @State private var appeared = false

    private var handPoints: Int { game.myHand.map(\.pointValue).reduce(0, +) }

    var body: some View {
        GameAdaptiveLayout(portrait: { portrait }, landscape: { landscape })
    }

    // MARK: - Portrait

    private var portrait: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Round \(game.roundNumber)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Your Hand")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.masterGold)
                Text("Dealer: \(game.playerName(game.dealerIndex))")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 56)
            .padding(.bottom, 24)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : -12)

            Spacer()

            VStack(spacing: 12) {
                handRow
                handPointsPill
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)

            Spacer()

            if game.isHost {
                startBiddingButton
                    .padding(.horizontal, 32)
            } else {
                waiting("Waiting for host to start bidding…")
                    .padding(.bottom, 8)
            }
        }
        .padding(.bottom, 54)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.1)) {
                appeared = true
            }
        }
    }

    // MARK: - Landscape

    private var landscape: some View {
        HStack(spacing: 0) {
            // Left — round context and what the hand is worth.
            VStack(spacing: 10) {
                Spacer()
                VStack(spacing: 6) {
                    Text("Round \(game.roundNumber)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Comic.textSecondary)
                    Text("Your Hand")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(Comic.yellow)
                    Text("Dealer: \(game.playerName(game.dealerIndex))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Comic.textSecondary)
                }
                handPointsPill
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Comic.containerBG)

            Rectangle()
                .fill(Comic.containerBorder)
                .frame(width: 1)

            // Right — the cards and the start control.
            VStack(spacing: 12) {
                Spacer()
                handRow
                Spacer()
                if game.isHost {
                    startBiddingButton
                        .padding(.horizontal, 32)
                        .padding(.bottom, 24)
                } else {
                    // Deliberately different wording from portrait: MED-05
                    // (2026-05-14) corrected this branch because the landscape
                    // copy is shown while everyone is still reading their hand.
                    waiting("Other players are looking at their cards…")
                        .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Comic.bg)
        }
    }

    // MARK: - Pieces

    /// Cards sized to fit, via the same helper the playing screen uses.
    ///
    /// Both copies previously hardcoded 74pt and divided the leftover space
    /// among the gaps. Eight cards need 592pt in a 361pt row, so the "gap"
    /// came out at **−33pt** and every card sat a third of the way over the
    /// one before it, clipping the point badges to `10p`. It got worse as the
    /// hand grew, which is backwards. `GameCardSizing` shrinks the cards
    /// instead (44pt at iPhone width, with a positive gap), so the badges stay
    /// whole — and this screen exists to show what the hand is worth.
    private var handRow: some View {
        GeometryReader { geo in
            let sorted = game.myHandSorted
            let available = geo.size.width - 32
            let cardW = GameCardSizing.cardWidth(available: available, count: sorted.count)
            let sp = sorted.count > 1
                ? (available - CGFloat(sorted.count) * cardW) / CGFloat(sorted.count - 1)
                : 0
            HStack(spacing: sp) {
                ForEach(sorted) { card in
                    HandCardView(card: card, width: cardW)
                }
            }
            .padding(.horizontal, 16)
            // Shrunk cards are shorter than the 106pt slot; centre them so the
            // surrounding layout does not move.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 106)
    }

    private var handPointsPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.masterGold)
            Text("\(handPoints) pts in your hand")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassmorphic(cornerRadius: 12)
    }

    private var startBiddingButton: some View {
        Button {
            HapticManager.impact(.medium)
            Task { await game.startBidding() }
        } label: {
            HStack(spacing: 8) {
                Text("Start Bidding").fontWeight(.black)
                Image(systemName: "arrow.right")
            }
            .font(.title3)
            .foregroundStyle(Comic.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
        .buttonStyle(ComicButtonStyle())
    }

    private func waiting(_ message: String) -> some View {
        VStack(spacing: 6) {
            ProgressView().tint(.masterGold)
            Text(message)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}
