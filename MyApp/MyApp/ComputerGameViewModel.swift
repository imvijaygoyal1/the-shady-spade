import SwiftUI
import Observation

// MARK: - Card

struct Card: Identifiable, Hashable {
    let rank: String   // "A","K","Q","J","10","9","8","7","6","5","4","3"
    let suit: String   // "♠","♥","♦","♣"
    var id: String { rank + suit }

    var pointValue: Int {
        if rank == "3" && suit == "♠" { return 30 }
        switch rank {
        case "A", "K", "Q", "J", "10": return 10
        case "5": return 5
        default: return 0
        }
    }

    static let rankOrder: [String: Int] = [
        "A": 12, "K": 11, "Q": 10, "J": 9, "10": 8,
        "9": 7,  "8": 6,  "7": 5,  "6": 4, "5": 3, "4": 2, "3": 1
    ]
}

// MARK: - Phase

enum ComputerGamePhase: Equatable {
    case bidding
    case humanBidding
    case callingCards
    case aiCalling
    case playing
    case humanPlaying
    case roundComplete
}

// MARK: - ViewModel

@MainActor
@Observable
final class ComputerGameViewModel {

    // MARK: Players
    let humanPlayerIndex = 0
    var humanName: String
    let aiNames = ["CPU 1", "CPU 2", "CPU 3", "CPU 4", "CPU 5"]

    // MARK: Hands & Phase
    var hands: [[Card]] = Array(repeating: [], count: 6)
    var phase: ComputerGamePhase = .bidding
    var dealerIndex: Int
    var roundNumber: Int

    // MARK: Bidding
    var bids: [Int] = Array(repeating: -1, count: 6)  // -1=pending, 0=pass
    var currentBidTurn: Int = 0
    var highBid: Int = 0
    var highBidderIndex: Int = -1
    var bidHistory: [(playerIndex: Int, amount: Int)] = []
    var humanMinBid: Int = 130
    var humanBidAmount: Double = 130
    var humanMustPass: Bool { humanMinBid > 250 }

    // MARK: Post-bid
    var trumpSuit: TrumpSuit = .spades
    var calledCard1Rank = "A"
    var calledCard1Suit = "♥"
    var calledCard2Rank = "K"
    var calledCard2Suit = "♦"
    var partner1Index: Int? = nil
    var partner2Index: Int? = nil

    // MARK: Playing
    var currentTrick: [(playerIndex: Int, card: Card)] = []
    var currentLeaderIndex: Int = 0
    var trickNumber: Int = 0
    var wonTricks: [[Card]] = Array(repeating: [], count: 6)
    var completedTricks: [[(playerIndex: Int, card: Card)]] = []
    var trickWinners: [Int] = []

    // MARK: UI
    var message: String = ""
    var partnerRevealMessage: String? = nil
    private var revealedCard1 = false
    private var revealedCard2 = false

    // MARK: Continuations
    private var bidContinuation: CheckedContinuation<Int, Never>?
    private var cardContinuation: CheckedContinuation<Card, Never>?

    // MARK: - Init

    init(humanName: String, dealerIndex: Int, roundNumber: Int) {
        self.humanName = humanName
        self.dealerIndex = dealerIndex
        self.roundNumber = roundNumber
    }

    // MARK: - Deck

    static func freshDeck() -> [Card] {
        ["A", "K", "Q", "J", "10", "9", "8", "7", "6", "5", "4", "3"]
            .flatMap { r in ["♠", "♥", "♦", "♣"].map { s in Card(rank: r, suit: s) } }
    }

    func deal() {
        let deck = Self.freshDeck().shuffled()
        hands = (0..<6).map { i in Array(deck[(i * 8)..<((i + 1) * 8)]) }
        bids = Array(repeating: -1, count: 6)
        bidHistory = []
        currentTrick = []
        trickNumber = 0
        wonTricks = Array(repeating: [], count: 6)
        highBid = 0
        highBidderIndex = -1
        partner1Index = nil
        partner2Index = nil
        message = ""
        partnerRevealMessage = nil
        revealedCard1 = false
        revealedCard2 = false
        completedTricks = []
        trickWinners = []
    }

    // MARK: - Bidding Phase

