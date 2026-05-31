import Foundation

/// Shared, stateless AI logic used by Solo, Online, and Bluetooth game modes.
/// All functions are pure (no side effects) — callers pass the game state they need.
enum AIEngine {

    // MARK: - Deck

    /// The canonical 48-card deck (12 ranks × 4 suits), computed once at load time.
    static let fullDeck: [Card] = ["A", "K", "Q", "J", "10", "9", "8", "7", "6", "5", "4", "3"]
        .flatMap { r in ["♠", "♥", "♦", "♣"].map { s in Card(rank: r, suit: s) } }

    // MARK: - Bot Personality

    enum BotPersonality: String, CaseIterable {
        case conservative
        case aggressive
        case pointFeeder
        case trumpController
        case riskTaker

        static func forSeat(_ seat: Int) -> BotPersonality {
            let styles: [BotPersonality] = [.conservative, .aggressive, .pointFeeder, .trumpController, .riskTaker]
            return styles[abs(seat) % styles.count]
        }

        var bidMultiplier: Double {
            switch self {
            case .conservative:     return 0.92
            case .aggressive:       return 1.08
            case .pointFeeder:      return 1.00
            case .trumpController:  return 1.03
            case .riskTaker:        return 1.12
            }
        }

        var bidOffset: Int {
            switch self {
            case .conservative:     return -5
            case .aggressive:       return 5
            case .pointFeeder:      return 0
            case .trumpController:  return 5
            case .riskTaker:        return 10
            }
        }

        var trumpLeadFloor: Int {
            switch self {
            case .conservative:     return Card.rankOrder["A"] ?? 12
            case .aggressive:       return Card.rankOrder["K"] ?? 11
            case .pointFeeder:      return Card.rankOrder["A"] ?? 12
            case .trumpController:  return Card.rankOrder["Q"] ?? 10
            case .riskTaker:        return Card.rankOrder["J"] ?? 9
            }
        }

        var trumpInPointThreshold: Int {
            switch self {
            case .conservative:     return 25
            case .aggressive:       return 10
            case .pointFeeder:      return 20
            case .trumpController:  return 5
            case .riskTaker:        return 0
            }
        }

        var unsafeFeedTolerance: Int {
            switch self {
            case .conservative:     return 0
            case .aggressive:       return 1
            case .pointFeeder:      return 2
            case .trumpController:  return 1
            case .riskTaker:        return 3
            }
        }

        var leadTrumpBias: Int {
            switch self {
            case .conservative:     return -8
            case .aggressive:       return 6
            case .pointFeeder:      return -4
            case .trumpController:  return 18
            case .riskTaker:        return 10
            }
        }

        var pointFeedBias: Int {
            switch self {
            case .conservative:     return -4
            case .aggressive:       return 3
            case .pointFeeder:      return 12
            case .trumpController:  return 0
            case .riskTaker:        return 6
            }
        }
    }

    private struct Urgency {
        let offense: Bool
        let defense: Bool
        let offensePoints: Int
        let defensePoints: Int
        let remainingPoints: Int
        let tricksRemaining: Int

        var eitherSide: Bool { offense || defense }
    }

    private enum PartnerRevealIntent {
        case stayHidden
        case revealToWin
        case revealToFeed
        case revealToCoordinate

        var shouldReveal: Bool {
            switch self {
            case .stayHidden: return false
            case .revealToWin, .revealToFeed, .revealToCoordinate: return true
            }
        }
    }

