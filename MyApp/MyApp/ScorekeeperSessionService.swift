import Foundation
import FirebaseAuth
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
    func observeSession(
        code: String,
        onChange: @escaping (Result<[String: Any]?, Error>) -> Void
    ) -> ScorekeeperSessionObservation
}

protocol ScorekeeperSessionObservation {
    func cancel()
}

private struct NoopScorekeeperSessionObservation: ScorekeeperSessionObservation {
    func cancel() {}
}

private final class FirestoreScorekeeperSessionObservation: ScorekeeperSessionObservation {
    private let registration: ListenerRegistration

    init(registration: ListenerRegistration) {
        self.registration = registration
    }

    func cancel() {
        registration.remove()
    }
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

    func observeSession(
        code: String,
        onChange: @escaping (Result<[String: Any]?, Error>) -> Void
    ) -> ScorekeeperSessionObservation {
        let registration = collection.document(code).addSnapshotListener { snapshot, error in
            if let error {
                onChange(.failure(error))
                return
            }
            onChange(.success(snapshot?.data()))
        }
        return FirestoreScorekeeperSessionObservation(registration: registration)
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

    @MainActor
    func observeSession(
        code: String,
        onChange: @escaping @MainActor (Result<ScorekeeperLiveSessionDocument, ScorekeeperSessionServiceError>) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) -> ScorekeeperSessionObservation {
        let normalizedCode = Self.normalizedSessionCode(code)
        guard Self.isValidSessionCode(normalizedCode) else {
            onChange(.failure(.sessionNotFound))
            return NoopScorekeeperSessionObservation()
        }

        return remote.observeSession(code: normalizedCode) { result in
            Task { @MainActor in
                switch result {
                case .success(let data):
                    guard let data else {
                        onChange(.failure(.sessionNotFound))
                        return
                    }
                    guard let document = ScorekeeperLiveSessionDocument(sessionCode: normalizedCode, data: data) else {
                        onChange(.failure(.invalidSessionData))
                        return
                    }
                    onChange(.success(document))
                case .failure(let error):
                    onError(error)
                }
            }
        }
    }

    static func normalizedSessionCode(_ code: String) -> String {
        code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    static func isValidSessionCode(_ code: String) -> Bool {
        code.count == 6 && code.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    func canHostUpdate(document: ScorekeeperLiveSessionDocument, hostUid: String) -> Bool {
        document.hostUid == hostUid && !document.isClosed && !document.isExpired(now: now())
    }

    func isSessionExpired(_ document: ScorekeeperLiveSessionDocument) -> Bool {
        document.isExpired(now: now())
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

@MainActor
@Observable final class ScorekeeperLivePublishingController {
    private let service: ScorekeeperSessionService
    private let hostUidProvider: () async throws -> String
    private var hostUid: String?

    var document: ScorekeeperLiveSessionDocument?
    var isBusy = false
    var errorMessage: String?

    init(
        service: ScorekeeperSessionService = ScorekeeperSessionService(),
        hostUidProvider: @escaping () async throws -> String = ScorekeeperLivePublishingController.firebaseHostUid
    ) {
        self.service = service
        self.hostUidProvider = hostUidProvider
    }

    var isLive: Bool {
        guard let document, let hostUid else { return false }
        return service.canHostUpdate(document: document, hostUid: hostUid)
    }

    var sessionCode: String? {
        document?.sessionCode
    }

    var shareURL: URL? {
        guard let sessionCode else { return nil }
        return URL(string: "https://shadyspade-d6b84.web.app/shadyspade/scorekeeper/\(sessionCode)")
    }

    func startSharing(game: ScorekeeperGameState) async {
        guard document == nil else {
            await publish(game: game)
            return
        }

        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let uid = try await hostUidProvider()
            hostUid = uid
            document = try await service.createSession(hostUid: uid, game: game)
        } catch {
            errorMessage = "Could not start live sharing. Please try again."
        }
    }

    func publish(game: ScorekeeperGameState) async {
        guard let document, let hostUid else { return }
        guard !isBusy else { return }

        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            self.document = try await service.publish(game: game, to: document, hostUid: hostUid)
        } catch {
            errorMessage = "Live sharing could not sync the latest scorecard."
        }
    }

    func close() async {
        guard let document, let hostUid else { return }
        guard !document.isClosed else { return }
        guard !isBusy else { return }

        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            self.document = try await service.close(document: document, hostUid: hostUid)
        } catch {
            errorMessage = "Live sharing could not be closed."
        }
    }

    private static func firebaseHostUid() async throws -> String {
        if let uid = Auth.auth().currentUser?.uid {
            return uid
        }
        let result = try await Auth.auth().signInAnonymously()
        return result.user.uid
    }
}

enum ScorekeeperLiveViewerState: Equatable {
    case idle
    case loading
    case live
    case closed
    case expired
    case notFound
    case invalidCode
    case syncError
}

@MainActor
@Observable final class ScorekeeperLiveViewingController {
    private let service: ScorekeeperSessionService
    private var observation: ScorekeeperSessionObservation?

    var sessionCode = ""
    var document: ScorekeeperLiveSessionDocument?
    var state: ScorekeeperLiveViewerState = .idle
    var errorMessage: String?

    init(service: ScorekeeperSessionService = ScorekeeperSessionService()) {
        self.service = service
    }

    var canStart: Bool {
        ScorekeeperSessionService.isValidSessionCode(normalizedCode)
    }

    var normalizedCode: String {
        ScorekeeperSessionService.normalizedSessionCode(sessionCode)
    }

    func startViewing(code: String? = nil) {
        if let code {
            sessionCode = code
        }

        let code = normalizedCode
        guard ScorekeeperSessionService.isValidSessionCode(code) else {
            stop()
            state = .invalidCode
            errorMessage = "Enter a valid 6-character scorekeeper code."
            return
        }

        sessionCode = code
        document = nil
        state = .loading
        errorMessage = nil
        observation?.cancel()
        observation = service.observeSession(
            code: code,
            onChange: { [weak self] result in
                self?.handle(result)
            },
            onError: { [weak self] _ in
                self?.state = .syncError
                self?.errorMessage = "Live scorecard could not sync. Check your connection and try again."
            }
        )
    }

    func stop() {
        observation?.cancel()
        observation = nil
        document = nil
        state = .idle
        errorMessage = nil
    }

    private func handle(_ result: Result<ScorekeeperLiveSessionDocument, ScorekeeperSessionServiceError>) {
        switch result {
        case .success(let document):
            self.document = document
            errorMessage = nil
            if document.isClosed {
                state = .closed
            } else if service.isSessionExpired(document) {
                state = .expired
            } else {
                state = .live
            }
        case .failure(.sessionNotFound):
            document = nil
            state = .notFound
            errorMessage = "No live scorecard was found for this code."
        case .failure(.invalidSessionData):
            document = nil
            state = .syncError
            errorMessage = "This live scorecard data is not readable by this app version."
        case .failure:
            document = nil
            state = .syncError
            errorMessage = "Live scorecard could not sync. Check your connection and try again."
        }
    }
}
