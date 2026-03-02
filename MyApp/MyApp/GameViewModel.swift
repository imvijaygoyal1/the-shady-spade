import SwiftUI
import SwiftData
import Observation

// MARK: - Game View Model

@Observable
final class GameViewModel {

    // MARK: Persisted data
    var rounds: [Round] = []

    // MARK: Player names (UserDefaults)
    var playerNames: [String] = (1...6).map { "Player \($0)" }

    // MARK: Player avatars (UserDefaults)
    var playerAvatars: [String] = Array(repeating: "person.fill", count: 6)

    static let avatarCatalog: [(symbol: String, color: Color)] = [
        ("suit.spade.fill", .white),
        ("suit.heart.fill", .defenseRose),
        ("suit.diamond.fill", .offenseBlue),
        ("suit.club.fill", .green),
        ("crown.fill", .masterGold),
        ("bolt.fill", .yellow),
        ("flame.fill", .orange),
        ("star.fill", .cyan),
        ("moon.fill", .indigo),
        ("shield.fill", Color(white: 0.6)),
        ("tornado", .teal),
        ("snowflake", Color(red: 0.5, green: 0.85, blue: 1.0))
    ]

    func avatarColor(for index: Int) -> Color {
        GameViewModel.avatarCatalog.first { $0.symbol == playerAvatars[index] }?.color ?? .offenseBlue
    }

    // MARK: Add-Round form state
    var dealerIndex:   Int        = 0
    var bidderIndex:   Int        = 0
    var bidAmount:     Double     = 130
    var trumpSuit:     TrumpSuit  = .spades
    var callCard1Rank: String     = "A"
    var callCard1Suit: String     = "♠"
    var callCard2Rank: String     = "K"
    var callCard2Suit: String     = "♠"
    var partner1Index: Int?       = nil
    var partner2Index: Int?       = nil
    var offensePoints: Int        = 0
    var defensePoints: Int        = 0

    // MARK: Navigation
    var showingAddRound:     Bool = false
    var showingGameTable:    Bool = false
    var showingAuth:         Bool = false
    var showingOnlineSession: Bool = false

    // MARK: Online mode
    var onlineSessionVM: OnlineSessionViewModel? = nil
    var isOnlineMode: Bool { onlineSessionVM != nil }

    // MARK: Private
    private var context: ModelContext?

    // MARK: - Setup

    func setup(with context: ModelContext) {
        self.context = context
        loadPlayerNames()
        loadPlayerAvatars()
        fetchRounds()
    }

    // MARK: - Computed card strings

    var callCard1: String { callCard1Rank + callCard1Suit }
    var callCard2: String { callCard2Rank + callCard2Suit }

    // MARK: - Validation

    var callCardsValid: Bool {
        !callCard1Rank.isEmpty && !callCard2Rank.isEmpty && callCard1 != callCard2
    }

    var partnersValid: Bool {
        guard let p1 = partner1Index, let p2 = partner2Index else { return false }
        return p1 != bidderIndex && p2 != bidderIndex && p1 != p2
    }

    var totalPointsEntered: Int { offensePoints + defensePoints }

    var isFormValid: Bool {
        callCardsValid && partnersValid &&
        offensePoints >= 0 && defensePoints >= 0 &&
        totalPointsEntered <= 250
    }

    // MARK: - Per-player scoring

    func totalScore(for playerIndex: Int) -> Int {
        rounds.reduce(0) { $0 + $1.score(for: playerIndex) }
    }

    var rankedPlayers: [(index: Int, score: Int)] {
        (0..<6)
            .map { (index: $0, score: totalScore(for: $0)) }
            .sorted { $0.score > $1.score }
    }

    var nextRoundNumber: Int { (rounds.map(\.roundNumber).max() ?? 0) + 1 }

    // MARK: - CRUD

    func addRound() {
        guard isFormValid,
              let p1 = partner1Index,
              let p2 = partner2Index else { return }

        let round = Round(
            roundNumber:          nextRoundNumber,
            dealerIndex:          dealerIndex,
            bidderIndex:          bidderIndex,
            bidAmount:            Int(bidAmount),
            trumpSuit:            trumpSuit,
            callCard1:            callCard1,
            callCard2:            callCard2,
            partner1Index:        p1,
            partner2Index:        p2,
            offensePointsCaught:  offensePoints,
            defensePointsCaught:  defensePoints
        )

        if let osvm = onlineSessionVM {
            // Online mode: write to Firestore only; listener will sync back
            Task { await osvm.addRound(OnlineRound(from: round)) }
        } else {
            // Offline mode: write to SwiftData
            guard let context else { return }
            context.insert(round)
            try? context.save()
            fetchRounds()
        }

        if round.isSet { HapticManager.error() } else { HapticManager.success() }
        advanceDealer()
        resetFormFields()
        showingAddRound = false
    }

