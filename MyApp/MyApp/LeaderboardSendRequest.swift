import Foundation

enum SendResult: Equatable {
    case success
    /// Server rejected the payload (4xx). Retrying will not help; discard the record.
    case serverRejected(String)
    /// Network error, 5xx, or unexpected status. Safe to enqueue and retry later.
    case networkFailure
}

enum LeaderboardSendRequest {
    static func payload(for record: PendingGameRecord) -> [String: Any] {
        [
            "sessionCode":         record.sessionCode ?? "",
            "gameMode":            record.gameMode,
            "playerNames":         record.playerNames,
            "finalScores":         record.finalScores,
            "aiSeats":             record.aiSeats,
            "winnerIndex":         record.winnerIndex,
            "bid":                 record.bid,
            "bidMade":             record.bidMade,
            "bidderIndex":         record.bidderIndex,
            "partner1Index":       record.partner1Index,
            "partner2Index":       record.partner2Index,
            "defensePointsCaught": record.defensePointsCaught,
            "roundCount":          record.roundCount
        ]
    }

    static func wrappedPayload(for record: PendingGameRecord) -> [String: Any] {
        ["data": payload(for: record)]
    }

    static func result(forHTTPStatus status: Int) -> SendResult {
        if status == 200 {
            return .success
        }
        if status >= 400 && status < 500 {
            return .serverRejected("HTTP \(status)")
        }
        return .networkFailure
    }
}
