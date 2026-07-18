import Foundation
import FirebaseFirestore

struct ScorekeeperLiveRoundDTO: Equatable {
    var roundNumber: Int
    var dealerIndex: Int
    var bidderIndex: Int
    var bidAmount: Int
    var trumpSuit: TrumpSuit
    var partner1Index: Int
    var partner2Index: Int
    var offensePointsCaught: Int
    var createdAt: Date

    init(round: ScorekeeperRoundEntry) {
        roundNumber = round.roundNumber
        dealerIndex = round.dealerIndex
        bidderIndex = round.bidderIndex
        bidAmount = round.bidAmount
        trumpSuit = round.trumpSuit
        partner1Index = round.partner1Index
        partner2Index = round.partner2Index
        offensePointsCaught = round.offensePointsCaught
        createdAt = round.createdAt
    }

    init?(_ data: [String: Any]) {
        guard let roundNumber = Self.int(data["roundNumber"]),
              let dealerIndex = Self.int(data["dealerIndex"]),
              let bidderIndex = Self.int(data["bidderIndex"]),
              let bidAmount = Self.int(data["bidAmount"]),
              let trumpRaw = data["trumpSuit"] as? String,
              let trumpSuit = TrumpSuit(rawValue: trumpRaw),
              let partner1Index = Self.int(data["partner1Index"]),
              let partner2Index = Self.int(data["partner2Index"]),
              let offensePointsCaught = Self.int(data["offensePointsCaught"]) else {
            return nil
        }

        self.roundNumber = roundNumber
        self.dealerIndex = dealerIndex
        self.bidderIndex = bidderIndex
        self.bidAmount = bidAmount
        self.trumpSuit = trumpSuit
        self.partner1Index = partner1Index
        self.partner2Index = partner2Index
        self.offensePointsCaught = offensePointsCaught
        self.createdAt = Self.date(data["createdAt"]) ?? Date(timeIntervalSince1970: 0)
    }

    var firestoreData: [String: Any] {
        [
            "roundNumber": roundNumber,
            "dealerIndex": dealerIndex,
            "bidderIndex": bidderIndex,
            "bidAmount": bidAmount,
            "trumpSuit": trumpSuit.rawValue,
            "partner1Index": partner1Index,
            "partner2Index": partner2Index,
            "offensePointsCaught": offensePointsCaught,
            "createdAt": Timestamp(date: createdAt)
        ]
    }

    private static func int(_ value: Any?) -> Int? {
        (value as? Int) ?? (value as? Int64).map(Int.init) ?? (value as? NSNumber).map(\.intValue)
    }

    private static func date(_ value: Any?) -> Date? {
        (value as? Timestamp)?.dateValue() ?? value as? Date
    }
}

struct ScorekeeperLiveSessionDocument: Equatable {
    static let kind = "scorekeeper"
    static let schemaVersion = 1

    var sessionCode: String
    var hostUid: String
    var createdAt: Date
    var updatedAt: Date
    var expiresAt: Date
    var isClosed: Bool
    var playerNames: [String]
    var rounds: [ScorekeeperLiveRoundDTO]
    var runningScores: [Int]
    var winnerIndex: Int

    init(
        sessionCode: String,
        hostUid: String,
        game: ScorekeeperGameState,
        createdAt: Date,
        updatedAt: Date,
        expiresAt: Date,
        isClosed: Bool = false
    ) {
        self.sessionCode = sessionCode
        self.hostUid = hostUid
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.isClosed = isClosed
        self.playerNames = game.playerNames
        self.rounds = game.rounds.map(ScorekeeperLiveRoundDTO.init(round:))
        self.runningScores = game.runningScores
        self.winnerIndex = game.winnerIndex
    }

    init?(sessionCode: String, data: [String: Any]) {
        guard data["kind"] as? String == Self.kind,
              Self.int(data["schemaVersion"]) == Self.schemaVersion,
              let hostUid = data["hostUid"] as? String,
              let createdAt = Self.date(data["createdAt"]),
              let updatedAt = Self.date(data["updatedAt"]),
              let expiresAt = Self.date(data["expiresAt"]),
              let isClosed = data["isClosed"] as? Bool,
              let rawPlayerNames = data["playerNames"] as? [String],
              let rawRounds = data["rounds"] as? [[String: Any]],
              let rawRunningScores = data["runningScores"] as? [Any],
              let winnerIndex = Self.int(data["winnerIndex"]) else {
            return nil
        }

        let rounds = rawRounds.compactMap(ScorekeeperLiveRoundDTO.init)
        guard rounds.count == rawRounds.count else { return nil }

        self.sessionCode = sessionCode
        self.hostUid = hostUid
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.isClosed = isClosed
        self.playerNames = ScorekeeperGameState.normalizedPlayerNames(rawPlayerNames)
        self.rounds = rounds
        self.runningScores = rawRunningScores.compactMap(Self.int)
        self.winnerIndex = winnerIndex
    }

    var firestoreData: [String: Any] {
        [
            "kind": Self.kind,
            "schemaVersion": Self.schemaVersion,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
            "expiresAt": Timestamp(date: expiresAt),
            "hostUid": hostUid,
            "isClosed": isClosed,
            "playerNames": playerNames,
            "rounds": rounds.map(\.firestoreData),
            "runningScores": runningScores,
            "winnerIndex": winnerIndex
        ]
    }

    func isExpired(now: Date = Date()) -> Bool {
        expiresAt <= now
    }