    func loadSampleData() {
        guard !isOnlineMode, let context else { return }
        // Clear existing
        rounds.forEach { context.delete($0) }
        try? context.save()

        let samples: [(dealer: Int, bidder: Int, bid: Int, trump: TrumpSuit,
                        c1: String, c2: String, p1: Int, p2: Int, off: Int, def: Int)] = [
            (0, 0, 150, .spades,   "A♥", "K♦", 2, 4, 180, 70),
            (1, 1, 170, .hearts,   "K♠", "Q♥", 3, 5, 160, 90),
            (2, 2, 140, .diamonds, "A♠", "J♥", 0, 4, 200, 50),
            (3, 3, 160, .clubs,    "Q♠", "10♥", 1, 5, 155, 95),
            (4, 4, 130, .spades,   "K♥", "A♦", 1, 3, 145, 105),
            (5, 0, 180, .hearts,   "A♣", "K♠", 2, 3, 190, 60),
        ]

        for (i, s) in samples.enumerated() {
            let r = Round(roundNumber: i + 1, dealerIndex: s.dealer, bidderIndex: s.bidder,
                          bidAmount: s.bid, trumpSuit: s.trump,
                          callCard1: s.c1, callCard2: s.c2,
                          partner1Index: s.p1, partner2Index: s.p2,
                          offensePointsCaught: s.off, defensePointsCaught: s.def)
            context.insert(r)
        }
        try? context.save()
        fetchRounds()
    }

    func deleteRound(_ round: Round) {
        guard !isOnlineMode else { return }
        guard let context else { return }
        context.delete(round)
        try? context.save()
        fetchRounds()
    }

    // MARK: - Online Mode

    func enterOnlineMode(_ sessionVM: OnlineSessionViewModel) {
        onlineSessionVM = sessionVM
        // Sync player names from session slots so all devices see the same names
        for slot in sessionVM.playerSlots where slot.joined && slot.slotIndex < 6 {
            playerNames[slot.slotIndex] = slot.name
        }
        syncOnlineRounds(sessionVM.rounds)
        sessionVM.onSessionUpdated = { [weak self] in
            guard let self, let osvm = self.onlineSessionVM else { return }
            DispatchQueue.main.async {
                for slot in osvm.playerSlots where slot.joined && slot.slotIndex < 6 {
                    self.playerNames[slot.slotIndex] = slot.name
                }
                self.syncOnlineRounds(osvm.rounds)
            }
        }
    }

    func exitOnlineMode() {
        onlineSessionVM?.onSessionUpdated = nil
        onlineSessionVM = nil
        fetchRounds()
    }

    func syncOnlineRounds(_ onlineRounds: [OnlineRound]) {
        rounds = onlineRounds
            .sorted { $0.roundNumber > $1.roundNumber }   // newest first, matches offline sort
            .map { or in
                Round(
                    roundNumber:         or.roundNumber,
                    dealerIndex:         or.dealerIndex,
                    bidderIndex:         or.bidderIndex,
                    bidAmount:           or.bidAmount,
                    trumpSuit:           TrumpSuit(rawValue: or.trumpSuit) ?? .spades,
                    callCard1:           or.callCard1,
                    callCard2:           or.callCard2,
                    partner1Index:       or.partner1Index,
                    partner2Index:       or.partner2Index,
                    offensePointsCaught: or.offensePointsCaught,
                    defensePointsCaught: or.defensePointsCaught
                )
            }
    }

    // MARK: - Point helpers

    func adjustPoints(offense: Bool, delta: Int) {
        HapticManager.impact(.light)
        if offense {
            offensePoints = max(0, min(250, offensePoints + delta))
        } else {
            defensePoints = max(0, min(250, defensePoints + delta))
        }
    }

    // MARK: - Partner toggle (called from form UI)

    func togglePartner(_ idx: Int) {
        guard idx != bidderIndex else { return }
        if partner1Index == idx {
            partner1Index = nil
        } else if partner2Index == idx {
            partner2Index = nil
        } else if partner1Index == nil {
            partner1Index = idx
        } else if partner2Index == nil {
            partner2Index = idx
        } else {
            // Both slots full — replace partner2
            partner2Index = idx
        }
    }

    func isPartner(_ idx: Int) -> Bool {
        partner1Index == idx || partner2Index == idx
    }

    // MARK: - Player Names

    private func loadPlayerNames() {
        playerNames = (0..<6).map {
            UserDefaults.standard.string(forKey: "playerName_\($0)") ?? "Player \($0 + 1)"
        }
    }

    private func loadPlayerAvatars() {
        playerAvatars = (0..<6).map {
            UserDefaults.standard.string(forKey: "playerAvatar_\($0)") ?? "person.fill"
        }
    }

    func updatePlayerAvatar(_ symbol: String, at index: Int) {
        playerAvatars[index] = symbol
        UserDefaults.standard.set(symbol, forKey: "playerAvatar_\(index)")
    }

    func updatePlayerName(_ name: String, at index: Int) {
        let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(30))
        let resolved = trimmed.isEmpty ? "Player \(index + 1)" : trimmed
        playerNames[index] = resolved
        UserDefaults.standard.set(resolved, forKey: "playerName_\(index)")
    }

    // MARK: - Private helpers

    private func fetchRounds() {
        guard let context else { return }
        let descriptor = FetchDescriptor<Round>(
            sortBy: [SortDescriptor(\.roundNumber, order: .reverse)]
        )
        rounds = (try? context.fetch(descriptor)) ?? []
    }

    private func advanceDealer() { dealerIndex = (dealerIndex + 1) % 6 }

    private func resetFormFields() {
        let others = (0..<6).filter { $0 != bidderIndex }
        bidAmount     = 130
        trumpSuit     = .spades
        callCard1Rank = "A"
        callCard1Suit = "♠"
        callCard2Rank = "K"
        callCard2Suit = "♠"
        partner1Index = nil
        partner2Index = nil
        offensePoints = 0
        defensePoints = 0
        _ = others // suppress warning
    }
}
