import Foundation

/// Who may be picked for each role when recording a round.
///
/// Shared by the iPhone form and the Watch form, which previously computed
/// this separately and so carried the same two wrong rules in both places
/// (2026-09-19):
///
/// - the bidder list excluded the **dealer**, but bidding starts at dealer+1
///   and goes round, so the dealer bids last and can win it;
/// - each partner list excluded the **other partner**, but one player can hold
///   both called cards, which makes the offense two against four.
enum ScorekeeperRoundEligibility {
    static let playerCount = 6

    /// Every seat.
    static var bidderCandidates: [Int] { Array(0..<playerCount) }

    /// Every seat except the bidder — five of them, the other partner included.
    static func partnerCandidates(bidderIndex: Int) -> [Int] {
        (0..<playerCount).filter { $0 != bidderIndex }
    }
}

enum ScorekeeperWatchActionType: String, Codable {
    case requestSnapshot
    case addRound
    case undoLastRound
}

struct ScorekeeperWatchSnapshot: Codable, Equatable {
    var isActive: Bool
    var playerNames: [String]
    var roundNumber: Int
    var nextDealerIndex: Int
    var runningScores: [Int]
    var lastRoundSummary: String?
    var statusMessage: String

    static let inactive = ScorekeeperWatchSnapshot(
        isActive: false,
        playerNames: [],
        roundNumber: 1,
        nextDealerIndex: 0,
        runningScores: Array(repeating: 0, count: 6),
        lastRoundSummary: nil,
        statusMessage: "No active scorecard"
    )
}

struct ScorekeeperWatchRoundDraftPayload: Codable, Equatable {
    var dealerIndex: Int
    var bidderIndex: Int
    var bidAmount: Int
    var trumpSuitRaw: String
    var partner1Index: Int
    var partner2Index: Int
    var calledCard1: String? = nil
    var calledCard2: String? = nil
    var bidMade: Bool
}

struct ScorekeeperWatchActionPayload: Codable, Equatable {
    var type: ScorekeeperWatchActionType
    var draft: ScorekeeperWatchRoundDraftPayload?

    static let requestSnapshot = ScorekeeperWatchActionPayload(type: .requestSnapshot, draft: nil)
    static let undoLastRound = ScorekeeperWatchActionPayload(type: .undoLastRound, draft: nil)
}

enum ScorekeeperWatchMessageCodec {
    static let payloadKey = "scorekeeperPayload"

    static func encode<T: Encodable>(_ value: T) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return [:]
        }
        return [payloadKey: string]
    }

    static func decode<T: Decodable>(_ type: T.Type, from message: [String: Any]) -> T? {
        guard let string = message[payloadKey] as? String,
              let data = string.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }
}