    private struct TeamRead {
        let suspectedOffense: Set<Int>
        let suspicionScores: [Int: Int]
    }

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
        canPass: Bool,
        personality: BotPersonality? = nil
    ) -> Int {
        let style = personality ?? BotPersonality.forSeat(seat)
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

        let rawEstimate = myPoints + call1Pts + call2Pts + partnerBonus + clusterBonus - shortnessPenalty
        let estimated = Int(Double(rawEstimate) * style.bidMultiplier) + style.bidOffset
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
    static func computeCalling(
        hand: [Card],
        personality: BotPersonality? = nil
    ) -> (trump: TrumpSuit, c1: String, c2: String) {
        let style = personality ?? .trumpController

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
            let controlBonus = style == .trumpController ? count * 4 : 0
            let riskBonus = style == .riskTaker && count >= 3 ? 8 : 0
            return (suit, pts + trumpTier(suit) * 15 + count * 2 + controlBonus + riskBonus)
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

    // MARK: - Partner Visibility

    static func revealedPartnerIndices(
        calledCardIds: Set<String>,
        currentTrick: [(playerIndex: Int, card: Card)],
        completedTricks: [[(playerIndex: Int, card: Card)]]
    ) -> Set<Int> {
        guard !calledCardIds.isEmpty else { return [] }
        let playedEntries = completedTricks.flatMap { $0 } + currentTrick
        return Set(playedEntries.compactMap { entry in
            calledCardIds.contains(entry.card.id) ? entry.playerIndex : nil
        })
    }

    // MARK: - AI Card Play

    /// Compute the best card ID to play for `seat`.
    /// Returns nil if the hand is empty (caller should retry after a delay).
    static func computeCard(
        seat: Int,
        hand: [Card],
        actualPartnerIndices: Set<Int>,
        revealedPartnerIndices: Set<Int>,
        calledCardIds: Set<String>,
        highBidderIndex: Int,
        trumpSuit: TrumpSuit,
        currentTrick: [(playerIndex: Int, card: Card)],
        completedTricks: [[(playerIndex: Int, card: Card)]],
        wonPointsPerPlayer: [Int],
        highBid: Int,
        trickNumber: Int,
        personality: BotPersonality? = nil
    ) -> String? {
        guard !hand.isEmpty else { return nil }

        let style = personality ?? BotPersonality.forSeat(seat)
        let trumpRaw = trumpSuit.rawValue
        let actualPartners = actualPartnerIndices.filter { $0 >= 0 && $0 < 6 }
        let knownOffense = knownOffenseSet(
            seat: seat,
            hand: hand,
            highBidderIndex: highBidderIndex,
            actualPartnerIndices: actualPartners,
            revealedPartnerIndices: revealedPartnerIndices,
            calledCardIds: calledCardIds
        )
        let knownVoids = knownVoids(from: completedTricks)
        let remainingCards = unseenCards(
            hand: hand,
            currentTrick: currentTrick,
            completedTricks: completedTricks
        )
        let teamRead = inferTeamRead(
            publicKnownOffense: knownOffense,
            highBidderIndex: highBidderIndex,
            trumpRaw: trumpRaw,
            currentTrick: currentTrick,
            completedTricks: completedTricks,
            wonPointsPerPlayer: wonPointsPerPlayer
        )
        let strategicOffense = knownOffense.union(teamRead.suspectedOffense)
        let isKnownOffense = knownOffense.contains(seat)
        let urgency = urgencyState(
            knownOffenseSet: knownOffense,
            wonPointsPerPlayer: wonPointsPerPlayer,
            highBid: highBid,
            trickNumber: trickNumber,
            personality: style
        )
        let playedCalledCardIds = playedCalledCardIds(
            calledCardIds: calledCardIds,
            currentTrick: currentTrick,
            completedTricks: completedTricks
        )
        let unrevealedCalledCardIds = calledCardIds.subtracting(playedCalledCardIds)

        // ── LEADING ──────────────────────────────────────────────────────────
        if currentTrick.isEmpty {
            if let revealCard = hiddenPartnerRevealCard(
                seat: seat,
                hand: hand,
                actualPartnerIndices: actualPartners,
                revealedPartnerIndices: revealedPartnerIndices,
                calledCardIds: unrevealedCalledCardIds,
                highBidderIndex: highBidderIndex,
                trumpRaw: trumpRaw,
                currentTrick: currentTrick,
                winnerCard: nil,
                trickPoints: 0,
                futureThreats: 0,
                canFeedPoints: true,
                urgency: urgency,
                trickNumber: trickNumber,
                personality: style
            ) {
                return revealCard.id
            }

            return bestLeadCard(
                hand: hand,
                seat: seat,
                isKnownOffense: isKnownOffense,
                strategicOffenseSet: strategicOffense,
                highBidderIndex: highBidderIndex,
                trumpRaw: trumpRaw,
                unrevealedCalledCardIds: unrevealedCalledCardIds,
                revealedPartnerCount: revealedPartnerIndices.count,
                remainingCards: remainingCards,
                knownVoids: knownVoids,
                urgency: urgency,
                personality: style
            ).id
        }

        // ── FOLLOWING ────────────────────────────────────────────────────────
        let ledSuit = currentTrick[0].card.suit
        let sameSuit = hand.filter { $0.suit == ledSuit }
        let winnerIndex = trickWinnerIndex(trick: currentTrick, trumpSuit: trumpSuit)
        guard let winner = currentTrick.first(where: { $0.playerIndex == winnerIndex }) else {
            return hand[0].id
        }

        let teammateWinning = strategicOffense.contains(winner.playerIndex) == isKnownOffense
        let futureSeats = playersAfter(seat: seat, currentTrick: currentTrick)
        let futureThreats = futureOpponentThreatCount(
            futureSeats: futureSeats,
            isKnownOffense: isKnownOffense,
            strategicOffenseSet: strategicOffense,
            winnerCard: winner.card,
            ledSuit: ledSuit,
            trumpRaw: trumpRaw,
            remainingCards: remainingCards,
            knownVoids: knownVoids
        )
        let trickPoints = currentTrick.map(\.card.pointValue).reduce(0, +)
        let canFeedPoints = futureThreats <= style.unsafeFeedTolerance
            || (isKnownOffense && urgency.offense)
            || (!isKnownOffense && urgency.defense)

        if let revealCard = hiddenPartnerRevealCard(
            seat: seat,
            hand: hand,
            actualPartnerIndices: actualPartners,
            revealedPartnerIndices: revealedPartnerIndices,
            calledCardIds: unrevealedCalledCardIds,
            highBidderIndex: highBidderIndex,
            trumpRaw: trumpRaw,
            currentTrick: currentTrick,
            winnerCard: winner.card,
            trickPoints: trickPoints,
            futureThreats: futureThreats,
            canFeedPoints: canFeedPoints,
            urgency: urgency,
            trickNumber: trickNumber,
            personality: style
        ) {
            return revealCard.id
        }

        if !sameSuit.isEmpty {
            if teammateWinning {
                return (canFeedPoints
                    ? highestValueCard(sameSuit, personality: style)
                    : lowestValueCard(sameSuit)).id
            }

            let winningCards = sameSuit.filter {
                cardBeats($0, winner: winner.card, ledSuit: ledSuit, trumpRaw: trumpRaw)
            }
            if let best = lowestWinningCard(winningCards, trumpRaw: trumpRaw) {
                return best.id
            }
            return lowestValueCard(sameSuit).id
        }

        // ── CAN'T FOLLOW ──────────────────────────────────────────────────────
        let trumpCards = hand.filter { $0.suit == trumpRaw }
        let nonTrump = hand.filter { $0.suit != trumpRaw }

        if teammateWinning {
            if canFeedPoints, let feed = nonTrump.max(by: { valueScore($0, personality: style) < valueScore($1, personality: style) }) {
                return feed.id
            }
            if let discard = nonTrump.min(by: { valueScore($0, personality: style) < valueScore($1, personality: style) }) {
                return discard.id
            }
            return lowestValueCard(trumpCards.isEmpty ? hand : trumpCards).id
        }

        let winningTrumps = trumpCards.filter {
            cardBeats($0, winner: winner.card, ledSuit: ledSuit, trumpRaw: trumpRaw)
        }
        let shouldTrump = !winningTrumps.isEmpty
            && (trickPoints >= style.trumpInPointThreshold || urgency.eitherSide)
        if shouldTrump, let bestTrump = lowestWinningCard(winningTrumps, trumpRaw: trumpRaw) {
            return bestTrump.id
        }

        if let discard = nonTrump.min(by: { valueScore($0, personality: style) < valueScore($1, personality: style) }) {
            return discard.id
        }
        return lowestValueCard(trumpCards.isEmpty ? hand : trumpCards).id
    }

    private static func knownOffenseSet(
        seat: Int,
        hand: [Card],
        highBidderIndex: Int,
        actualPartnerIndices: Set<Int>,
        revealedPartnerIndices: Set<Int>,
        calledCardIds: Set<String>
    ) -> Set<Int> {
        var known = Set([highBidderIndex])
        known.formUnion(revealedPartnerIndices.filter { $0 >= 0 && $0 < 6 })

        if seat == highBidderIndex {
            known.formUnion(actualPartnerIndices)
            return known
        }

        let handIds = Set(hand.map(\.id))
        let knowsSelfIsPartner = actualPartnerIndices.contains(seat)
            && (!handIds.isDisjoint(with: calledCardIds) || revealedPartnerIndices.contains(seat))
        if knowsSelfIsPartner {
            known.insert(seat)
        }
        return known
    }

    private static func inferTeamRead(
        publicKnownOffense: Set<Int>,
        highBidderIndex: Int,
        trumpRaw: String,
        currentTrick: [(playerIndex: Int, card: Card)],
        completedTricks: [[(playerIndex: Int, card: Card)]],
        wonPointsPerPlayer: [Int]
    ) -> TeamRead {
        var scores: [Int: Int] = [:]
        scores[highBidderIndex, default: 0] += 100
        for player in publicKnownOffense {
            scores[player, default: 0] += 80
        }

        var allTricks = completedTricks
        if !currentTrick.isEmpty { allTricks.append(currentTrick) }
        for trick in allTricks {
            guard let ledSuit = trick.first?.card.suit else { continue }
            var partial: [(playerIndex: Int, card: Card)] = []

            for entry in trick {
                let previousWinner: Int? = partial.isEmpty
                    ? nil
                    : trickWinnerIndexFromPartial(partial, trumpRaw: trumpRaw)
                let previousWinnerIsOffense = previousWinner.map { publicKnownOffense.contains($0) || $0 == highBidderIndex } ?? false
                let playedPoints = entry.card.pointValue

                if previousWinnerIsOffense && playedPoints > 0 {
                    let wouldBeat = previousWinner.flatMap { winnerIndex in
                        partial.first(where: { $0.playerIndex == winnerIndex })?.card
                    }.map { winnerCard in
                        cardBeats(entry.card, winner: winnerCard, ledSuit: ledSuit, trumpRaw: trumpRaw)
                    } ?? true
                    if !wouldBeat {
                        scores[entry.playerIndex, default: 0] += playedPoints >= 10 ? 3 : 1
                    }
                }

                if !previousWinnerIsOffense,
                   playedPoints == 0,
                   entry.card.suit == trumpRaw,
                   let previousWinner,
                   let winnerCard = partial.first(where: { $0.playerIndex == previousWinner })?.card,
                   cardBeats(entry.card, winner: winnerCard, ledSuit: ledSuit, trumpRaw: trumpRaw) {
                    scores[entry.playerIndex, default: 0] += 2
                }

                partial.append(entry)
            }

            let finalWinner: Int? = partial.isEmpty
                ? nil
                : trickWinnerIndexFromPartial(partial, trumpRaw: trumpRaw)
            if let winner = finalWinner,
               publicKnownOffense.contains(winner) || winner == highBidderIndex {
                for entry in trick where entry.playerIndex != winner && entry.card.pointValue > 0 {
                    scores[entry.playerIndex, default: 0] += 1
                }
            }
        }

        for (player, points) in wonPointsPerPlayer.enumerated() where points >= 60 {
            scores[player, default: 0] += 1
        }

        let suspected = Set<Int>(scores.compactMap { player, score in
            guard !publicKnownOffense.contains(player), player != highBidderIndex, score >= 4 else { return nil }
            return player
        })
        return TeamRead(suspectedOffense: suspected, suspicionScores: scores)
    }

    private static func trickWinnerIndexFromPartial(
        _ trick: [(playerIndex: Int, card: Card)],
        trumpRaw: String
    ) -> Int {
        let ledSuit = trick[0].card.suit
        let trumpPlays = trick.filter { $0.card.suit == trumpRaw }
        if let winner = trumpPlays.max(by: { rankScore($0.card) < rankScore($1.card) }) {
            return winner.playerIndex
        }
        let ledPlays = trick.filter { $0.card.suit == ledSuit }
        return ledPlays.max(by: { rankScore($0.card) < rankScore($1.card) })?.playerIndex ?? trick[0].playerIndex
    }

    private static func playedCalledCardIds(
        calledCardIds: Set<String>,
        currentTrick: [(playerIndex: Int, card: Card)],
        completedTricks: [[(playerIndex: Int, card: Card)]]
    ) -> Set<String> {
        guard !calledCardIds.isEmpty else { return [] }
        let playedCards = completedTricks.flatMap { $0.map(\.card.id) } + currentTrick.map(\.card.id)
        return Set(playedCards.filter { calledCardIds.contains($0) })
    }

    private static func hiddenPartnerRevealCard(
        seat: Int,
        hand: [Card],
        actualPartnerIndices: Set<Int>,
        revealedPartnerIndices: Set<Int>,
        calledCardIds: Set<String>,
        highBidderIndex: Int,
        trumpRaw: String,
        currentTrick: [(playerIndex: Int, card: Card)],
        winnerCard: Card?,
        trickPoints: Int,
        futureThreats: Int,
        canFeedPoints: Bool,
        urgency: Urgency,
        trickNumber: Int,
        personality: BotPersonality
    ) -> Card? {
        guard seat != highBidderIndex,
              actualPartnerIndices.contains(seat),
              !revealedPartnerIndices.contains(seat) else { return nil }

        let calledCardsInHand = hand.filter { calledCardIds.contains($0.id) }
        guard !calledCardsInHand.isEmpty else { return nil }

        let legalCalledCards = legalPlayableCards(
            from: calledCardsInHand,
            hand: hand,
            currentTrick: currentTrick
        )
        guard !legalCalledCards.isEmpty else { return nil }

        let intent = partnerRevealIntent(
            legalCalledCards: legalCalledCards,
            winnerCard: winnerCard,
            trumpRaw: trumpRaw,
            currentTrick: currentTrick,
            trickPoints: trickPoints,
            futureThreats: futureThreats,
            canFeedPoints: canFeedPoints,
            urgency: urgency,
            trickNumber: trickNumber,
            personality: personality
        )
        guard intent.shouldReveal else { return nil }

        switch intent {
        case .revealToWin:
            if let winnerCard {
                let ledSuit = currentTrick.first?.card.suit ?? legalCalledCards[0].suit
                return lowestWinningCard(
                    legalCalledCards.filter { cardBeats($0, winner: winnerCard, ledSuit: ledSuit, trumpRaw: trumpRaw) },
                    trumpRaw: trumpRaw
                )
            }
            return strongestCalledCard(legalCalledCards, trumpRaw: trumpRaw)
        case .revealToFeed:
            return legalCalledCards.max {
                valueScore($0, personality: personality) < valueScore($1, personality: personality)
            }
        case .revealToCoordinate:
            return strongestCalledCard(legalCalledCards, trumpRaw: trumpRaw)
        case .stayHidden:
            return nil
        }
    }

    private static func partnerRevealIntent(
        legalCalledCards: [Card],
        winnerCard: Card?,
        trumpRaw: String,
        currentTrick: [(playerIndex: Int, card: Card)],
        trickPoints: Int,
        futureThreats: Int,
        canFeedPoints: Bool,
        urgency: Urgency,
        trickNumber: Int,
        personality: BotPersonality
    ) -> PartnerRevealIntent {
        let lateRound = trickNumber >= 5
        let coordinationWindow = trickNumber >= 3 && personality != .conservative
        let highValueCalledCard = legalCalledCards.contains { $0.pointValue >= 10 || $0.suit == trumpRaw }

        if currentTrick.isEmpty {
            if urgency.offense || lateRound {
                return .revealToCoordinate
            }
            if coordinationWindow && highValueCalledCard {
                return .revealToCoordinate
            }
            return .stayHidden
        }

        guard let winnerCard else { return .stayHidden }
        let ledSuit = currentTrick[0].card.suit
        let winningCalledCards = legalCalledCards.filter {
            cardBeats($0, winner: winnerCard, ledSuit: ledSuit, trumpRaw: trumpRaw)
        }

        if !winningCalledCards.isEmpty {
            if urgency.offense || trickPoints >= personality.trumpInPointThreshold || lateRound {
                return .revealToWin
            }
            if personality == .aggressive || personality == .riskTaker {
                return .revealToWin
            }
        }

        if canFeedPoints,
           futureThreats <= personality.unsafeFeedTolerance,
           legalCalledCards.contains(where: { $0.pointValue > 0 }),
           (urgency.offense || lateRound || personality == .pointFeeder) {
            return .revealToFeed
        }

        if coordinationWindow && highValueCalledCard && futureThreats == 0 {
            return .revealToCoordinate
        }

        return .stayHidden
    }

    private static func legalPlayableCards(
        from candidates: [Card],
        hand: [Card],
        currentTrick: [(playerIndex: Int, card: Card)]
    ) -> [Card] {
        guard let ledSuit = currentTrick.first?.card.suit else { return candidates }
        let sameSuitInHand = hand.filter { $0.suit == ledSuit }
        guard !sameSuitInHand.isEmpty else { return candidates }
        return candidates.filter { $0.suit == ledSuit }
    }

    private static func strongestCalledCard(_ cards: [Card], trumpRaw: String) -> Card {
        cards.max {
            let lhs = ($0.suit == trumpRaw ? 100 : 0) + $0.pointValue * 10 + rankScore($0)
            let rhs = ($1.suit == trumpRaw ? 100 : 0) + $1.pointValue * 10 + rankScore($1)
            return lhs < rhs
        } ?? cards[0]
    }

    private static func knownVoids(
        from completedTricks: [[(playerIndex: Int, card: Card)]]
    ) -> [Int: Set<String>] {
        var voids: [Int: Set<String>] = [:]
        for trick in completedTricks {
            guard let ledSuit = trick.first?.card.suit else { continue }
            for entry in trick where entry.card.suit != ledSuit {
                voids[entry.playerIndex, default: []].insert(ledSuit)
            }
        }
        return voids
    }

    private static func unseenCards(
        hand: [Card],
        currentTrick: [(playerIndex: Int, card: Card)],
        completedTricks: [[(playerIndex: Int, card: Card)]]
    ) -> [Card] {
        var seen = Set(hand.map(\.id))
        seen.formUnion(currentTrick.map(\.card.id))
        seen.formUnion(completedTricks.flatMap { $0.map(\.card.id) })
        return fullDeck.filter { !seen.contains($0.id) }
    }

    private static func urgencyState(
        knownOffenseSet: Set<Int>,
        wonPointsPerPlayer: [Int],
        highBid: Int,
        trickNumber: Int,
        personality: BotPersonality
    ) -> Urgency {
        func points(for index: Int) -> Int {
            guard wonPointsPerPlayer.indices.contains(index) else { return 0 }
            return wonPointsPerPlayer[index]
        }

        let offensePoints = knownOffenseSet.map(points(for:)).reduce(0, +)
        let totalPoints = wonPointsPerPlayer.reduce(0, +)
        let defensePoints = totalPoints - offensePoints
        let remainingPoints = max(0, 250 - totalPoints)
        let tricksRemaining = max(0, 8 - trickNumber)
        let offenseShortfall = max(0, highBid - offensePoints)
        let defenseTarget = max(0, 251 - highBid)
        let defenseShortfall = max(0, defenseTarget - defensePoints)

        let offensePressure = personality == .riskTaker ? 5 : 6
        let defensePressure = personality == .conservative ? 6 : 5
        let offenseUrgent = remainingPoints > 0
            && (offenseShortfall * 10 > remainingPoints * offensePressure
                || (tricksRemaining <= 2 && offenseShortfall > 0))
        let defenseUrgent = remainingPoints > 0
            && (defenseShortfall * 10 > remainingPoints * defensePressure
                || (tricksRemaining <= 2 && offensePoints < highBid && offensePoints + remainingPoints >= highBid))

        return Urgency(
            offense: offenseUrgent,
            defense: defenseUrgent,
            offensePoints: offensePoints,
            defensePoints: defensePoints,
            remainingPoints: remainingPoints,
            tricksRemaining: tricksRemaining
        )
    }

    private static func bestLeadCard(
        hand: [Card],
        seat: Int,
        isKnownOffense: Bool,
        strategicOffenseSet: Set<Int>,
        highBidderIndex: Int,
        trumpRaw: String,
        unrevealedCalledCardIds: Set<String>,
        revealedPartnerCount: Int,
        remainingCards: [Card],
        knownVoids: [Int: Set<String>],
        urgency: Urgency,
        personality: BotPersonality
    ) -> Card {
        let unrevealedCalledSuits = Set(unrevealedCalledCardIds.compactMap { $0.last.map(String.init) })
        let scored = hand.map { card -> (Card, Int) in
            let isTrump = card.suit == trumpRaw
            let higherRemaining = remainingCards.filter {
                $0.suit == card.suit && rankScore($0) > rankScore(card)
            }.count
            let higherTrumpRemaining = remainingCards.filter {
                $0.suit == trumpRaw && rankScore($0) > rankScore(card)
            }.count
            let futureVoidRisk = (0..<6).filter {
                strategicOffenseSet.contains($0) != isKnownOffense
                    && knownVoids[$0]?.contains(card.suit) == true
            }.count

            var score = rankScore(card) + card.pointValue
            if isTrump {
                score += personality.leadTrumpBias
                if rankScore(card) >= personality.trumpLeadFloor { score += 18 }
                if seat == highBidderIndex || personality == .trumpController { score += 10 }
                if higherTrumpRemaining == 0 { score += 10 }
                if higherTrumpRemaining >= 3 { score -= higherTrumpRemaining * 4 }
                if !isKnownOffense && !urgency.defense { score -= 8 }
            } else {
                score += higherRemaining == 0 ? 18 : -(higherRemaining * 3)
                score -= futureVoidRisk * 10
                if isKnownOffense && urgency.offense { score += card.pointValue * 3 }
                if !isKnownOffense && urgency.defense { score += card.pointValue * 2 }
                if seat == highBidderIndex,
                   revealedPartnerCount < 2,
                   unrevealedCalledSuits.contains(card.suit) {
                    score += 24 - card.pointValue
                    if urgency.offense { score += 12 }
                }
                score += personality.pointFeedBias
            }
            return (card, score)
        }

        return scored.max {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return rankScore($0.0) < rankScore($1.0)
        }?.0 ?? hand[0]
    }

    private static func playersAfter(
        seat: Int,
        currentTrick: [(playerIndex: Int, card: Card)]
    ) -> [Int] {
        guard let leader = currentTrick.first?.playerIndex else { return [] }
        let order = (0..<6).map { (leader + $0) % 6 }
        let alreadyPlayed = Set(currentTrick.map(\.playerIndex))
        guard let position = order.firstIndex(of: seat), position + 1 < order.count else { return [] }
        return order[(position + 1)...].filter { !alreadyPlayed.contains($0) }
    }

    private static func futureOpponentThreatCount(
        futureSeats: [Int],
        isKnownOffense: Bool,
        strategicOffenseSet: Set<Int>,
        winnerCard: Card,
        ledSuit: String,
        trumpRaw: String,
        remainingCards: [Card],
        knownVoids: [Int: Set<String>]
    ) -> Int {
        let futureOpponents = futureSeats.filter { strategicOffenseSet.contains($0) != isKnownOffense }
        guard !futureOpponents.isEmpty else { return 0 }

        let higherTrumpCount = remainingCards.filter {
            $0.suit == trumpRaw && rankScore($0) > rankScore(winnerCard)
        }.count
        let higherLedCount = remainingCards.filter {
            $0.suit == ledSuit && rankScore($0) > rankScore(winnerCard)
        }.count
        let trumpRemainingCount = remainingCards.filter { $0.suit == trumpRaw }.count

        return futureOpponents.reduce(0) { risk, player in
            if winnerCard.suit == trumpRaw {
                if knownVoids[player]?.contains(ledSuit) == true && higherTrumpCount > 0 {
                    return risk + 3
                }
                return risk + (higherTrumpCount >= 2 ? 1 : 0)
            }
            if knownVoids[player]?.contains(ledSuit) == true && trumpRemainingCount > 0 {
                return risk + (trumpRemainingCount >= 3 ? 3 : 2)
            }
            if higherLedCount > 0 {
                return risk + min(2, higherLedCount)
            }
            return risk
        }
    }

    private static func cardBeats(
        _ card: Card,
        winner: Card,
        ledSuit: String,
        trumpRaw: String
    ) -> Bool {
        if card.suit == trumpRaw && winner.suit != trumpRaw { return true }
        if card.suit == trumpRaw && winner.suit == trumpRaw {
            return rankScore(card) > rankScore(winner)
        }
        if winner.suit == trumpRaw { return false }
        return card.suit == ledSuit && winner.suit == ledSuit && rankScore(card) > rankScore(winner)
    }

    private static func lowestWinningCard(_ cards: [Card], trumpRaw: String) -> Card? {
        cards.min {
            let lhs = ($0.suit == trumpRaw ? 100 : 0) + rankScore($0)
            let rhs = ($1.suit == trumpRaw ? 100 : 0) + rankScore($1)
            if lhs != rhs { return lhs < rhs }
            return $0.pointValue < $1.pointValue
        }
    }

    private static func highestValueCard(_ cards: [Card], personality: BotPersonality) -> Card {
        cards.max {
            valueScore($0, personality: personality) < valueScore($1, personality: personality)
        } ?? cards[0]
    }

    private static func lowestValueCard(_ cards: [Card]) -> Card {
        cards.min {
            if $0.pointValue != $1.pointValue { return $0.pointValue < $1.pointValue }
            return rankScore($0) < rankScore($1)
        } ?? cards[0]
    }

    private static func rankScore(_ card: Card) -> Int {
        Card.rankOrder[card.rank] ?? 0
    }

    private static func valueScore(_ card: Card, personality: BotPersonality) -> Int {
        let feedBonus = personality == .pointFeeder ? card.pointValue * 20 : 0
        return card.pointValue * 100 + rankScore(card) + feedBonus
    }
}
