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

// MARK: - Card sorting

extension Array where Element == Card {
    /// Groups cards by suit (♠ ♥ ♦ ♣), then sorts each group highest rank first.
    func sortedBySuit() -> [Card] {
        let suitOrder = ["♠": 0, "♥": 1, "♦": 2, "♣": 3]
        return sorted { lhs, rhs in
            let ls = suitOrder[lhs.suit] ?? 4
            let rs = suitOrder[rhs.suit] ?? 4
            if ls != rs { return ls < rs }
            return (Card.rankOrder[lhs.rank] ?? 0) > (Card.rankOrder[rhs.rank] ?? 0)
        }
    }
}

// MARK: - Phase

enum ComputerGamePhase: Equatable {
    case viewingCards
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
    var humanPlayerIndex: Int { humanPlayerIndices.first ?? 0 }
    var humanName: String
    var humanAvatar: String
    let aiNames: [String]
    let aiAvatars: [String]

    // Multi-human support
    var humanPlayerIndices: [Int] = [0]
    var currentHumanPlayerIndex: Int = 0
    /// Set at init time — true only for Pass & Play games. Never inferred from
    /// humanPlayerIndices.count at runtime to avoid the #2 branch-mismatch bug.
    var isPassAndPlay: Bool = false
    var isPassingDevice: Bool = false
    var passingDeviceToIndex: Int = -1
    private var confirmDeviceContinuation: CheckedContinuation<Void, Never>?

    // All-player names/avatars (used when set, e.g. custom game)
    var _allPlayerNames: [String] = []
    var _allPlayerAvatars: [String] = []

    static var namePool: [String] { Comic.aiNamePool }

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
    var biddingStartPlayerIndex: Int = 0
    var biddingToastMessage: String? = nil
    var bidWinnerInfo: BidWinnerInfo? = nil
    var playerHasPassed: [Bool] = Array(repeating: false, count: 6)
    var humanCanPass: Bool = true

    // MARK: Next-hand confirmation
    var waitingForNextHand: Bool = false
    var lastTrickWinnerIndex: Int = -1
    var lastTrickPoints: Int = 0
    var lastCompletedTrick: [(playerIndex: Int, card: Card)] = []
    private var nextHandContinuation: CheckedContinuation<Void, Never>?
    private var bidWinnerContinuation: CheckedContinuation<Void, Never>?

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
    var partner1Revealed = false
    var partner2Revealed = false
    // Revealed in play order (slot 2 = first reveal, slot 3 = second reveal)
    var revealedPartner1Index: Int? = nil
    var revealedPartner2Index: Int? = nil

    // MARK: Continuations
    private var viewCardsContinuation: CheckedContinuation<Void, Never>?
    private var bidContinuation: CheckedContinuation<Int, Never>?
    private var cardContinuation: CheckedContinuation<Card, Never>?

    /// Set to true by cancelAllContinuationsIfNeeded(); checked after every blocking
    /// await so the game loop exits cleanly instead of processing stale input.
    private(set) var gameLoopCancelled = false
    /// Dummy card used only to unblock cardContinuation on cancellation — never
    /// processed because gameLoopCancelled is checked immediately after the await.
    private static let cancelSentinelCard = Card(rank: "2", suit: "♣")

    // MARK: - Init

    init(humanName: String, humanAvatar: String = "🦁", dealerIndex: Int, roundNumber: Int) {
        self.humanName = humanName
        self.humanAvatar = humanAvatar
        self.dealerIndex = dealerIndex
        self.roundNumber = roundNumber
        // Random unique names & avatars for AI opponents (exclude the human's avatar)
        self.aiNames   = Array(Self.namePool.shuffled().prefix(5))
        self.aiAvatars = Comic.randomAIAvatars(count: 5, excluding: [humanAvatar])
    }

    /// Custom game init — 1–5 human seats share one device; AI auto-fills remaining.
    init(humanSeats: [Int], allNames: [String], allAvatars: [String], dealerIndex: Int, roundNumber: Int) {
        self.humanPlayerIndices = humanSeats
        self.isPassAndPlay = humanSeats.count > 1
        self.currentHumanPlayerIndex = humanSeats.first ?? 0
        self._allPlayerNames = allNames
        self._allPlayerAvatars = allAvatars
        self.dealerIndex = dealerIndex
        self.roundNumber = roundNumber
        let firstHuman = humanSeats.first ?? 0
        self.humanName   = allNames.indices.contains(firstHuman) ? allNames[firstHuman] : "Player"
        self.humanAvatar = allAvatars.indices.contains(firstHuman) ? allAvatars[firstHuman] : "🦁"
        self.aiNames   = []
        self.aiAvatars = []
    }

