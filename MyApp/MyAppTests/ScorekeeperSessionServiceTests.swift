import XCTest
@testable import MyApp

final class ScorekeeperSessionServiceTests: XCTestCase {
    func test_liveSessionDocument_mapsGameStateToFirestoreAndBack() {
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 120)
        let expiresAt = Date(timeIntervalSince1970: 200)
        let round = ScorekeeperRoundEntry(
            roundNumber: 1,
            dealerIndex: 0,
            bidderIndex: 1,
            bidAmount: 135,
            trumpSuit: .spades,
            partner1Index: 2,
            partner2Index: 3,
            offensePointsCaught: 135,
            createdAt: createdAt
        )
        let game = ScorekeeperGameState(
            playerNames: ["Amit", "Shikha", "Manish", "Vijay", "Sweta", "Megha"],
            rounds: [round]
        )
        let document = ScorekeeperLiveSessionDocument(
            sessionCode: "ABC123",
            hostUid: "host-uid",
            game: game,
            createdAt: createdAt,
            updatedAt: updatedAt,
            expiresAt: expiresAt
        )

        XCTAssertEqual(document.playerNames, ["Amit", "Shikha", "Manish", "Vijay", "Sweta", "Megha"])
        XCTAssertEqual(document.rounds.count, 1)
        XCTAssertEqual(document.runningScores, [0, 135, 67, 67, 0, 0])
        XCTAssertEqual(document.winnerIndex, 1)

        let parsed = ScorekeeperLiveSessionDocument(sessionCode: "ABC123", data: document.firestoreData)

        XCTAssertEqual(parsed, document)
    }

    func test_findUniqueSessionCode_skipsCollisions() async throws {
        let remote = FakeScorekeeperSessionRemoteStore(existingCodes: ["AAAAAA", "BBBBBB"])
        var codes = ["AAAAAA", "BBBBBB", "CCCCCC"]
        let service = ScorekeeperSessionService(
            remote: remote,
            codeGenerator: { codes.removeFirst() }
        )

        let code = try await service.findUniqueSessionCode()

        XCTAssertEqual(code, "CCCCCC")
    }

    func test_createSession_writesDocumentWithExpiration() async throws {
        let remote = FakeScorekeeperSessionRemoteStore()
        let now = Date(timeIntervalSince1970: 1_000)
        let game = ScorekeeperGameState(playerNames: ["A", "B", "C", "D", "E", "F"])
        let service = ScorekeeperSessionService(
            remote: remote,
            codeGenerator: { "ZXCVBN" },
            now: { now },
            expirationInterval: 60
        )

        let document = try await service.createSession(hostUid: "host", game: game)

        XCTAssertEqual(document.sessionCode, "ZXCVBN")
        XCTAssertEqual(document.hostUid, "host")
        XCTAssertEqual(document.createdAt, now)
        XCTAssertEqual(document.updatedAt, now)
        XCTAssertEqual(document.expiresAt, now.addingTimeInterval(60))
        XCTAssertEqual(remote.createdCodes, ["ZXCVBN"])

        let fetched = try await service.fetchSession(code: "ZXCVBN")
        XCTAssertEqual(fetched, document)
    }

    func test_hostOnlyUpdate_rejectsWrongHostClosedAndExpiredSessions() async throws {
        let remote = FakeScorekeeperSessionRemoteStore()
        let now = Date(timeIntervalSince1970: 1_000)
        let game = ScorekeeperGameState(playerNames: ["A", "B", "C", "D", "E", "F"])
        let service = ScorekeeperSessionService(
            remote: remote,
            now: { now },
            expirationInterval: 60
        )
        let document = ScorekeeperLiveSessionDocument(
            sessionCode: "ABC123",
            hostUid: "host",
            game: game,
            createdAt: now,
            updatedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )

        XCTAssertTrue(service.canHostUpdate(document: document, hostUid: "host"))
        XCTAssertFalse(service.canHostUpdate(document: document, hostUid: "viewer"))

        do {
            _ = try await service.publish(game: game, to: document, hostUid: "viewer")
            XCTFail("Expected wrong host to be rejected")
        } catch ScorekeeperSessionServiceError.hostMismatch {}

        let closed = document.closed(updatedAt: now)
        XCTAssertFalse(service.canHostUpdate(document: closed, hostUid: "host"))
        do {
            _ = try await service.publish(game: game, to: closed, hostUid: "host")
            XCTFail("Expected closed session to be rejected")
        } catch ScorekeeperSessionServiceError.sessionClosed {}

        let expired = ScorekeeperLiveSessionDocument(
            sessionCode: "ABC123",
            hostUid: "host",
            game: game,
            createdAt: now.addingTimeInterval(-120),
            updatedAt: now.addingTimeInterval(-120),
            expiresAt: now.addingTimeInterval(-1)
        )
        XCTAssertFalse(service.canHostUpdate(document: expired, hostUid: "host"))
        do {
            _ = try await service.publish(game: game, to: expired, hostUid: "host")
            XCTFail("Expected expired session to be rejected")
        } catch ScorekeeperSessionServiceError.sessionExpired {}
    }

    func test_publishAndClose_updateRemoteDocument() async throws {
        let remote = FakeScorekeeperSessionRemoteStore()
        var now = Date(timeIntervalSince1970: 1_000)
        let service = ScorekeeperSessionService(
            remote: remote,
            codeGenerator: { "LIVE01" },
            now: { now },
            expirationInterval: 600
        )
        var game = ScorekeeperGameState(playerNames: ["A", "B", "C", "D", "E", "F"])
        let created = try await service.createSession(hostUid: "host", game: game)

        now = Date(timeIntervalSince1970: 1_020)
        var round = ScorekeeperRoundDraft(nextDealerIndex: 0)
        round.bidAmount = 140
        game.appendRound(round)

        let published = try await service.publish(game: game, to: created, hostUid: "host")

        XCTAssertEqual(published.updatedAt, now)
        XCTAssertEqual(published.rounds.count, 1)
        XCTAssertEqual(published.runningScores, [0, 140, 70, 70, 0, 0])

        now = Date(timeIntervalSince1970: 1_030)
        let closed = try await service.close(document: published, hostUid: "host")

        XCTAssertTrue(closed.isClosed)
        XCTAssertEqual(closed.updatedAt, now)
        XCTAssertEqual(remote.updatedCodes, ["LIVE01", "LIVE01"])
    }
}

private final class FakeScorekeeperSessionRemoteStore: ScorekeeperSessionRemoteStore {
    private var documents: [String: [String: Any]]
    private(set) var createdCodes: [String] = []
    private(set) var updatedCodes: [String] = []

    init(existingCodes: Set<String> = []) {
        documents = existingCodes.reduce(into: [:]) { result, code in
            result[code] = ["exists": true]
        }
    }

    func sessionExists(code: String) async throws -> Bool {
        documents[code] != nil
    }

    func createSession(code: String, data: [String: Any]) async throws {
        createdCodes.append(code)
        documents[code] = data
    }

    func updateSession(code: String, data: [String: Any]) async throws {
        updatedCodes.append(code)
        var existing = documents[code] ?? [:]
        data.forEach { existing[$0.key] = $0.value }
        documents[code] = existing
    }

    func fetchSession(code: String) async throws -> [String: Any]? {
        documents[code]
    }
}
