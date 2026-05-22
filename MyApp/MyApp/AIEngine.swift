import Foundation

/// Shared, stateless AI logic used by OnlineGameViewModel and BluetoothGameViewModel.
/// All functions are pure (no side effects) — callers pass the game state they need.
enum AIEngine {

    // MARK: - Deck

    /// The canonical 48-card deck (12 ranks × 4 suits), computed once at load time.
    static let fullDeck: [Card] = ["A", "K", "Q", "J", "10", "9", "8", "7", "6", "5", "4", "3"]
        .flatMap { r in ["♠", "♥", "♦", "♣"].map { s in Card(rank: r, suit: s) } }

    // MARK: - Bid History

    /// Deduplicate bid history so each player appears once with their LATEST amount.
    /// Preserves first-appearance order (important for display).
    static func latestBidPerPlayer(
        _ history: [(playerIndex: Int, amount: Int)]
    ) -> [(playerIndex: Int, amount: Int)] {
        var latest: [Int: Int] = [:]
        for e in history { latest[e.playerIndex] = e.amount }
        var seen = Set<Int>()
        return history.compactMap { e in
            guard seen.insert(e.playerIndex).inserted else { return nil }
            return (playerIndex: e.playerIndex, amount: latest[e.playerIndex] ?? e.amount)
        }
    }

    // MARK: - Trick Winner

    /// Returns the playerIndex of the trick winner.
    /// Trump beats any non-trump; within the same suit, highest rank wins.
    static func trickWinnerIndex(
        trick: [(playerIndex: Int, card: Card)],
        trumpSuit: TrumpSuit
    ) -> Int {
        let ledSuit  = trick[0].card.suit
        let trumpRaw = trumpSuit.rawValue
        let trumpPlays = trick.filter { $0.card.suit == trumpRaw }
        if !trumpPlays.isEmpty {
            guard let winner = trumpPlays.max(by: {
                (Card.rankOrder[$0.card.rank] ?? 0) < (Card.rankOrder[$1.card.rank] ?? 0)
            }) else { return trick[0].playerIndex }
            return winner.playerIndex
        }
        let ledPlays = trick.filter { $0.card.suit == ledSuit }
        guard let winner = ledPlays.max(by: {
            (Card.rankOrder[$0.card.rank] ?? 0) < (Card.rankOrder[$1.card.rank] ?? 0)
        }) else { return trick[0].playerIndex }
        return winner.playerIndex
    }

    // MARK: - AI Bidding

    /// Compute an AI bid amount for `seat`.
    /// Returns 0 to indicate a pass (only valid when `canPass` is true).
    static func computeBid(
        seat: Int,
        hand: [Card],
        dealerIndex: Int,
        highBid: Int,
        canPass: Bool
    ) -> Int {
        let myPoints = hand.map(\.pointValue).reduce(0, +)
        let myIds    = Set(hand.map(\.id))
        let topExternal = fullDeck
            .filter { !myIds.contains($0.id) }
            .sorted { lhs, rhs in
                lhs.pointValue != rhs.pointValue
                    ? lhs.pointValue > rhs.pointValue
                    : (Card.rankOrder[lhs.rank] ?? 0) > (Card.rankOrder[rhs.rank] ?? 0)
            }
        let call1Pts = topExternal.first?.pointValue ?? 0
        let call2Pts = topExternal.dropFirst().first?.pointValue ?? 0

        // Phase 1a — Position-aware partner bonus
        let position = (seat - dealerIndex + 6) % 6
        let bonusFraction: Double
        switch position {
        case 1, 2: bonusFraction = 0.25
        case 3:    bonusFraction = 0.33
        case 4, 5: bonusFraction = 0.42
        default:   bonusFraction = 0.38   // dealer
        }
        let remaining    = max(0, 250 - myPoints - call1Pts - call2Pts)
        let partnerBonus = Int(Double(remaining) * bonusFraction)

        // Phase 1b — Suit-clustering bonus (2+ high cards in same suit)
        var clusterBonus = 0
        for suit in TrumpSuit.allCases {
            let suitCards = hand.filter { $0.suit == suit.rawValue }
            guard suitCards.count >= 2 else { continue }
            let sortedRanks = suitCards.compactMap { Card.rankOrder[$0.rank] }.sorted(by: >)
            if let top = sortedRanks.first, let second = sortedRanks.dropFirst().first,
               top >= 10 && second >= 10 {
                clusterBonus += suitCards.count * 4
            }
        }

        // Phase 1c — Shortness penalty (3+ thin suits)
        let thinSuits = TrumpSuit.allCases.filter { suit in
            hand.filter { $0.suit == suit.rawValue }.count <= 1
        }.count
        let shortnessPenalty = max(0, thinSuits - 2) * 8

        let estimated = myPoints + call1Pts + call2Pts + partnerBonus + clusterBonus - shortnessPenalty
        let minBid    = max(130, highBid + 5)
        if !canPass {
            let rounded = (max(estimated, minBid) / 5) * 5
            return min(max(rounded, minBid), 250)
        }
        guard estimated >= minBid else { return 0 }
        let rounded = (estimated / 5) * 5
        return min(max(rounded, minBid), 250)
    }

