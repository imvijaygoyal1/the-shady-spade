import Foundation

enum GameFlowRules {
    static let playerCount = 6
    static let minimumBid = 130
    static let maximumBid = 250
    static let bidStep = 5

    static func firstBidder(afterDealer dealerIndex: Int) -> Int {
        normalizedSeat(dealerIndex + 1)
    }

    static func minimumBid(after highBid: Int) -> Int {
        max(minimumBid, highBid + bidStep)
    }

    static func canPass(highBid: Int) -> Bool {
        highBid > 0
    }

    static func mustPass(highBid: Int) -> Bool {
        minimumBid(after: highBid) > maximumBid
    }

    static func isValidBid(_ amount: Int, highBid: Int) -> Bool {
        amount >= minimumBid(after: highBid) && amount <= maximumBid
    }

    static func nextActivePlayer(after playerIndex: Int, playerHasPassed: [Bool]) -> Int? {
        guard isValidSeat(playerIndex), playerHasPassed.count >= playerCount else { return nil }
        for offset in 1...playerCount {
            let candidate = normalizedSeat(playerIndex + offset)
            if !playerHasPassed[candidate] {
                return candidate
            }
        }
        return nil
    }

    static func activePlayers(playerHasPassed: [Bool]) -> [Int] {
        guard playerHasPassed.count >= playerCount else { return [] }
        return (0..<playerCount).filter { !playerHasPassed[$0] }
    }

    static func offenseSet(bidderIndex: Int, partner1Index: Int, partner2Index: Int) -> Set<Int> {
        Set([bidderIndex, partner1Index, partner2Index].filter(isValidSeat))
    }

    /// Offense seats in the order they are shown: the bidder first, then the
    /// partners as they were called.
    ///
    /// `offenseSet` answers membership and is what the view models use, but a
    /// `Set` has no order, so every game view wrote its own ordered version --
    /// three copies, in two encodings. Solo carries partner seats as `Int?`,
    /// while Online and Bluetooth use `-1` for "not yet revealed", so this
    /// takes optionals and rejects any seat that is not on the table. That
    /// sentinel is what once normalised `-1` into seat 0 and put a defender on
    /// the bidding team.
    static func offenseOrder(bidderIndex: Int?, partner1Index: Int?, partner2Index: Int?) -> [Int] {
        var seen = Set<Int>()
        return [bidderIndex, partner1Index, partner2Index]
            .compactMap { $0 }
            .filter(isValidSeat)
            .filter { seen.insert($0).inserted }
    }

    /// Everyone not on the bidding team, in seat order.
    static func defenseOrder(offense: [Int]) -> [Int] {
        let offenseSeats = Set(offense)
        return (0..<playerCount).filter { !offenseSeats.contains($0) }
    }

    static func pointTotal(for players: Set<Int>, wonPointsPerPlayer: [Int]) -> Int {
        guard wonPointsPerPlayer.count >= playerCount else { return 0 }
        return (0..<playerCount)
            .filter { players.contains($0) }
            .map { wonPointsPerPlayer[$0] }
            .reduce(0, +)
    }

    static func defensePointTotal(offenseSet: Set<Int>, wonPointsPerPlayer: [Int]) -> Int {
        guard wonPointsPerPlayer.count >= playerCount else { return 0 }
        return (0..<playerCount)
            .filter { !offenseSet.contains($0) }
            .map { wonPointsPerPlayer[$0] }
            .reduce(0, +)
    }

    static func validCardsToPlay(hand: [Card], currentTrick: [(playerIndex: Int, card: Card)]) -> Set<String> {
        if currentTrick.isEmpty {
            return Set(hand.map(\.id))
        }
        let ledSuit = currentTrick[0].card.suit
        let followSuitCards = hand.filter { $0.suit == ledSuit }
        return Set((followSuitCards.isEmpty ? hand : followSuitCards).map(\.id))
    }

    static func isValidCalledCards(_ c1: String, _ c2: String, callerHand: [Card]) -> Bool {
        guard c1 != c2 else { return false }
        let validCardIds = Set(AIEngine.fullDeck.map(\.id))
        guard validCardIds.contains(c1), validCardIds.contains(c2) else { return false }
        let handIds = Set(callerHand.map(\.id))
        return !handIds.contains(c1) && !handIds.contains(c2)
    }

    static func resolvePartners(c1: String, c2: String, hands: [[Card]], bidderIndex: Int) -> (Int, Int) {
        var p1 = -1
        var p2 = -1
        for (index, hand) in hands.enumerated() where index != bidderIndex {
            if hand.contains(where: { $0.id == c1 }) { p1 = index }
            if hand.contains(where: { $0.id == c2 }) { p2 = index }
        }
        return (p1, p2)
    }

    static func nextPlayerInTrick(after playerIndex: Int, leaderIndex: Int) -> Int {
        let trickOrder = (0..<playerCount).map { normalizedSeat(leaderIndex + $0) }
        let position = trickOrder.firstIndex(of: playerIndex) ?? 0
        return trickOrder[(position + 1) % playerCount]
    }

    static func normalizedSeat(_ index: Int) -> Int {
        ((index % playerCount) + playerCount) % playerCount
    }

    static func isValidSeat(_ index: Int) -> Bool {
        index >= 0 && index < playerCount
    }
}
