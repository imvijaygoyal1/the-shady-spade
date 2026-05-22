import Foundation

// MARK: - Round Score Result

struct RoundScoreResult {
    /// Per-player score deltas (6 players, index-aligned)
    let playerDeltas: [Int]
    let bidderScore: Int
    let eachPartnerScore: Int
    /// Display-only. Not added to any individual's running total.
    let defenseDisplayScore: Int
    let bidMade: Bool
}

// MARK: - Scoring Engine

enum ScoringEngine {
    /// Calculate score deltas for a single round.
    /// - Parameters:
    ///   - bidAmount: The winning bid amount.
    ///   - bidderIndex: Index (0–5) of the bidder.
    ///   - offenseIndices: Set of indices on the offense team (includes bidder + 2 partners).
    ///   - bidMade: Whether the offense team reached or exceeded the bid.
    static func calculateRoundScores(
        bidAmount: Int,
        bidderIndex: Int,
        offenseIndices: Set<Int>,
        bidMade: Bool
    ) -> RoundScoreResult {
        let bidderScore: Int
        let eachPartnerScore: Int

        if bidMade {
            // Offense made the bid — positive scores.
            // Partners earn floor(bid/2): on odd bids the bidder keeps the larger share
            // as reward for taking on the risk of calling trump.
            bidderScore      = bidAmount
            eachPartnerScore = bidAmount / 2
        } else {
            // Offense SET — negative scores.
            // Partners lose ceil(bid/2): rounding up ensures the full penalty is distributed
            // without floating point; total penalty = bid + 2×ceil(bid/2) ≈ 2×bid.
            bidderScore      = -bidAmount
            eachPartnerScore = -((bidAmount + 1) / 2)
        }

        // Defense earns no individual score delta per round.
        // Their team goal is to prevent the bid — accumulated points come only from
        // rounds where they ARE the offense. This value exists solely for display.
        let defenseDisplayScore = 0

        var playerDeltas = Array(repeating: 0, count: 6)
        for i in 0..<6 {
            if i == bidderIndex {
                playerDeltas[i] = bidderScore
            } else if offenseIndices.contains(i) {
                playerDeltas[i] = eachPartnerScore
            } else {
                playerDeltas[i] = 0
            }
        }

        return RoundScoreResult(
            playerDeltas: playerDeltas,
            bidderScore: bidderScore,
            eachPartnerScore: eachPartnerScore,
            defenseDisplayScore: defenseDisplayScore,
            bidMade: bidMade
        )
    }
}