    // MARK: - AI Calling

    /// Compute the best trump suit and two called card IDs for the bidder's hand.
    static func computeCalling(hand: [Card]) -> (trump: TrumpSuit, c1: String, c2: String) {
        // Phase 2a — Tier-based trump selection
        func trumpTier(_ suit: TrumpSuit) -> Int {
            let topRank = hand.filter { $0.suit == suit.rawValue }
                .compactMap { Card.rankOrder[$0.rank] }.max() ?? 0
            if topRank >= 12 { return 3 }
            if topRank >= 11 { return 2 }
            if topRank >= 10 { return 1 }
            return 0
        }
        let suitRankings = TrumpSuit.allCases.map { suit -> (TrumpSuit, Int) in
            let pts   = hand.filter { $0.suit == suit.rawValue }.map(\.pointValue).reduce(0, +)
            let count = hand.filter { $0.suit == suit.rawValue }.count
            return (suit, pts + trumpTier(suit) * 15 + count * 2)
        }
        let trump = suitRankings.max(by: { $0.1 < $1.1 })?.0 ?? .spades

        // Phase 2b — Void-feeding called cards, diversified across suits
        let handIds    = Set(hand.map(\.id))
        let candidates = fullDeck
            .filter { !handIds.contains($0.id) }
            .sorted { lhs, rhs in
                lhs.pointValue != rhs.pointValue
                    ? lhs.pointValue > rhs.pointValue
                    : (Card.rankOrder[lhs.rank] ?? 0) > (Card.rankOrder[rhs.rank] ?? 0)
            }
        let voidSuits  = TrumpSuit.allCases.filter { suit in
            suit != trump && hand.filter { $0.suit == suit.rawValue }.isEmpty
        }
        let shortSuits = TrumpSuit.allCases.filter { suit in
            suit != trump && hand.filter { $0.suit == suit.rawValue }.count == 1
        }
        var ordered: [Card] = []
        for suit in voidSuits {
            if let top = candidates.first(where: { $0.suit == suit.rawValue }) { ordered.append(top) }
        }
        let coveredSuits = Set(ordered.map(\.suit))
        for suit in shortSuits where !coveredSuits.contains(suit.rawValue) {
            if let top = candidates.first(where: { $0.suit == suit.rawValue }) { ordered.append(top) }
        }
        let chosenIds = Set(ordered.map(\.id))
        ordered += candidates.filter { !chosenIds.contains($0.id) }

        let c1Card = ordered.first
        let c2Card = ordered.first(where: { $0.suit != c1Card?.suit }) ?? ordered.dropFirst().first
        let c1 = c1Card?.id ?? "A♥"
        let c2 = c2Card?.id ?? (ordered.count > 1 ? ordered[1].id : "K♥")
        return (trump: trump, c1: c1, c2: c2)
    }

    // MARK: - AI Card Play