    func startBiddingPhase() async {
        phase = .bidding
        let order = (1...6).map { (dealerIndex + $0) % 6 }

        for playerIndex in order {
            currentBidTurn = playerIndex

            if playerIndex == humanPlayerIndex {
                humanMinBid = max(130, highBid + 5)
                humanBidAmount = Double(humanMinBid)
                phase = .humanBidding

                let amount = await withCheckedContinuation { cont in
                    bidContinuation = cont
                }
                bids[playerIndex] = amount
                bidHistory.append((playerIndex: playerIndex, amount: amount))
                if amount > 0 {
                    if amount > highBid { highBid = amount; highBidderIndex = playerIndex }
                    message = "\(humanName) bid \(amount)"
                } else {
                    message = "\(humanName) passed"
                }
                phase = .bidding

            } else {
                try? await Task.sleep(nanoseconds: 700_000_000)
                let amount = aiBidAmount(for: playerIndex)
                bids[playerIndex] = amount
                bidHistory.append((playerIndex: playerIndex, amount: amount))
                if amount > 0 {
                    if amount > highBid { highBid = amount; highBidderIndex = playerIndex }
                    message = "\(playerName(playerIndex)) bid \(amount)"
                } else {
                    message = "\(playerName(playerIndex)) passed"
                }
            }
        }

        // All passed → dealer forced to 130
        if highBidderIndex == -1 {
            highBidderIndex = dealerIndex
            highBid = 130
            bids[dealerIndex] = 130
            bidHistory.append((playerIndex: dealerIndex, amount: 130))
            message = "\(playerName(dealerIndex)) is forced to bid 130"
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        if highBidderIndex == humanPlayerIndex {
            setSmartCallingDefaults()
            phase = .callingCards
        } else {
            phase = .aiCalling
            await resolveAiCalling()
        }
    }

    func humanBid(_ amount: Int) {
        bidContinuation?.resume(returning: amount)
        bidContinuation = nil
    }

    func humanPass() {
        bidContinuation?.resume(returning: 0)
        bidContinuation = nil
    }

    // MARK: - Smart Calling Defaults

    private func setSmartCallingDefaults() {
        let hand = hands[humanPlayerIndex]

        // Trump: suit with highest point value in hand
        let suitScores = TrumpSuit.allCases.map { suit -> (TrumpSuit, Int) in
            let pts = hand.filter { $0.suit == suit.rawValue }.map(\.pointValue).reduce(0, +)
            return (suit, pts)
        }
        trumpSuit = suitScores.max(by: { $0.1 < $1.1 })?.0 ?? .spades

        // Called cards: 2 highest-value cards not in hand
        let humanIds = Set(hand.map(\.id))
        let candidates = Self.freshDeck()
            .filter { !humanIds.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.pointValue != rhs.pointValue { return lhs.pointValue > rhs.pointValue }
                return (Card.rankOrder[lhs.rank] ?? 0) > (Card.rankOrder[rhs.rank] ?? 0)
            }
        if candidates.count >= 2 {
            calledCard1Rank = candidates[0].rank
            calledCard1Suit = candidates[0].suit
            calledCard2Rank = candidates[1].rank
            calledCard2Suit = candidates[1].suit
        }
    }

    // MARK: - AI Bid Heuristic

    private func aiBidAmount(for playerIndex: Int) -> Int {
        let handPoints = hands[playerIndex].map(\.pointValue).reduce(0, +)
        let minBid = max(130, highBid + 5)
        guard handPoints >= minBid else { return 0 }
        return min(handPoints, 250)
    }

    // MARK: - AI Calling

    private func resolveAiCalling() async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let hand = hands[highBidderIndex]

        // Trump = suit with most point value in bidder's hand
        let suitScores = TrumpSuit.allCases.map { suit -> (TrumpSuit, Int) in
            let pts = hand.filter { $0.suit == suit.rawValue }.map(\.pointValue).reduce(0, +)
            return (suit, pts)
        }
        trumpSuit = suitScores.max(by: { $0.1 < $1.1 })?.0 ?? .spades

        // Call 2 highest-value cards NOT in bidder's hand
        let bidderIds = Set(hand.map(\.id))
        let candidates = Self.freshDeck()
            .filter { !bidderIds.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.pointValue != rhs.pointValue { return lhs.pointValue > rhs.pointValue }
                return (Card.rankOrder[lhs.rank] ?? 0) > (Card.rankOrder[rhs.rank] ?? 0)
            }

        if candidates.count >= 2 {
            calledCard1Rank = candidates[0].rank
            calledCard1Suit = candidates[0].suit
            calledCard2Rank = candidates[1].rank
            calledCard2Suit = candidates[1].suit
        }

        resolvePartners()
        await startPlayingPhase()
    }

    // MARK: - Human Calling