    func playerAvatar(_ index: Int) -> String {
        if !_allPlayerAvatars.isEmpty { return _allPlayerAvatars.indices.contains(index) ? _allPlayerAvatars[index] : "🦁" }
        return index == humanPlayerIndex ? humanAvatar : aiAvatars[index - 1]
    }

    // MARK: - Deck

    static func freshDeck() -> [Card] {
        ["A", "K", "Q", "J", "10", "9", "8", "7", "6", "5", "4", "3"]
            .flatMap { r in ["♠", "♥", "♦", "♣"].map { s in Card(rank: r, suit: s) } }
    }

    func deal() {
        cancelAllContinuationsIfNeeded()
        gameLoopCancelled = false       // reset for the new round
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
        partner1Revealed = false
        partner2Revealed = false
        revealedPartner1Index = nil
        revealedPartner2Index = nil
        completedTricks = []
        trickWinners = []
        biddingStartPlayerIndex = 0
        biddingToastMessage = nil
        playerHasPassed = Array(repeating: false, count: 6)
        humanCanPass = true
        waitingForNextHand = false
        lastTrickWinnerIndex = -1
        lastTrickPoints = 0
        lastCompletedTrick = []
        phase = .viewingCards
    }

    func waitForCardViewing() async {
        await withCheckedContinuation { cont in
            viewCardsContinuation = cont
        }
        // Guard is checked by startBiddingPhase() at its own entry point.
    }

    func humanReadyToBid() {
        viewCardsContinuation?.resume()
        viewCardsContinuation = nil
    }

    // MARK: - Bidding Phase