    /// Compute the best card ID to play for `seat`.
    /// Returns nil if the hand is empty (caller should retry after a delay).
    static func computeCard(
        seat: Int,
        hand: [Card],
        offenseSet: Set<Int>,
        highBidderIndex: Int,
        trumpSuit: TrumpSuit,
        currentTrick: [(playerIndex: Int, card: Card)],
        completedTricks: [[(playerIndex: Int, card: Card)]],
        wonPointsPerPlayer: [Int],
        highBid: Int,
        trickNumber: Int
    ) -> String? {
        guard !hand.isEmpty else { return nil }

        let isOffense = offenseSet.contains(seat)
        let isBidder  = seat == highBidderIndex
        let trumpRaw  = trumpSuit.rawValue

        func rankScore(_ c: Card) -> Int  { Card.rankOrder[c.rank] ?? 0 }
        func valueScore(_ c: Card) -> Int { c.pointValue * 100 + rankScore(c) }

        // Phase 3 — Deficit tracking
        let offensePts = offenseSet.map { wonPointsPerPlayer[$0] }.reduce(0, +)
        let totalPts   = wonPointsPerPlayer.reduce(0, +)
        let remaining  = 250 - totalPts
        let shortfall  = max(0, highBid - offensePts)
        let isUrgent   = isOffense && remaining > 0 && shortfall * 10 > remaining * 6

        // Phase 4 — Void memory from completed tricks
        var knownVoids: [Int: Set<String>] = [:]
        for trick in completedTricks {
            guard let ledSuit = trick.first?.card.suit else { continue }
            for entry in trick where entry.card.suit != ledSuit {
                knownVoids[entry.playerIndex, default: []].insert(ledSuit)
            }
        }
        let opponentIndices = (0..<6).filter {
            isOffense ? !offenseSet.contains($0) : offenseSet.contains($0)
        }

        // ── LEADING ──────────────────────────────────────────────────────────
        if currentTrick.isEmpty {
            let nonTrump = hand.filter { $0.suit != trumpRaw }
            if isBidder {
                let bidSecured  = offensePts >= highBid
                let trumpCards  = hand.filter { $0.suit == trumpRaw }
                if !bidSecured || trickNumber < 3 {
                    if let highTrump = trumpCards.max(by: { rankScore($0) < rankScore($1) }),
                       rankScore(highTrump) >= (Card.rankOrder["Q"] ?? 0) {
                        return highTrump.id
                    }
                }
            }
            if isUrgent, let best = nonTrump.max(by: { valueScore($0) < valueScore($1) }) { return best.id }
            let scored = nonTrump.map { card -> (Card, Int) in
                let voidCount = opponentIndices.filter { knownVoids[$0]?.contains(card.suit) == true }.count
                return (card, rankScore(card) + card.pointValue - voidCount * 4)
            }
            if let best = scored.max(by: { $0.1 < $1.1 })?.0 { return best.id }
            if let best = nonTrump.max(by: { rankScore($0) < rankScore($1) }) { return best.id }
            return (hand.min(by: { rankScore($0) < rankScore($1) }) ?? hand[0]).id
        }

        // ── FOLLOWING ────────────────────────────────────────────────────────
        let ledSuit  = currentTrick[0].card.suit
        let sameSuit = hand.filter { $0.suit == ledSuit }

        guard let winnerEntry = currentTrick.max(by: { (a, b) in
            let aTrump = a.card.suit == trumpRaw
            let bTrump = b.card.suit == trumpRaw
            if aTrump != bTrump { return bTrump }
            if a.card.suit == b.card.suit { return rankScore(a.card) < rankScore(b.card) }
            return true
        }) else { return hand[0].id }

        let winner          = winnerEntry
        let winnerIsOffense = offenseSet.contains(winner.playerIndex)
        let teammateWinning = isOffense ? winnerIsOffense : !winnerIsOffense

        if !sameSuit.isEmpty {
            if teammateWinning {
                return (sameSuit.max(by: { valueScore($0) < valueScore($1) }) ?? sameSuit[0]).id
            }
            if winner.card.suit == ledSuit {
                let canBeat = sameSuit.filter { rankScore($0) > rankScore(winner.card) }
                if let best = canBeat.max(by: { rankScore($0) < rankScore($1) }) { return best.id }
            }
            return (sameSuit.min(by: { valueScore($0) < valueScore($1) }) ?? sameSuit[0]).id
        }

        // ── CAN'T FOLLOW ──────────────────────────────────────────────────────
        if teammateWinning {
            let nonTrump = hand.filter { $0.suit != trumpRaw }
            if let best = nonTrump.max(by: { valueScore($0) < valueScore($1) }) { return best.id }
        }
        // Only trump in if points are at stake or offense is urgent
        let trickPoints = currentTrick.map(\.card.pointValue).reduce(0, +)
        let trumpCards  = hand.filter { $0.suit == trumpRaw }
        if !trumpCards.isEmpty && (trickPoints > 0 || isUrgent) {
            return (trumpCards.min(by: { rankScore($0) < rankScore($1) }) ?? trumpCards[0]).id
        }
        let nonTrump = hand.filter { $0.suit != trumpRaw }
        if let discard = nonTrump.min(by: { valueScore($0) < valueScore($1) }) { return discard.id }
        return (trumpCards.min(by: { rankScore($0) < rankScore($1) }) ?? hand[0]).id
    }
}