    func withGame(_ game: ScorekeeperGameState, updatedAt: Date) -> ScorekeeperLiveSessionDocument {
        ScorekeeperLiveSessionDocument(
            sessionCode: sessionCode,
            hostUid: hostUid,
            game: game,
            createdAt: createdAt,
            updatedAt: updatedAt,
            expiresAt: expiresAt,
            isClosed: isClosed
        )
    }

    func closed(updatedAt: Date) -> ScorekeeperLiveSessionDocument {
        var copy = self
        copy.isClosed = true
        copy.updatedAt = updatedAt
        return copy
    }

    private static func int(_ value: Any?) -> Int? {
        (value as? Int) ?? (value as? Int64).map(Int.init) ?? (value as? NSNumber).map(\.intValue)
    }

    private static func date(_ value: Any?) -> Date? {
        (value as? Timestamp)?.dateValue() ?? value as? Date
    }
}

protocol ScorekeeperSessionRemoteStore {
    func sessionExists(code: String) async throws -> Bool
    func createSession(code: String, data: [String: Any]) async throws
    func updateSession(code: String, data: [String: Any]) async throws
    func fetchSession(code: String) async throws -> [String: Any]?
}

struct FirestoreScorekeeperSessionRemoteStore: ScorekeeperSessionRemoteStore {
    private let collection = Firestore.firestore().collection("scorekeeperSessions")

    func sessionExists(code: String) async throws -> Bool {
        try await collection.document(code).getDocument().exists
    }

    func createSession(code: String, data: [String: Any]) async throws {
        try await collection.document(code).setData(data)
    }

    func updateSession(code: String, data: [String: Any]) async throws {
        try await collection.document(code).setData(data, merge: true)
    }

    func fetchSession(code: String) async throws -> [String: Any]? {
        try await collection.document(code).getDocument().data()
    }
}

enum ScorekeeperSessionServiceError: Error, Equatable {
    case noUniqueCode
    case hostMismatch
    case sessionClosed
    case sessionExpired
    case sessionNotFound
    case invalidSessionData
}

final class ScorekeeperSessionService {
    private let remote: ScorekeeperSessionRemoteStore
    private let codeGenerator: () -> String
    private let now: () -> Date
    private let expirationInterval: TimeInterval

    init(
        remote: ScorekeeperSessionRemoteStore = FirestoreScorekeeperSessionRemoteStore(),
        codeGenerator: @escaping () -> String = ScorekeeperSessionService.generateRoomCode,
        now: @escaping () -> Date = Date.init,
        expirationInterval: TimeInterval = 24 * 60 * 60
    ) {
        self.remote = remote
        self.codeGenerator = codeGenerator
        self.now = now
        self.expirationInterval = expirationInterval
    }

    static func generateRoomCode() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<6).compactMap { _ in chars.randomElement() })
    }

    func findUniqueSessionCode(maxAttempts: Int = 5) async throws -> String {
        for _ in 0..<maxAttempts {
            let code = codeGenerator()
            if try await !remote.sessionExists(code: code) {
                return code
            }
        }
        throw ScorekeeperSessionServiceError.noUniqueCode
    }

    func createSession(hostUid: String, game: ScorekeeperGameState) async throws -> ScorekeeperLiveSessionDocument {
        let code = try await findUniqueSessionCode()
        let createdAt = now()
        let document = ScorekeeperLiveSessionDocument(
            sessionCode: code,
            hostUid: hostUid,
            game: game,
            createdAt: createdAt,
            updatedAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(expirationInterval)
        )
        try await remote.createSession(code: code, data: document.firestoreData)
        return document
    }

    func publish(
        game: ScorekeeperGameState,
        to document: ScorekeeperLiveSessionDocument,
        hostUid: String
    ) async throws -> ScorekeeperLiveSessionDocument {
        try validateHostUpdate(document: document, hostUid: hostUid)
        let updated = document.withGame(game, updatedAt: now())
        try await remote.updateSession(code: updated.sessionCode, data: updated.firestoreData)
        return updated
    }

    func close(
        document: ScorekeeperLiveSessionDocument,
        hostUid: String
    ) async throws -> ScorekeeperLiveSessionDocument {
        try validateHostUpdate(document: document, hostUid: hostUid)
        let closed = document.closed(updatedAt: now())
        try await remote.updateSession(code: closed.sessionCode, data: closed.firestoreData)
        return closed
    }

    func fetchSession(code: String) async throws -> ScorekeeperLiveSessionDocument {
        guard let data = try await remote.fetchSession(code: code) else {
            throw ScorekeeperSessionServiceError.sessionNotFound
        }
        guard let document = ScorekeeperLiveSessionDocument(sessionCode: code, data: data) else {
            throw ScorekeeperSessionServiceError.invalidSessionData
        }
        return document
    }

    func canHostUpdate(document: ScorekeeperLiveSessionDocument, hostUid: String) -> Bool {
        document.hostUid == hostUid && !document.isClosed && !document.isExpired(now: now())
    }

    private func validateHostUpdate(document: ScorekeeperLiveSessionDocument, hostUid: String) throws {
        guard document.hostUid == hostUid else {
            throw ScorekeeperSessionServiceError.hostMismatch
        }
        guard !document.isClosed else {
            throw ScorekeeperSessionServiceError.sessionClosed
        }
        guard !document.isExpired(now: now()) else {
            throw ScorekeeperSessionServiceError.sessionExpired
        }
    }
}