    func startBiddingPhase() async {
        guard !gameLoopCancelled else { return }
        phase = .bidding
        playerHasPassed = Array(repeating: false, count: 6)

        let startPlayer = Int.random(in: 0..<6)
        biddingStartPlayerIndex = startPlayer

        biddingToastMessage = "\(playerName(startPlayer)) starts the bid!"
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        biddingToastMessage = nil

        var currentPlayer = startPlayer
        var isVeryFirstBid = true

        // Cycle through active players until only one hasn't passed
        while playerHasPassed.filter({ !$0 }).count > 1 {
            if playerHasPassed[currentPlayer] {
                currentPlayer = (currentPlayer + 1) % 6
                continue
            }

            currentBidTurn = currentPlayer
            // Starting player must bid on their very first turn
            let canPassThisTurn = !isVeryFirstBid
            humanCanPass = canPassThisTurn

            if humanPlayerIndices.contains(currentPlayer) {
                // Pass device if this isn't the currently active human
                if currentPlayer != currentHumanPlayerIndex {
                    passingDeviceToIndex = currentPlayer
                    isPassingDevice = true
                    await withCheckedContinuation { cont in confirmDeviceContinuation = cont }
                    currentHumanPlayerIndex = currentPlayer
                    isPassingDevice = false
                }
                humanMinBid = max(130, highBid + 5)
                humanBidAmount = Double(humanMinBid)
                phase = .humanBidding

                let amount = await withCheckedContinuation { cont in
                    bidContinuation = cont
                }
                guard !gameLoopCancelled else { return }
                bids[currentPlayer] = amount
                bidHistory.append((playerIndex: currentPlayer, amount: amount))
                bidHistory = latestBidPerPlayer(bidHistory)
                if amount > 0 {
                    if amount > highBid { highBid = amount; highBidderIndex = currentPlayer }
                    message = "\(playerName(currentPlayer)) bid \(amount)"
                } else {
                    playerHasPassed[currentPlayer] = true
                    message = "\(playerName(currentPlayer)) passed"
                }
                phase = .bidding
            } else {
                try? await Task.sleep(nanoseconds: 700_000_000)
                let amount = aiBidAmount(for: currentPlayer, canPass: canPassThisTurn)
                bids[currentPlayer] = amount
                bidHistory.append((playerIndex: currentPlayer, amount: amount))
                bidHistory = latestBidPerPlayer(bidHistory)
                if amount > 0 {
                    if amount > highBid { highBid = amount; highBidderIndex = currentPlayer }
                    message = "\(playerName(currentPlayer)) bid \(amount)"
                } else {
                    playerHasPassed[currentPlayer] = true
                    message = "\(playerName(currentPlayer)) passed"
                }
            }

            isVeryFirstBid = false
            currentPlayer = (currentPlayer + 1) % 6
        }

        // Fallback: all passed somehow — dealer forced to 130
        if highBidderIndex == -1 {
            highBidderIndex = dealerIndex
            highBid = 130
            bids[dealerIndex] = 130
            bidHistory.append((playerIndex: dealerIndex, amount: 130))
            bidHistory = latestBidPerPlayer(bidHistory)
            message = "\(playerName(dealerIndex)) is forced to bid 130"
            try? await Task.sleep(nanoseconds: 500_000_000)
        } else {
            bidWinnerInfo = BidWinnerInfo(name: playerName(highBidderIndex),
                                          avatar: playerAvatar(highBidderIndex),
                                          bid: highBid)
            if humanPlayerIndices.contains(highBidderIndex) {
                // Human winner — wait until they tap Continue
                await withCheckedContinuation { cont in bidWinnerContinuation = cont }
                guard !gameLoopCancelled else { return }
            } else {
                // AI winner — auto-proceed after 1.5 seconds
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            bidWinnerInfo = nil
        }

        if humanPlayerIndices.contains(highBidderIndex) {
            currentHumanPlayerIndex = highBidderIndex
            setSmartCallingDefaults()
            phase = .callingCards
        } else {
            phase = .aiCalling
            await resolveAiCalling()
        }
    }

    /// Returns bid history keeping one entry per player in first-appearance order,
    /// using each player's LATEST bid amount (not their first).
    private func latestBidPerPlayer(
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

    func humanBid(_ amount: Int) {
        bidContinuation?.resume(returning: amount)
        bidContinuation = nil
    }

    func humanPass() {
        bidContinuation?.resume(returning: 0)
        bidContinuation = nil
    }

    func proceedFromBidWinner() {
        bidWinnerContinuation?.resume()
        bidWinnerContinuation = nil
    }

    // MARK: - Smart Calling Defaults

    private func setSmartCallingDefaults() {
        let hand = hands[highBidderIndex]

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

    private func aiBidAmount(for playerIndex: Int, canPass: Bool = true) -> Int {
        let hand = hands[playerIndex]
        let myPoints = hand.map(\.pointValue).reduce(0, +)

        // Best 2 callable cards outside this hand
        let myIds = Set(hand.map(\.id))
        let topExternal = Self.freshDeck()
            .filter { !myIds.contains($0.id) }
            .sorted { lhs, rhs in
                lhs.pointValue != rhs.pointValue
                    ? lhs.pointValue > rhs.pointValue
                    : (Card.rankOrder[lhs.rank] ?? 0) > (Card.rankOrder[rhs.rank] ?? 0)
            }
        let call1Pts = topExternal.first?.pointValue ?? 0
        let call2Pts = topExternal.dropFirst().first?.pointValue ?? 0

        // Phase 1a — Position-aware partner bonus.
        // Early bidders have less information and should be conservative;
        // late bidders have seen more passes/bids and can estimate their hand's value better.
        // Position: 1 = first after dealer, 5 = last before dealer wraps, 0 = dealer (forced).
        let position = (playerIndex - dealerIndex + 6) % 6
        let bonusFraction: Double
        switch position {
        case 1, 2: bonusFraction = 0.25   // early — conservative, limited info
        case 3:    bonusFraction = 0.33   // middle
        case 4, 5: bonusFraction = 0.42   // late — most info, bid more aggressively
        default:   bonusFraction = 0.38   // dealer (position 0) — forced at 130 if all pass
        }
        let remaining = max(0, 250 - myPoints - call1Pts - call2Pts)
        let partnerBonus = Int(Double(remaining) * bonusFraction)

        // Phase 1b — Suit-clustering bonus.
        // A hand with A+K or A+Q in the same suit is structurally stronger than
        // equal-point hands with scattered low cards. Reward high-card clustering.
        var clusterBonus = 0
        for suit in TrumpSuit.allCases {
            let suitCards = hand.filter { $0.suit == suit.rawValue }
            guard suitCards.count >= 2 else { continue }
            let sortedRanks = suitCards.compactMap { Card.rankOrder[$0.rank] }.sorted(by: >)
            // Both top-2 cards must be Queen or higher (rank >= 10)
            if let top = sortedRanks.first, let second = sortedRanks.dropFirst().first,
               top >= 10 && second >= 10 {
                clusterBonus += suitCards.count * 4
            }
        }

        // Phase 1c — Shortness penalty.
        // 3+ singleton/void suits means you'll be weak in most suits and
        // highly dependent on partners for coverage.
        let thinSuits = TrumpSuit.allCases.filter { suit in
            hand.filter { $0.suit == suit.rawValue }.count <= 1
        }.count
        let shortnessPenalty = max(0, thinSuits - 2) * 8

        let estimated = myPoints + call1Pts + call2Pts + partnerBonus + clusterBonus - shortnessPenalty
        let minBid = max(130, highBid + 5)

        if !canPass {
            let rounded = (max(estimated, minBid) / 5) * 5
            return min(max(rounded, minBid), 250)
        }

        guard estimated >= minBid else { return 0 }
        let rounded = (estimated / 5) * 5
        return min(max(rounded, minBid), 250)
    }

    // MARK: - AI Calling

    private func resolveAiCalling() async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        // RC-C fix: guard after sleep so a quit/new-round during the 1s delay
        // does not continue into stale state. startPlayingPhase() already guards
        // at its own entry, but stopping here is cleaner.
        guard !gameLoopCancelled else { return }

        let hand = hands[highBidderIndex]
        let bidderIds = Set(hand.map(\.id))

        // Phase 2a — Tier-based trump selection.
        // Points alone are insufficient: Q♠ 5♠ 3♠ is risky trump (low cards get overtrumped).
        // Score each suit by points + a tier bonus for high-card backing + card count.
        func trumpTier(_ suit: TrumpSuit) -> Int {
            let topRank = hand.filter { $0.suit == suit.rawValue }
                .compactMap { Card.rankOrder[$0.rank] }.max() ?? 0
            if topRank >= 12 { return 3 }   // Ace — safest trump
            if topRank >= 11 { return 2 }   // King
            if topRank >= 10 { return 1 }   // Queen — acceptable
            return 0                         // J or below — risky, avoid
        }
        let suitRankings = TrumpSuit.allCases.map { suit -> (TrumpSuit, Int) in
            let pts   = hand.filter { $0.suit == suit.rawValue }.map(\.pointValue).reduce(0, +)
            let count = hand.filter { $0.suit == suit.rawValue }.count
            return (suit, pts + trumpTier(suit) * 15 + count * 2)
        }
        trumpSuit = suitRankings.max(by: { $0.1 < $1.1 })?.0 ?? .spades

        // Phase 2b — Void-feeding called cards.
        // If the bidder is void in a suit, calling a high card in that suit means a partner
        // holds it and can feed the bidder that suit (bidder can always trump or discard).
        // Diversify across suits so both called cards don't come from the same suit.
        let candidates = Self.freshDeck()
            .filter { !bidderIds.contains($0.id) }
            .sorted { lhs, rhs in
                lhs.pointValue != rhs.pointValue
                    ? lhs.pointValue > rhs.pointValue
                    : (Card.rankOrder[lhs.rank] ?? 0) > (Card.rankOrder[rhs.rank] ?? 0)
            }

        let voidSuits = TrumpSuit.allCases.filter { suit in
            suit != trumpSuit && hand.filter { $0.suit == suit.rawValue }.isEmpty
        }
        let shortSuits = TrumpSuit.allCases.filter { suit in
            suit != trumpSuit && hand.filter { $0.suit == suit.rawValue }.count == 1
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

        // Pick c1 and c2 from different suits when possible
        let c1 = ordered.first
        let c2 = ordered.first(where: { $0.suit != c1?.suit }) ?? ordered.dropFirst().first

        if let card1 = c1, let card2 = c2 {
            calledCard1Rank = card1.rank; calledCard1Suit = card1.suit
            calledCard2Rank = card2.rank; calledCard2Suit = card2.suit
        } else if let card1 = c1 {
            calledCard1Rank = card1.rank; calledCard1Suit = card1.suit
            if ordered.count > 1 {
                calledCard2Rank = ordered[1].rank; calledCard2Suit = ordered[1].suit
            }
        }

        resolvePartners()
        await startPlayingPhase()
    }

    // MARK: - Human Calling

    var calledCard1: String { calledCard1Rank + calledCard1Suit }
    var calledCard2: String { calledCard2Rank + calledCard2Suit }

    var callingValid: Bool {
        guard calledCard1 != calledCard2 else { return false }
        let bidderIds = Set(hands[highBidderIndex].map(\.id))
        return !bidderIds.contains(calledCard1) && !bidderIds.contains(calledCard2)
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
        guard !gameLoopCancelled else { return }
        phase = .playing
        currentLeaderIndex = highBidderIndex

        for _ in 0..<8 {
            let order = (0..<6).map { (currentLeaderIndex + $0) % 6 }

            for playerIndex in order {
                if humanPlayerIndices.contains(playerIndex) {
                    // Pass device if this isn't the currently active human
                    if playerIndex != currentHumanPlayerIndex {
                        passingDeviceToIndex = playerIndex
                        isPassingDevice = true
                        await withCheckedContinuation { cont in confirmDeviceContinuation = cont }
                        guard !gameLoopCancelled else { return }
                        currentHumanPlayerIndex = playerIndex
                        isPassingDevice = false
                    }
                    phase = .humanPlaying
                    message = "Your turn — tap a card to play"

                    let card = await withCheckedContinuation { cont in
                        cardContinuation = cont
                    }
                    guard !gameLoopCancelled else { return }
                    hands[playerIndex].removeAll { $0.id == card.id }
                    currentTrick.append((playerIndex: playerIndex, card: card))
                    checkPartnerReveal(card: card, playerIndex: playerIndex)
                    phase = .playing

                } else {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    // Fix 5: guard after AI-turn sleep so a cancellation during the delay
                    // exits cleanly instead of continuing into stale game state.
                    guard !gameLoopCancelled else { return }
                    // Fix 1: safety guard — hand should always have cards here; if not,
                    // something corrupted game state. Skip the card rather than inject a phantom.
                    guard !hands[playerIndex].isEmpty else { continue }
                    let card = aiPlayCard(playerIndex: playerIndex)
                    hands[playerIndex].removeAll { $0.id == card.id }
                    currentTrick.append((playerIndex: playerIndex, card: card))
                    checkPartnerReveal(card: card, playerIndex: playerIndex)
                    message = "\(playerName(playerIndex)) played \(card.rank)\(card.suit)"
                }
            }

            // Brief pause so SwiftUI renders the 6th card before resolveTrick() fires.
            // Pass & Play uses 1s (multiple people at the table); solo uses 0.4s.
            if isPassAndPlay {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            } else {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            // Fix 5: guard after post-trick sleep for the same reason.
            guard !gameLoopCancelled else { return }
            resolveTrick()
            await waitForNextHand()
            currentTrick = []
        }

        phase = .roundComplete
    }

    private func waitForNextHand() async {
        lastTrickWinnerIndex = trickWinners.last ?? -1
        lastTrickPoints = completedTricks.last?.map(\.card.pointValue).reduce(0, +) ?? 0
        lastCompletedTrick = completedTricks.last ?? []
        waitingForNextHand = true

        if isPassAndPlay {
            // Pass & Play — auto advance after 5 seconds
            // so all players at the table can see the cards
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            waitingForNextHand = false
        } else {
            // Solo — wait for human to tap Next Hand
            await withCheckedContinuation { cont in
                nextHandContinuation = cont
            }
            guard !gameLoopCancelled else { return }
            waitingForNextHand = false
        }
    }

    func humanReadyForNextHand() {
        nextHandContinuation?.resume()
        nextHandContinuation = nil
    }

    func humanPlayCard(_ card: Card) {
        cardContinuation?.resume(returning: card)
        cardContinuation = nil
    }

    func confirmDevicePass() {
        confirmDeviceContinuation?.resume()
        confirmDeviceContinuation = nil
    }

    /// Resumes any pending device-pass continuation so the game loop unblocks.
    /// Prefer cancelAllContinuationsIfNeeded() for full teardown; this is kept
    /// for callers that only need to unblock the pass-device overlay.
    func cancelDevicePassIfNeeded() {
        guard confirmDeviceContinuation != nil else { return }
        confirmDeviceContinuation?.resume()
        confirmDeviceContinuation = nil
        isPassingDevice = false
    }

    /// Resumes every pending continuation with a sentinel/dummy value so all
    /// blocked async tasks can exit their awaits and hit the gameLoopCancelled
    /// guard, returning cleanly. Call from deal() (new round) and from the
    /// view's onDisappear (quit/navigation away).
    func cancelAllContinuationsIfNeeded() {
        gameLoopCancelled = true
        viewCardsContinuation?.resume();                              viewCardsContinuation = nil
        bidContinuation?.resume(returning: 0);                        bidContinuation = nil
        bidWinnerContinuation?.resume();                              bidWinnerContinuation = nil
        cardContinuation?.resume(returning: Self.cancelSentinelCard); cardContinuation = nil
        nextHandContinuation?.resume();                               nextHandContinuation = nil
        cancelDevicePassIfNeeded()
    }

    private func checkPartnerReveal(card: Card, playerIndex: Int) {
        guard playerIndex != highBidderIndex else { return }

        let isCalledCard1 = card.id == calledCard1
        let isCalledCard2 = card.id == calledCard2
        guard isCalledCard1 || isCalledCard2 else { return }

        // Use the index slots as the single source of truth.
        // Only set each slot once — first come first served in play order.
        // Do NOT use separate boolean flags — they can desync from indices.

        if isCalledCard1 && revealedPartner1Index == nil {
            // Called card 1 played for the first time
            revealedPartner1Index = playerIndex
            partner1Revealed = true
        } else if isCalledCard2 && revealedPartner2Index == nil {
            // Called card 2 played for the first time
            revealedPartner2Index = playerIndex
            partner2Revealed = true
        } else if isCalledCard1 && revealedPartner1Index != nil {
            // Called card 1 already revealed — ignore duplicate
            return
        } else if isCalledCard2 && revealedPartner2Index != nil {
            // Called card 2 already revealed — ignore duplicate
            return
        } else {
            return
        }

        // Show the reveal banner
        let isSelf = humanPlayerIndices.contains(playerIndex)
        partnerRevealMessage = isSelf
            ? "You are a partner!"
            : "\(playerName(playerIndex)) is a partner!"
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            partnerRevealMessage = nil
        }
    }

    // MARK: - AI Card Heuristic (partner-aware)

    private func aiPlayCard(playerIndex: Int) -> Card {
        let hand = hands[playerIndex]
        guard !hand.isEmpty else { return Card(rank: "A", suit: "♠") }

        let isOffense = offenseSet.contains(playerIndex)
        let isBidder  = playerIndex == highBidderIndex
        let trumpRaw  = trumpSuit.rawValue

        func rankScore(_ c: Card) -> Int  { Card.rankOrder[c.rank] ?? 0 }
        func valueScore(_ c: Card) -> Int { c.pointValue * 100 + rankScore(c) }

        // Phase 3 — Deficit tracking.
        // Offense urgency: does offense need more than 60% of remaining points?
        let offensePts = offenseSet.map { wonTricks[$0].map(\.pointValue).reduce(0, +) }.reduce(0, +)
        let totalPts   = wonTricks.flatMap { $0 }.map(\.pointValue).reduce(0, +)
        let remaining  = 250 - totalPts
        let shortfall  = max(0, highBid - offensePts)
        // Urgent = we need a disproportionate share of remaining points
        let isUrgent   = isOffense && remaining > 0 && shortfall * 10 > remaining * 6

        // Phase 4 — Void memory from completed tricks.
        // Any player who didn't follow the led suit is void in that suit.
        // Uses only publicly visible information (all played cards are visible).
        var knownVoids: [Int: Set<String>] = [:]
        for trick in completedTricks {
            guard let ledSuit = trick.first?.card.suit else { continue }
            for entry in trick where entry.card.suit != ledSuit {
                knownVoids[entry.playerIndex, default: []].insert(ledSuit)
            }
        }
        let opponentIndices = (0..<6).filter { isOffense ? !offenseSet.contains($0) : offenseSet.contains($0) }

        // ── LEADING ──────────────────────────────────────────────────────
        if currentTrick.isEmpty {
            let nonTrump = hand.filter { $0.suit != trumpRaw }

            if isBidder {
                // Lead high trump (Q+) to pull opponents' trump — but only when
                // bid is not yet secured OR in early tricks (pull trump early when it counts).
                let bidSecured = offensePts >= highBid
                let trumpCards = hand.filter { $0.suit == trumpRaw }
                if !bidSecured || trickNumber < 3 {
                    if let highTrump = trumpCards.max(by: { rankScore($0) < rankScore($1) }),
                       rankScore(highTrump) >= (Card.rankOrder["Q"] ?? 0) {
                        return highTrump
                    }
                }
            }

            // Phase 3: urgent offense — lead highest-value card to maximise points NOW
            if isUrgent, let best = nonTrump.max(by: { valueScore($0) < valueScore($1) }) {
                return best
            }

            // Phase 4: avoid suits where multiple opponents are void (they'll trump us).
            // Score each non-trump card down by the number of void opponents in that suit.
            let scoredNonTrump = nonTrump.map { card -> (Card, Int) in
                let voidCount = opponentIndices.filter { knownVoids[$0]?.contains(card.suit) == true }.count
                return (card, rankScore(card) + card.pointValue - voidCount * 4)
            }
            if let best = scoredNonTrump.max(by: { $0.1 < $1.1 })?.0 { return best }

            // Fallback: highest non-trump; if only trump left, lowest trump
            if let best = nonTrump.max(by: { rankScore($0) < rankScore($1) }) { return best }
            return hand.min(by: { rankScore($0) < rankScore($1) }) ?? hand[0]
        }

        // ── FOLLOWING ────────────────────────────────────────────────────
        let ledSuit  = currentTrick[0].card.suit
        let sameSuit = hand.filter { $0.suit == ledSuit }
        let winner   = trickWinner(trick: currentTrick)
        let winnerIsOffense = offenseSet.contains(winner.playerIndex)
        let teammateWinning = isOffense ? winnerIsOffense : !winnerIsOffense

        if !sameSuit.isEmpty {
            if teammateWinning {
                // Dump highest-point card of led suit onto teammate's winning trick
                return sameSuit.max(by: { valueScore($0) < valueScore($1) }) ?? sameSuit[0]
            }
            // Opponent winning — try to beat with the lowest card that wins
            if winner.card.suit == ledSuit {
                let canBeat = sameSuit.filter { rankScore($0) > rankScore(winner.card) }
                if let best = canBeat.max(by: { rankScore($0) < rankScore($1) }) { return best }
            }
            // Can't beat — play lowest-value card of suit
            return sameSuit.min(by: { valueScore($0) < valueScore($1) }) ?? sameSuit[0]
        }

        // ── CAN'T FOLLOW ─────────────────────────────────────────────────
        if teammateWinning {
            // Don't waste trump — dump highest-point non-trump instead
            let nonTrump = hand.filter { $0.suit != trumpRaw }
            if let best = nonTrump.max(by: { valueScore($0) < valueScore($1) }) { return best }
        }

        // Opponent winning and we're void in led suit.
        // Phase 3: only trump in if there are points at stake or we're in urgent mode —
        // otherwise conserve trump by discarding a low card instead.
        let trickPoints = currentTrick.map(\.card.pointValue).reduce(0, +)
        let trumpCards  = hand.filter { $0.suit == trumpRaw }
        if !trumpCards.isEmpty && (trickPoints > 0 || isUrgent) {
            return trumpCards.min(by: { rankScore($0) < rankScore($1) }) ?? trumpCards[0]
        }

        // No points at stake — discard lowest-value non-trump to conserve trump
        let nonTrump = hand.filter { $0.suit != trumpRaw }
        if let discard = nonTrump.min(by: { valueScore($0) < valueScore($1) }) { return discard }
        // Only trump left — play lowest
        return trumpCards.min(by: { rankScore($0) < rankScore($1) }) ?? hand[0]
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
        message = "\(playerName(winner.playerIndex)) wins the hand!"
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

    /// Index of the player currently winning the in-progress trick, or nil if no trick is active.
    var currentTrickWinnerIndex: Int? {
        guard !currentTrick.isEmpty else { return nil }
        return trickWinner(trick: currentTrick).playerIndex
    }

    var humanHand: [Card] { hands[currentHumanPlayerIndex] }

    func validCardsToPlay() -> Set<String> {
        let hand = hands[currentHumanPlayerIndex]
        if currentTrick.isEmpty { return Set(hand.map(\.id)) }
        let ledSuit = currentTrick[0].card.suit
        let canFollow = hand.filter { $0.suit == ledSuit }
        return Set((canFollow.isEmpty ? hand : canFollow).map(\.id))
    }

    // MARK: - Helper

    func playerName(_ index: Int) -> String {
        if !_allPlayerNames.isEmpty { return _allPlayerNames.indices.contains(index) ? _allPlayerNames[index] : "Guest \(index+1)" }
        return index == humanPlayerIndex ? humanName : aiNames[index - 1]
    }
}
