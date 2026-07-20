import Foundation

enum SyncedGameStateMapper {
    static func int(_ value: Any?, default defaultValue: Int = 0) -> Int {
        (value as? Int) ?? (value as? Int64).map(Int.init) ?? defaultValue
    }

    static func sixInts(from value: Any?, default defaultValue: Int) -> [Int]? {
        guard let values = value as? [Any], values.count == 6 else { return nil }
        return values.map { int($0, default: defaultValue) }
    }

    static func sixBools(from value: Any?) -> [Bool]? {
        guard let values = value as? [Any], values.count == 6 else { return nil }
        return values.map { ($0 as? Bool) ?? false }
    }

    static func aiSeats(from value: Any?) -> [Int] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap { raw in
            let seat = (raw as? Int) ?? (raw as? Int64).map(Int.init)
            guard let seat, (0..<6).contains(seat) else { return nil }
            return seat
        }
    }

    static func bidHistory(from value: Any?, boundsChecked: Bool) -> [(playerIndex: Int, amount: Int)] {
        guard let entries = value as? [[String: Any]] else { return [] }
        let parsed = entries.compactMap { entry -> (playerIndex: Int, amount: Int)? in
            guard let playerIndex = optionalInt(entry["pi"]),
                  let amount = optionalInt(entry["amt"]) else {
                return nil
            }
            if boundsChecked && !(0..<6).contains(playerIndex) {
                return nil
            }
            return (playerIndex: playerIndex, amount: amount)
        }
        return latestBidPerPlayer(parsed)
    }

    static func encodedBidHistory(_ history: [(playerIndex: Int, amount: Int)]) -> [[String: Any]] {
        history.map { ["pi": $0.playerIndex, "amt": $0.amount] }
    }

    static func currentTrick(from value: Any?) -> [(playerIndex: Int, card: Card)] {
        guard let entries = value as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let playerIndex = optionalInt(entry["pi"]),
                  (0..<6).contains(playerIndex),
                  let cardID = entry["card"] as? String,
                  let card = card(from: cardID) else {
                return nil
            }
            return (playerIndex: playerIndex, card: card)
        }
    }

    static func encodedCurrentTrick(_ trick: [(playerIndex: Int, card: Card)]) -> [[String: Any]] {
        trick.map { ["pi": $0.playerIndex, "card": $0.card.id] }
    }

    static func encodedCompletedRounds(_ rounds: [HistoryRound]) -> [[String: Any]] {
        rounds.map { round in
            [
                "roundNumber": round.roundNumber,
                "dealerIndex": round.dealerIndex,
                "bidderIndex": round.bidderIndex,
                "bidAmount": round.bidAmount,
                "trumpSuit": round.trumpSuitRaw,
                "callCard1": round.callCard1,
                "callCard2": round.callCard2,
                "partner1Index": round.partner1Index,
                "partner2Index": round.partner2Index,
                "offensePointsCaught": round.offensePointsCaught,
                "defensePointsCaught": round.defensePointsCaught,
                "runningScores": round.runningScores
            ]
        }
    }

    static func completedRounds(from value: Any?, excludingRoundNumbers existing: Set<Int>) -> [HistoryRound] {
        guard let entries = value as? [[String: Any]] else { return [] }
        var seen = existing
        return entries.compactMap { entry in
            guard let round = completedRound(from: entry),
                  seen.insert(round.roundNumber).inserted else {
                return nil
            }
            return round
        }
    }

    static func completedRound(
        roundNumber: Int,
        dealerIndex: Int,
        highBidderIndex: Int,
        highBid: Int,
        trumpSuit: TrumpSuit,
        calledCard1: String,
        calledCard2: String,
        partner1Index: Int,
        partner2Index: Int,
        offensePoints: Int,
        defensePoints: Int,
        runningScores: [Int],
        requiresResolvedPartners: Bool
    ) -> HistoryRound? {
        if requiresResolvedPartners {
            guard partner1Index >= 0, partner2Index >= 0 else { return nil }
        }

        return HistoryRound(
            roundNumber: roundNumber,
            dealerIndex: dealerIndex,
            bidderIndex: highBidderIndex >= 0 ? highBidderIndex : 0,
            bidAmount: highBid,
            trumpSuit: trumpSuit,
            callCard1: calledCard1,
            callCard2: calledCard2,
            partner1Index: partner1Index >= 0 ? partner1Index : 0,
            partner2Index: partner2Index >= 0 ? partner2Index : 0,
            offensePointsCaught: offensePoints,
            defensePointsCaught: defensePoints,
            runningScores: normalizedRunningScores(runningScores)
        )
    }

    static func card(from id: String) -> Card? {
        guard let suit = id.last else { return nil }
        let rank = String(id.dropLast())
        guard !rank.isEmpty else { return nil }
        let card = Card(rank: rank, suit: String(suit))
        return AIEngine.fullDeck.contains(card) ? card : nil
    }

    private static func completedRound(from entry: [String: Any]) -> HistoryRound? {
        let roundNumber = int(entry["roundNumber"], default: -1)
        guard roundNumber >= 0 else { return nil }
        let partner1Index = int(entry["partner1Index"], default: -1)
        let partner2Index = int(entry["partner2Index"], default: -1)
        guard partner1Index >= 0, partner2Index >= 0 else { return nil }

        return HistoryRound(
            roundNumber: roundNumber,
            dealerIndex: int(entry["dealerIndex"]),
            bidderIndex: int(entry["bidderIndex"]),
            bidAmount: int(entry["bidAmount"], default: 130),
            trumpSuit: TrumpSuit(rawValue: entry["trumpSuit"] as? String ?? "") ?? .spades,
            callCard1: entry["callCard1"] as? String ?? "",
            callCard2: entry["callCard2"] as? String ?? "",
            partner1Index: partner1Index,
            partner2Index: partner2Index,
            offensePointsCaught: int(entry["offensePointsCaught"]),
            defensePointsCaught: int(entry["defensePointsCaught"]),
            runningScores: normalizedRunningScores(entry["runningScores"] as? [Int] ?? [])
        )
    }

    private static func optionalInt(_ value: Any?) -> Int? {
        (value as? Int) ?? (value as? Int64).map(Int.init)
    }

    private static func latestBidPerPlayer(
        _ history: [(playerIndex: Int, amount: Int)]
    ) -> [(playerIndex: Int, amount: Int)] {
        var latest: [Int: Int] = [:]
        for entry in history { latest[entry.playerIndex] = entry.amount }
        var seen = Set<Int>()
        return history.compactMap { entry in
            guard seen.insert(entry.playerIndex).inserted else { return nil }
            return (playerIndex: entry.playerIndex, amount: latest[entry.playerIndex] ?? entry.amount)
        }
    }

    private static func normalizedRunningScores(_ scores: [Int]) -> [Int] {
        scores.count == 6 ? scores : Array(repeating: 0, count: 6)
    }
}