    var calledCard1: String { calledCard1Rank + calledCard1Suit }
    var calledCard2: String { calledCard2Rank + calledCard2Suit }

    var callingValid: Bool {
        guard calledCard1 != calledCard2 else { return false }
        let humanIds = Set(hands[humanPlayerIndex].map(\.id))
        return !humanIds.contains(calledCard1) && !humanIds.contains(calledCard2)
    }

    func humanConfirmCalling() {
        resolvePartners()
        Task { await startPlayingPhase() }
    }

    // MARK: - Resolve Partners

    private func resolvePartners() {
        partner1Index = nil
        partner2Index = nil
        for (i, hand) in hands.enumerated() where i != highBidderIndex {
            if hand.contains(where: { $0.id == calledCard1 }) { partner1Index = i }
            if hand.contains(where: { $0.id == calledCard2 }) { partner2Index = i }
        }
    }

    // MARK: - Playing Phase

    func startPlayingPhase() async {
        phase = .playing
        currentLeaderIndex = (dealerIndex + 1) % 6

        for _ in 0..<8 {
            currentTrick = []
            let order = (0..<6).map { (currentLeaderIndex + $0) % 6 }

            for playerIndex in order {
                if playerIndex == humanPlayerIndex {
                    phase = .humanPlaying
                    message = "Your turn — tap a card to play"

                    let card = await withCheckedContinuation { cont in
                        cardContinuation = cont
                    }
                    hands[humanPlayerIndex].removeAll { $0.id == card.id }
                    currentTrick.append((playerIndex: playerIndex, card: card))
                    checkPartnerReveal(card: card, playerIndex: playerIndex)
                    phase = .playing

                } else {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    let card = aiPlayCard(playerIndex: playerIndex)
                    hands[playerIndex].removeAll { $0.id == card.id }
                    currentTrick.append((playerIndex: playerIndex, card: card))
                    checkPartnerReveal(card: card, playerIndex: playerIndex)
                    message = "\(playerName(playerIndex)) played \(card.rank)\(card.suit)"
                }
            }

            resolveTrick()
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        phase = .roundComplete
    }

    func humanPlayCard(_ card: Card) {
        cardContinuation?.resume(returning: card)
        cardContinuation = nil
    }

    private func checkPartnerReveal(card: Card, playerIndex: Int) {
        guard playerIndex != highBidderIndex else { return }
        let isSelf = playerIndex == humanPlayerIndex
        if !revealedCard1 && card.id == calledCard1 {
            revealedCard1 = true
            partnerRevealMessage = isSelf ? "You are a partner!" : "\(playerName(playerIndex)) is a partner!"
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                partnerRevealMessage = nil
            }
        } else if !revealedCard2 && card.id == calledCard2 {
            revealedCard2 = true
            partnerRevealMessage = isSelf ? "You are a partner!" : "\(playerName(playerIndex)) is a partner!"
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                partnerRevealMessage = nil
            }
        }
    }

    // MARK: - AI Card Heuristic (partner-aware)

    private func aiPlayCard(playerIndex: Int) -> Card {
        let hand = hands[playerIndex]
        guard !hand.isEmpty else { return Card(rank: "A", suit: "♠") }

        let isOffense = offenseSet.contains(playerIndex)
        let isBidder  = playerIndex == highBidderIndex

        func rankScore(_ c: Card) -> Int  { Card.rankOrder[c.rank] ?? 0 }
        func valueScore(_ c: Card) -> Int { c.pointValue * 100 + rankScore(c) }

        // ── LEADING ──────────────────────────────────────────────────────
        if currentTrick.isEmpty {
            if isBidder {
                // Bidder leads high trump (Q+) to pull opponents' trump
                let trumpCards = hand.filter { $0.suit == trumpSuit.rawValue }
                if let highTrump = trumpCards.max(by: { rankScore($0) < rankScore($1) }),
                   rankScore(highTrump) >= (Card.rankOrder["Q"] ?? 0) {
                    return highTrump
                }
            }
            // Everyone else: highest non-trump; if only trump left, lowest trump
            let nonTrump = hand.filter { $0.suit != trumpSuit.rawValue }
            if let best = nonTrump.max(by: { rankScore($0) < rankScore($1) }) { return best }
            return hand.min(by: { rankScore($0) < rankScore($1) }) ?? hand[0]
        }

        // ── FOLLOWING ────────────────────────────────────────────────────
        let ledSuit  = currentTrick[0].card.suit
        let samesuit = hand.filter { $0.suit == ledSuit }
        let winner   = trickWinner(trick: currentTrick)
        // True when current trick winner is on the same team as this player
        let winnerIsOffense  = offenseSet.contains(winner.playerIndex)
        let teammateWinning  = isOffense ? winnerIsOffense : !winnerIsOffense

        if !samesuit.isEmpty {
            if teammateWinning {
                // Dump highest-point card of led suit onto teammate's winning trick
                return samesuit.max(by: { valueScore($0) < valueScore($1) }) ?? samesuit[0]
            }
            // Opponent winning — try to beat with lowest winning card
            if winner.card.suit == ledSuit {
                let canBeat = samesuit.filter { rankScore($0) > rankScore(winner.card) }
                if let best = canBeat.max(by: { rankScore($0) < rankScore($1) }) { return best }
            }
            // Can't beat — play lowest-value card of suit
            return samesuit.min(by: { valueScore($0) < valueScore($1) }) ?? samesuit[0]
        }

        // ── CAN'T FOLLOW ─────────────────────────────────────────────────
        if teammateWinning {
            // Don't waste trump — dump highest-point non-trump card instead
            let nonTrump = hand.filter { $0.suit != trumpSuit.rawValue }
            if let best = nonTrump.max(by: { valueScore($0) < valueScore($1) }) { return best }
        }
        // Opponent winning — play lowest trump to take the trick cheaply
        let trumpCards = hand.filter { $0.suit == trumpSuit.rawValue }
        if let lowest = trumpCards.min(by: { rankScore($0) < rankScore($1) }) { return lowest }

        // No trump — discard lowest-value card
        return hand.min(by: { valueScore($0) < valueScore($1) }) ?? hand[0]
    }

    // MARK: - Trick Resolution

    private func trickWinner(trick: [(playerIndex: Int, card: Card)]) -> (playerIndex: Int, card: Card) {
        let ledSuit = trick[0].card.suit
        let trumpPlays = trick.filter { $0.card.suit == trumpSuit.rawValue }
        if !trumpPlays.isEmpty {
            return trumpPlays.max(by: { (Card.rankOrder[$0.card.rank] ?? 0) < (Card.rankOrder[$1.card.rank] ?? 0) })!
        }
        let ledPlays = trick.filter { $0.card.suit == ledSuit }
        return ledPlays.max(by: { (Card.rankOrder[$0.card.rank] ?? 0) < (Card.rankOrder[$1.card.rank] ?? 0) })!
    }

    private func resolveTrick() {
        let winner = trickWinner(trick: currentTrick)
        completedTricks.append(currentTrick)
        trickWinners.append(winner.playerIndex)
        wonTricks[winner.playerIndex].append(contentsOf: currentTrick.map(\.card))
        currentLeaderIndex = winner.playerIndex
        trickNumber += 1
        message = "\(playerName(winner.playerIndex)) wins the trick!"
    }

    // MARK: - Scoring

    var offenseSet: Set<Int> {
        Set([highBidderIndex, partner1Index, partner2Index].compactMap { $0 })
    }

    var offensePoints: Int {
        wonTricks.enumerated()
            .filter { offenseSet.contains($0.offset) }
            .flatMap(\.element)
            .map(\.pointValue)
            .reduce(0, +)
    }

    var defensePoints: Int {
        wonTricks.enumerated()
            .filter { !offenseSet.contains($0.offset) }
            .flatMap(\.element)
            .map(\.pointValue)
            .reduce(0, +)
    }

    // MARK: - Build Round

    func buildRound(nextRoundNumber: Int) -> Round {
        Round(
            roundNumber: nextRoundNumber,
            dealerIndex: dealerIndex,
            bidderIndex: max(0, highBidderIndex),
            bidAmount: max(130, highBid),
            trumpSuit: trumpSuit,
            callCard1: calledCard1,
            callCard2: calledCard2,
            partner1Index: partner1Index ?? 0,
            partner2Index: partner2Index ?? 1,
            offensePointsCaught: offensePoints,
            defensePointsCaught: defensePoints
        )
    }

    // MARK: - Valid Cards

    func validCardsToPlay() -> Set<String> {
        let hand = hands[humanPlayerIndex]
        if currentTrick.isEmpty { return Set(hand.map(\.id)) }
        let ledSuit = currentTrick[0].card.suit
        let canFollow = hand.filter { $0.suit == ledSuit }
        return Set((canFollow.isEmpty ? hand : canFollow).map(\.id))
    }

    // MARK: - Helper

    func playerName(_ index: Int) -> String {
        index == humanPlayerIndex ? humanName : aiNames[index - 1]
    }
}
