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
        let bidderCloseToWin: Bool
        let bidSecure: Bool        // ADD THIS

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

    // MARK: - Hand Model

    /// Per-player card probability distribution built from public information.
    /// Stateless — rebuilt each computeCard call. Internal so AIEngineTests can access it.
    struct HandModel {
        // prob[cardId][playerIndex] → probability (0–1) player holds this card
        private let prob: [String: [Int: Double]]

        /// Probability that `player` holds any remaining card in `suit` with
        /// rankScore > `beatingRankScore`. Pass -1 to match any card in the suit.
        func threatProb(player: Int, suit: String, beatingRankScore: Int) -> Double {
            prob.reduce(0.0) { sum, entry in
                guard let cardSuit = entry.key.last.map(String.init),
                      cardSuit == suit else { return sum }
                let cardRank = String(entry.key.dropLast())
                let rs = Card.rankOrder[cardRank] ?? 0
                guard rs > beatingRankScore else { return sum }
                return sum + (entry.value[player] ?? 0)
            }
        }

        /// Probability that `player` holds no remaining cards in `suit`.
        func voidProb(player: Int, suit: String) -> Double {
            let held = prob.reduce(0.0) { sum, entry in
                guard let cardSuit = entry.key.last.map(String.init),
                      cardSuit == suit else { return sum }
                return sum + (entry.value[player] ?? 0)
            }
            return max(0, 1.0 - held)
        }

        static func build(
            seat: Int,
            remainingCards: [Card],
            knownVoids: [Int: Set<String>],
            completedTricks: [[(playerIndex: Int, card: Card)]],
            playerBidStrengths: [Int: Int]
        ) -> HandModel {
            // Determine which players led which suits from completed tricks.
            var leadersBySuit: [String: Set<Int>] = [:]
            for trick in completedTricks {
                guard let lead = trick.first else { continue }
                leadersBySuit[lead.card.suit, default: []].insert(lead.playerIndex)
            }

            var result: [String: [Int: Double]] = [:]

            for card in remainingCards {
                // Eligible holders: all non-self players not confirmed void in this suit.
                let eligible = (0..<6).filter { p in
                    p != seat && !(knownVoids[p]?.contains(card.suit) == true)
                }
                guard !eligible.isEmpty else {
                    result[card.id] = [:]
                    continue
                }

                let isHighValue = card.pointValue >= 10 || (Card.rankOrder[card.rank] ?? 0) >= 9

                var weights: [Int: Double] = [:]
                for p in eligible {
                    var w = 1.0
                    // Bid boost: strong bidders more likely hold high-value cards.
                    if isHighValue, let strength = playerBidStrengths[p] {
                        w *= 1.0 + (Double(strength) / 5.0) * 0.5
                    }
                    // Lead boost: player who led this suit likely still holds cards in it.
                    if leadersBySuit[card.suit]?.contains(p) == true {
                        w *= 1.5
                    }
                    weights[p] = w
                }

                let total = weights.values.reduce(0, +)
                result[card.id] = total > 0
                    ? weights.mapValues { $0 / total }
                    : Dictionary(uniqueKeysWithValues: eligible.map { ($0, 1.0 / Double(eligible.count)) })
            }

            return HandModel(prob: result)
        }
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
    /// `bidHistory` enables loser-adjusted and bid-identity-aware bidding.
    static func computeBid(
        seat: Int,
        hand: [Card],
        dealerIndex: Int,
        highBid: Int,
        canPass: Bool,
        personality: BotPersonality? = nil,
        bidHistory: [(playerIndex: Int, amount: Int)] = []
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

        // Phase 1d — Loser counting: multi-card suits where opponents hold higher
        // cards will produce lost tricks; penalise 3pts per net loser.
        var loserCount = 0
        for suit in TrumpSuit.allCases {
            let suitCards = hand.filter { $0.suit == suit.rawValue }
            guard suitCards.count >= 2 else { continue }
            let myTopRank = suitCards.compactMap { Card.rankOrder[$0.rank] }.max() ?? 0
            let higherExternal = fullDeck.filter { card in
                card.suit == suit.rawValue && !myIds.contains(card.id)
                    && (Card.rankOrder[card.rank] ?? 0) > myTopRank
            }.count
            if higherExternal >= 2 {
                loserCount += min(suitCards.count - 1, higherExternal - 1)
            }
        }
        let loserPenalty = loserCount * 3

        // Phase 1e — Bid identity: strong competing bidders in good seat positions
        // are probable strong partners; modestly raise the partner quality estimate.
        var partnerQualityBonus = 0
        for entry in latestBidPerPlayer(bidHistory) where entry.playerIndex != seat && entry.amount > 150 {
            let bidStrength = (entry.amount - 150) / 20  // 0–5
            let offset = (entry.playerIndex - seat + 6) % 6
            let posBonus = (offset >= 2 && offset <= 4) ? 1 : 0
            partnerQualityBonus += bidStrength * posBonus
        }
        partnerQualityBonus = min(6, partnerQualityBonus)

        let rawEstimate = myPoints + call1Pts + call2Pts + partnerBonus + clusterBonus
            - shortnessPenalty - loserPenalty + partnerQualityBonus
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
    /// `seat`, `dealerIndex`, and `bidHistory` enable position-aware partner selection:
    /// among equally-valued candidates, prefer cards likely held by players who sit
    /// 2–5 seats after the bidder (they play after seeing the bidder's card, enabling
    /// better coordination). Players who bid higher are weighted as more likely to hold
    /// top-ranked cards in each suit.
    static func computeCalling(
        hand: [Card],
        seat: Int = 0,
        dealerIndex: Int = 0,
        bidHistory: [(playerIndex: Int, amount: Int)] = [],
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

        // Position-aware reordering: among equal-value candidates, prefer cards
        // likely held by players in good trick-order positions (2–5 seats after bidder).
        // Later seats see the bidder's card before playing — better for coordination.
        if !bidHistory.isEmpty {
            let bidMap: [Int: Int] = latestBidPerPlayer(bidHistory)
                .reduce(into: [:]) { dict, entry in dict[entry.playerIndex] = entry.amount }

            // Position quality: how good is it to have THIS player as a partner?
            // Offset 1 (plays right after bidder) = worst; offset 3–5 = best.
            func positionQuality(_ player: Int) -> Int {
                let offset = (player - seat + 6) % 6
                switch offset {
                case 1: return 0
                case 2: return 1
                case 3: return 2
                case 4, 5: return 3
                default: return 0
                }
            }

            // Estimate whether a high-ranked card is likely held by a strong bidder.
            // Higher bid → more likely to hold the top cards in any suit.
            func candidatePositionScore(_ card: Card) -> Int {
                let cardHighness = max(0, (Card.rankOrder[card.rank] ?? 0) - 9) // 0–3 for J/Q/K/A
                var total = 0
                for player in 0..<6 where player != seat {
                    let bidStrength = max(0, (bidMap[player, default: 130] - 130) / 30) // 0–4
                    total += positionQuality(player) * bidStrength * (1 + cardHighness)
                }
                return total
            }

            ordered.sort { a, b in
                if a.pointValue != b.pointValue { return a.pointValue > b.pointValue }
                let aPos = candidatePositionScore(a)
                let bPos = candidatePositionScore(b)
                if aPos != bPos { return aPos > bPos }
                return rankScore(a) > rankScore(b)
            }
        }

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
        personality: BotPersonality? = nil,
        bidHistory: [(playerIndex: Int, amount: Int)] = []
    ) -> String? {
        guard !hand.isEmpty else { return nil }

        let style = personality ?? BotPersonality.forSeat(seat)
        let trumpRaw = trumpSuit.rawValue
        let actualPartners = actualPartnerIndices.filter { $0 >= 0 && $0 < 6 }
        // Bid-strength per player (0–5 scale): used for team inference priors
        // and for lead-decision opponent risk weighting.
        let playerBidStrengths: [Int: Int] = latestBidPerPlayer(bidHistory)
            .reduce(into: [:]) { dict, entry in
                dict[entry.playerIndex] = min(5, max(0, (entry.amount - 130) / 24))
            }
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
        let handModel = HandModel.build(
            seat: seat,
            remainingCards: remainingCards,
            knownVoids: knownVoids,
            completedTricks: completedTricks,
            playerBidStrengths: playerBidStrengths
        )
        let teamRead = inferTeamRead(
            publicKnownOffense: knownOffense,
            highBidderIndex: highBidderIndex,
            trumpRaw: trumpRaw,
            currentTrick: currentTrick,
            completedTricks: completedTricks,
            wonPointsPerPlayer: wonPointsPerPlayer,
            playerBidStrengths: playerBidStrengths
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

            // Endgame: last 3 tricks — switch to near-exact calculation
            // using known remaining cards instead of heuristic scoring.
            if urgency.tricksRemaining <= 3,
               let endgameLead = computeEndgameLead(
                   hand: hand,
                   isKnownOffense: isKnownOffense,
                   trumpRaw: trumpRaw,
                   remainingCards: remainingCards,
                   urgency: urgency
               ) {
                return endgameLead.id
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
                personality: style,
                playerBidStrengths: playerBidStrengths,
                handModel: handModel,
                revealedPartnerIndices: revealedPartnerIndices
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
            knownVoids: knownVoids,
            handModel: handModel
        )
        let trickPoints = currentTrick.map(\.card.pointValue).reduce(0, +)
        // Dynamic personality: urgency raises feed tolerance by 1 so bots take
        // more risks when behind, mirroring how a human adapts under pressure.
        let adaptedFeedTolerance = style.unsafeFeedTolerance + (urgency.eitherSide ? 1 : 0)
        let canFeedPoints = (!isKnownOffense && urgency.bidderCloseToWin)
            ? false
            : (futureThreats <= adaptedFeedTolerance
               || (isKnownOffense && urgency.offense)
               || (!isKnownOffense && urgency.defense))

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
            // Void creation: discard the last card of a zero-value suit to enable
            // future ruffs, provided we still have trump to ruff with.
            if !trumpCards.isEmpty && urgency.tricksRemaining >= 2 {
                let voidCreation = nonTrump
                    .filter { card in
                        hand.filter { $0.suit == card.suit }.count == 1
                            && card.pointValue == 0
                    }
                    .min(by: { rankScore($0) < rankScore($1) })
                if let voidCard = voidCreation { return voidCard.id }
            }
            if canFeedPoints, let feed = nonTrump.max(by: { valueScore($0, personality: style) < valueScore($1, personality: style) }) {
                return feed.id
            }
            if let discard = nonTrump.max(by: {
                discardPreference($0, hand: hand, remainingCards: remainingCards)
                    < discardPreference($1, hand: hand, remainingCards: remainingCards)
            }) {
                return discard.id
            }
            return lowestValueCard(trumpCards.isEmpty ? hand : trumpCards).id
        }

        let winningTrumps = trumpCards.filter {
            cardBeats($0, winner: winner.card, ledSuit: ledSuit, trumpRaw: trumpRaw)
        }
        // 3♠ strategy: trump eagerly if 3♠ is in THIS trick (capture 30pts);
        // raise the threshold on other tricks so trump is reserved for that future capture.
        // Sacrifice play: the raised threshold prevents burning trump on cheap tricks
        // when significant value remains unplayed, keeping trump for bigger moments.
        let threeSpadeInTrick = currentTrick.contains { $0.card.id == "3♠" }
        let threeSpadeStillOut = remainingCards.contains { $0.id == "3♠" }
        var effectiveTrumpThreshold: Int
        if threeSpadeInTrick {
            effectiveTrumpThreshold = 0          // Always trump to contest the 3♠
        } else if threeSpadeStillOut && !urgency.eitherSide {
            effectiveTrumpThreshold = style.trumpInPointThreshold + 15  // Save trump
        } else {
            effectiveTrumpThreshold = style.trumpInPointThreshold
        }
        if isKnownOffense && urgency.bidSecure { effectiveTrumpThreshold += 20 }
        // When bid is already secure, offense bots should not be forced to trump by urgency alone —
        // the raised threshold governs. Otherwise urgency (e.g. defenseUrgent) would bypass the raise.
        let safetyOverridesUrgency = isKnownOffense && urgency.bidSecure
        let shouldTrump = !winningTrumps.isEmpty
            && (trickPoints >= effectiveTrumpThreshold || (urgency.eitherSide && !safetyOverridesUrgency))
        if shouldTrump, let bestTrump = lowestWinningCard(winningTrumps, trumpRaw: trumpRaw) {
            // Over-ruffing check: if a future opponent is void in the led suit AND
            // holds a higher trump, our trump will be over-ruffed for no gain.
            // Skip trumping and discard instead, unless urgency overrides.
            let wouldBeOverRuffed = futureSeats.contains { playerSeat in
                guard strategicOffense.contains(playerSeat) != isKnownOffense else { return false }
                let voidInLed = knownVoids[playerSeat]?.contains(ledSuit) == true
                let hasHigherTrump = remainingCards.contains {
                    $0.suit == trumpRaw && rankScore($0) > rankScore(bestTrump)
                }
                return voidInLed && hasHigherTrump
            }
            if !wouldBeOverRuffed || urgency.eitherSide {
                return bestTrump.id
            }
            // Fall through to discard — burning trump into an over-ruff wastes it
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
        wonPointsPerPlayer: [Int],
        playerBidStrengths: [Int: Int] = [:]
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

        // Bid-strength prior: players who bid aggressively before losing the bid
        // likely had strong hands — they are more probable silent partners.
        // Capped at a small nudge (strength/2) so behavioral signals dominate.
        for (player, strength) in playerBidStrengths
        where player != highBidderIndex && !publicKnownOffense.contains(player) {
            scores[player, default: 0] += strength / 2
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
        // Fires when offense is well advanced (≥75% of bid) and can finish from the
        // top half of remaining points, OR when very few points remain and offense
        // can still complete. Tells defense bots to switch into point-denial mode.
        let bidderCloseToWin = remainingPoints > 0
            && ((Double(offensePoints) >= Double(highBid) * 0.75
                 && offenseShortfall <= remainingPoints / 2)
                || (offenseShortfall <= remainingPoints && remainingPoints < 30))

        let bidSecure = offensePoints >= highBid

        return Urgency(
            offense: offenseUrgent,
            defense: defenseUrgent,
            offensePoints: offensePoints,
            defensePoints: defensePoints,
            remainingPoints: remainingPoints,
            tricksRemaining: tricksRemaining,
            bidderCloseToWin: bidderCloseToWin,
            bidSecure: bidSecure
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
        personality: BotPersonality,
        playerBidStrengths: [Int: Int] = [:],
        handModel: HandModel? = nil,
        revealedPartnerIndices: Set<Int> = []
    ) -> Card {
        let unrevealedCalledSuits = Set(unrevealedCalledCardIds.compactMap { $0.last.map(String.init) })
        // 3♠ is still unplayed — factor into lead decisions below.
        let threeSpadeStillOut = remainingCards.contains { $0.id == "3♠" }
        // Trump exhaustion: if no trump remains anywhere outside our hand,
        // void-ruff risk disappears and established suit winners run freely.
        let trumpExhausted = !remainingCards.contains { $0.suit == trumpRaw }
        // Trump pull: count established non-trump winners (no higher card remains, suit length >= 2).
        // When the bidding team holds 2+ such winners and is in the first 4 tricks, add a bonus to
        // trump leads so bots clear opponents' ruffs before cashing those winners.
        let establishedNonTrumpWinners = hand.filter { card in
            guard card.suit != trumpRaw else { return false }
            let higher = remainingCards.filter {
                $0.suit == card.suit && rankScore($0) > rankScore(card)
            }.count
            return higher == 0 && hand.filter { $0.suit == card.suit }.count >= 2
        }.count
        let trumpPullBonus = isKnownOffense
            && !trumpExhausted
            && urgency.tricksRemaining >= 5
            && establishedNonTrumpWinners >= 2
            ? establishedNonTrumpWinners * 10 : 0
        let scored = hand.map { card -> (Card, Int) in
            let isTrump = card.suit == trumpRaw
            let higherRemaining = remainingCards.filter {
                $0.suit == card.suit && rankScore($0) > rankScore(card)
            }.count
            let higherTrumpRemaining = remainingCards.filter {
                $0.suit == trumpRaw && rankScore($0) > rankScore(card)
            }.count
            let futureVoidRisk: Int
            if let model = handModel {
                // Probabilistic void risk: confirmed voids (prob≈1.0) count fully;
                // probable voids (0.3–0.7) count as 0.5; unlikely voids ignored.
                let weighted = (0..<6).filter { p in
                    strategicOffenseSet.contains(p) != isKnownOffense
                }.reduce(0.0) { risk, p in
                    let vp = model.voidProb(player: p, suit: card.suit)
                    return risk + (vp > 0.7 ? 1.0 : vp > 0.3 ? 0.5 : 0.0)
                }
                futureVoidRisk = Int(weighted.rounded())
            } else {
                futureVoidRisk = (0..<6).filter {
                    strategicOffenseSet.contains($0) != isKnownOffense
                        && knownVoids[$0]?.contains(card.suit) == true
                }.count
            }

            var score = rankScore(card) + card.pointValue
            if isTrump {
                // Dynamic personality: urgency boosts trump-lead aggression (+8)
                // so bots pull trump more assertively when behind.
                let dynamicTrumpBias = personality.leadTrumpBias + (urgency.eitherSide ? 8 : 0)
                score += dynamicTrumpBias
                if rankScore(card) >= personality.trumpLeadFloor { score += 18 }
                if seat == highBidderIndex || personality == .trumpController { score += 10 }
                if higherTrumpRemaining == 0 { score += 10 }
                if higherTrumpRemaining >= 3 { score -= higherTrumpRemaining * 4 }
                if isKnownOffense && urgency.bidSecure && higherTrumpRemaining >= 2 { score -= 12 }
                if !isKnownOffense && !urgency.defense { score -= 8 }
                // Sacrifice / 3♠ reservation: don't eagerly draw trump when the 3♠
                // is still unplayed and game is not yet urgent — save trump to intercept it.
                if threeSpadeStillOut && card.rank != "A" && !urgency.eitherSide {
                    score -= 8
                }
                score += trumpPullBonus
            } else {
                // Partner-adjusted higher-remaining penalty: offense leading into a suit
                // where the higher cards may be in partner's hand is much less risky
                // than leading into opponent strength — halve the penalty for offense.
                let higherPenaltyFactor = isKnownOffense ? 1 : 3
                score += higherRemaining == 0 ? 18 : -(higherRemaining * higherPenaltyFactor)
                // Finessing: if the nearest opponent (1–3 seats after us) probably holds a
                // beating card, leading into them is risky; if they almost certainly don't,
                // the lead is safer than raw higherRemaining suggests.
                if higherRemaining > 0, let model = handModel {
                    let nextOpponent = (1...3).lazy.compactMap { offset -> Int? in
                        let p = (seat + offset) % 6
                        guard strategicOffenseSet.contains(p) != isKnownOffense else { return nil }
                        return p
                    }.first
                    if let opp = nextOpponent {
                        let threatP = model.threatProb(player: opp, suit: card.suit,
                                                       beatingRankScore: rankScore(card))
                        if threatP > 0.5 { score -= 8 }
                        else if threatP < 0.15 { score += 5 }
                    }
                }
                // Long suit establishment: if we hold more cards in this suit than higher cards
                // remaining, leading it repeatedly exhausts blockers and turns lower cards into winners.
                let suitLength = hand.filter { $0.suit == card.suit }.count
                if higherRemaining > 0 {
                    let establishmentPotential = suitLength - higherRemaining
                    if establishmentPotential > 0 && urgency.tricksRemaining >= higherRemaining + 1 {
                        score += establishmentPotential * 6
                    }
                }
                // Trump exhaustion: if no trump remains elsewhere, void-ruff risk is zero;
                // also add a bonus for sure winners that can now safely run.
                let voidRiskMultiplier = trumpExhausted ? 0 : 10
                score -= futureVoidRisk * voidRiskMultiplier
                if trumpExhausted && higherRemaining == 0 { score += 15 }
                if isKnownOffense && urgency.offense { score += card.pointValue * 3 }
                if !isKnownOffense && urgency.defense { score += card.pointValue * 2 }
                if seat == highBidderIndex,
                   revealedPartnerCount < 2,
                   unrevealedCalledSuits.contains(card.suit) {
                    score += 24 - card.pointValue
                    if urgency.offense { score += 12 }
                }
                // Post-reveal coordination: bidder leads toward suit where revealed partners
                // hold more cards than random chance would predict. Uses above-baseline
                // excess to avoid boosting uniformly distributed suits. Up to +16.
                if seat == highBidderIndex,
                   !revealedPartnerIndices.isEmpty,
                   let model = handModel,
                   !isTrump {
                    let suitRemaining = Double(remainingCards.filter { $0.suit == card.suit }.count)
                    let baseline = suitRemaining / 5.0  // expected cards per player, uniform distribution
                    let partnerStrength = revealedPartnerIndices.reduce(0.0) { best, p in
                        let above = max(0.0, model.threatProb(player: p, suit: card.suit,
                                                              beatingRankScore: -1) - baseline)
                        return max(best, above)
                    }
                    score += Int(partnerStrength * 16)
                }
                score += personality.pointFeedBias

                // 3♠ protection: rank "3" loses to almost every other card, so leading
                // the unprotected 3♠ (when not trump) is very risky — opponents who are
                // void in spades can trump it for 30 points at no cost.
                if card.id == "3♠" {
                    let canBeBeaten = remainingCards.contains {
                        $0.suit == card.suit && rankScore($0) > rankScore(card)
                    }
                    if canBeBeaten { score -= 28 }
                }

                // Defense calling-suit targeting: lead a called suit to force the
                // hidden partner to either play the called card (revealing themselves)
                // or follow with a non-called card (narrowing the field).
                // Bidder's equivalent logic is the `seat == highBidderIndex` block above.
                if !isKnownOffense,
                   seat != highBidderIndex,
                   revealedPartnerCount < 2,
                   unrevealedCalledSuits.contains(card.suit) {
                    score += 12 * (2 - revealedPartnerCount) // +24 both hidden, +12 one hidden
                }
            }
            // Defense point denial: aggressively lead confirmed winners to accumulate
            // trick points before offense reaches their bid.
            if !isKnownOffense && urgency.bidderCloseToWin {
                if !isTrump && higherRemaining == 0 { score += 20 }
                if isTrump && higherTrumpRemaining == 0 { score += 15 }
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
        knownVoids: [Int: Set<String>],
        handModel: HandModel
    ) -> Int {
        let futureOpponents = futureSeats.filter { strategicOffenseSet.contains($0) != isKnownOffense }
        guard !futureOpponents.isEmpty else { return 0 }

        let winnerRank = rankScore(winnerCard)
        return futureOpponents.reduce(0) { risk, player in
            let p: Double
            if winnerCard.suit == trumpRaw {
                // Prob this player holds a higher trump.
                p = handModel.threatProb(player: player, suit: trumpRaw,
                                         beatingRankScore: winnerRank)
            } else {
                // Prob they hold a higher card in led suit, or are void and hold trump.
                let ledThreat = handModel.threatProb(player: player, suit: ledSuit,
                                                     beatingRankScore: winnerRank)
                let ruffThreat = handModel.voidProb(player: player, suit: ledSuit)
                    * handModel.threatProb(player: player, suit: trumpRaw, beatingRankScore: -1)
                p = max(ledThreat, ruffThreat)
            }
            return risk + (p > 0.5 ? 2 : p > 0.2 ? 1 : 0)
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

    /// Signal-aware discard scoring: prefers discarding from suits the bot cannot establish
    /// (implicit "don't lead this back" signal), while strongly protecting point cards.
    /// Higher score = better discard candidate.
    private static func discardPreference(
        _ card: Card, hand: [Card], remainingCards: [Card]
    ) -> Int {
        let suitCards = hand.filter { $0.suit == card.suit }
        let higherOut = remainingCards.filter {
            $0.suit == card.suit && rankScore($0) > rankScore(card)
        }.count
        let canEstablish = higherOut < suitCards.count
        var score = 0
        if !canEstablish { score += 10 }   // can't win this suit — safe to abandon
        if card.pointValue > 0 { score -= 20 }  // never discard point card if avoidable
        score -= card.pointValue
        score -= rankScore(card)
        return score
    }

    private static func rankScore(_ card: Card) -> Int {
        Card.rankOrder[card.rank] ?? 0
    }

    private static func valueScore(_ card: Card, personality: BotPersonality) -> Int {
        let feedBonus = personality == .pointFeeder ? card.pointValue * 20 : 0
        return card.pointValue * 100 + rankScore(card) + feedBonus
    }

    // MARK: - Endgame Exact Calculation

    /// Near-exact lead selection for the final 3 tricks.
    /// Instead of heuristic scoring, determines whether each card is a likely
    /// winner given the known remaining cards, then maximises total points
    /// captured across the 1–3 remaining tricks.
    /// Returns nil when more than 3 tricks remain (fall through to bestLeadCard).
    private static func computeEndgameLead(
        hand: [Card],
        isKnownOffense: Bool,
        trumpRaw: String,
        remainingCards: [Card],
        urgency: Urgency
    ) -> Card? {
        guard hand.count <= 3 else { return nil }

        // A card is a likely winner when led if no remaining card can beat it.
        func likelyWinsAsLead(_ card: Card) -> Bool {
            if card.suit == trumpRaw {
                return !remainingCards.contains { $0.suit == trumpRaw && rankScore($0) > rankScore(card) }
            } else {
                // Non-trump: safe only when no trump remains (can't be ruffed)
                // AND it is the highest remaining card in its suit.
                if remainingCards.contains(where: { $0.suit == trumpRaw }) { return false }
                return !remainingCards.contains { $0.suit == card.suit && rankScore($0) > rankScore(card) }
            }
        }

        let scored = hand.map { card -> (Card, Int) in
            var score = 0
            if likelyWinsAsLead(card) {
                score += card.pointValue * 10 + 50   // strong bonus: winning this trick
                if hand.count == 2 {
                    // existing 2-card sweep bonus (unchanged)
                    if let other = hand.first(where: { $0.id != card.id }),
                       likelyWinsAsLead(other) {
                        score += other.pointValue * 8 + 25
                    }
                } else {
                    // 3-card: project value of the remaining 2-card hand
                    let remaining2 = hand.filter { $0.id != card.id }
                    let wins = remaining2.filter { likelyWinsAsLead($0) }
                    score += wins.map { $0.pointValue * 8 + 20 }.reduce(0, +)
                }
            } else {
                // Leading a loser cedes the trick; prefer the one that costs least
                score -= card.pointValue * 5
                // Higher-rank losers force opponents to spend high cards to beat them
                score += rankScore(card) / 2
            }
            return (card, score)
        }

        return scored.max { $0.1 < $1.1 }?.0
    }
}
