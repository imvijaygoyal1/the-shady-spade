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
            // Offense made the bid — positive scores
            bidderScore      = bidAmount
            eachPartnerScore = bidAmount / 2              // floor division
        } else {
            // Offense SET — negative scores
            bidderScore      = -bidAmount
            eachPartnerScore = -((bidAmount + 1) / 2)    // ceiling division
        }

        // Defense always scores 0 individually
        let defenseDisplayScore = 0                        // defense always scores 0 individually

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
