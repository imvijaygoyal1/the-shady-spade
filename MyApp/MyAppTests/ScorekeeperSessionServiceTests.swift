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

    func test_findUniqueSessionCode_failsAfterMaximumCollisions() async {
        let remote = FakeScorekeeperSessionRemoteStore(existingCodes: ["AAAAAA"])
        let service = ScorekeeperSessionService(
            remote: remote,
            codeGenerator: { "AAAAAA" }
        )

        do {
            _ = try await service.findUniqueSessionCode(maxAttempts: 3)
            XCTFail("Expected noUniqueCode when all generated codes collide")
        } catch ScorekeeperSessionServiceError.noUniqueCode {
            XCTAssertEqual(remote.sessionExistsLookups, ["AAAAAA", "AAAAAA", "AAAAAA"])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_sessionCodeNormalizationAndValidation() {
        XCTAssertEqual(ScorekeeperSessionService.normalizedSessionCode(" view-01 "), "VIEW01")
        XCTAssertEqual(ScorekeeperSessionService.normalizedSessionCode("ab cd12!"), "ABCD12")
        XCTAssertTrue(ScorekeeperSessionService.isValidSessionCode("ABC123"))
        XCTAssertFalse(ScorekeeperSessionService.isValidSessionCode("ABC12"))
        XCTAssertFalse(ScorekeeperSessionService.isValidSessionCode("ABC1234"))
        XCTAssertFalse(ScorekeeperSessionService.isValidSessionCode("ABC12!"))
    }

    func test_liveHostStatusPresentation_coversPrimaryStates() {
        XCTAssertEqual(
            ScorekeeperLiveHostStatusPresentation.make(isLive: false, isBusy: false, hasError: false, hasSession: false),
            ScorekeeperLiveHostStatusPresentation(
                title: "Live View Off",
                message: "Start Live View before others try to join.",
                systemImage: "qrcode",
                showsCode: false
            )
        )

        XCTAssertEqual(
            ScorekeeperLiveHostStatusPresentation.make(isLive: true, isBusy: false, hasError: false, hasSession: true).title,
            "Live View On"
        )
        XCTAssertEqual(
            ScorekeeperLiveHostStatusPresentation.make(isLive: true, isBusy: true, hasError: false, hasSession: true).title,
            "Syncing Live View"
        )
        XCTAssertEqual(
            ScorekeeperLiveHostStatusPresentation.make(isLive: false, isBusy: false, hasError: true, hasSession: true).title,
            "Live View Needs Attention"
        )
        XCTAssertEqual(
            ScorekeeperLiveHostStatusPresentation.make(isLive: false, isBusy: false, hasError: false, hasSession: true).title,
            "Live View Closed"
        )
    }

    func test_liveViewerStatusPresentation_coversRecoveryActions() {
        XCTAssertEqual(ScorekeeperLiveViewerStatusPresentation.make(state: .live).title, "Live")
        XCTAssertNil(ScorekeeperLiveViewerStatusPresentation.make(state: .live).actionTitle)

        XCTAssertEqual(ScorekeeperLiveViewerStatusPresentation.make(state: .syncError).title, "Sync Issue")
        XCTAssertEqual(ScorekeeperLiveViewerStatusPresentation.make(state: .syncError).actionTitle, "Reconnect")

        XCTAssertEqual(ScorekeeperLiveViewerStatusPresentation.make(state: .closed).title, "Live View Closed")
        XCTAssertEqual(ScorekeeperLiveViewerStatusPresentation.make(state: .closed).actionTitle, "Change Code")

        XCTAssertEqual(ScorekeeperLiveViewerStatusPresentation.make(state: .expired).title, "Live View Expired")
        XCTAssertEqual(ScorekeeperLiveViewerStatusPresentation.make(state: .expired).actionTitle, "Change Code")

        XCTAssertEqual(ScorekeeperLiveViewerStatusPresentation.make(state: .notFound).title, "No Live View Found")
        XCTAssertEqual(ScorekeeperLiveViewerStatusPresentation.make(state: .notFound).actionTitle, "Change Code")
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

    func test_fetchSession_reportsMissingAndInvalidData() async {
        let remote = FakeScorekeeperSessionRemoteStore()
        let service = ScorekeeperSessionService(remote: remote)

        do {
            _ = try await service.fetchSession(code: "MISSING")
            XCTFail("Expected missing session error")
        } catch ScorekeeperSessionServiceError.sessionNotFound {}
        catch {
            XCTFail("Unexpected error: \(error)")
        }

        remote.seed(code: "BAD001", data: ["kind": "other"])

        do {
            _ = try await service.fetchSession(code: "BAD001")
            XCTFail("Expected invalid session data error")
        } catch ScorekeeperSessionServiceError.invalidSessionData {}
        catch {
            XCTFail("Unexpected error: \(error)")
        }
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

    @MainActor
    func test_publishingController_startPublishAndCloseTransitions() async throws {
        let remote = FakeScorekeeperSessionRemoteStore()
        var now = Date(timeIntervalSince1970: 2_000)
        let service = ScorekeeperSessionService(
            remote: remote,
            codeGenerator: { "HOST01" },
            now: { now },
            expirationInterval: 600
        )
        let controller = ScorekeeperLivePublishingController(
            service: service,
            hostUidProvider: { "host-uid" }
        )
        var game = ScorekeeperGameState(playerNames: ["A", "B", "C", "D", "E", "F"])

        await controller.startSharing(game: game)

        XCTAssertEqual(controller.sessionCode, "HOST01")
        XCTAssertTrue(controller.isLive)
        XCTAssertEqual(controller.shareURL?.absoluteString, "https://shadyspade.vijaygoyal.org/scorekeeper/HOST01")
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(remote.createdCodes, ["HOST01"])

        now = Date(timeIntervalSince1970: 2_020)
        var round = ScorekeeperRoundDraft(nextDealerIndex: 0)
        round.bidAmount = 145
        game.appendRound(round)

        await controller.publish(game: game)

        XCTAssertEqual(controller.document?.rounds.count, 1)
        XCTAssertEqual(controller.document?.runningScores, [0, 145, 72, 72, 0, 0])
        XCTAssertEqual(controller.document?.updatedAt, now)

        now = Date(timeIntervalSince1970: 2_040)
        await controller.close()

        XCTAssertEqual(controller.document?.updatedAt, now)
        XCTAssertEqual(controller.document?.isClosed, true)
        XCTAssertFalse(controller.isLive)
        XCTAssertEqual(remote.updatedCodes, ["HOST01", "HOST01"])
    }

    @MainActor
    func test_publishingController_reusesExistingSessionWhenStartSharingAgain() async throws {
        let remote = FakeScorekeeperSessionRemoteStore()
        var now = Date(timeIntervalSince1970: 4_000)
        let service = ScorekeeperSessionService(
            remote: remote,
            codeGenerator: { "HOST02" },
            now: { now },
            expirationInterval: 600
        )
        let controller = ScorekeeperLivePublishingController(
            service: service,
            hostUidProvider: { "host-uid" }
        )
        var game = ScorekeeperGameState(playerNames: ["A", "B", "C", "D", "E", "F"])

        await controller.startSharing(game: game)
        now = Date(timeIntervalSince1970: 4_020)
        var round = ScorekeeperRoundDraft(nextDealerIndex: 0)
        round.bidAmount = 150
        game.appendRound(round)

        await controller.startSharing(game: game)

        XCTAssertEqual(remote.createdCodes, ["HOST02"])
        XCTAssertEqual(remote.updatedCodes, ["HOST02"])
        XCTAssertEqual(controller.document?.rounds.count, 1)
        XCTAssertEqual(controller.document?.updatedAt, now)
    }

    @MainActor
    func test_publishingController_createsNewSessionAfterClosedSession() async throws {
        let remote = FakeScorekeeperSessionRemoteStore()
        var codes = ["HOST03", "HOST04"]
        let now = Date(timeIntervalSince1970: 4_200)
        let service = ScorekeeperSessionService(
            remote: remote,
            codeGenerator: { codes.removeFirst() },
            now: { now },
            expirationInterval: 600
        )
        let controller = ScorekeeperLivePublishingController(
            service: service,
            hostUidProvider: { "host-uid" }
        )
        let game = ScorekeeperGameState(playerNames: ["A", "B", "C", "D", "E", "F"])

        await controller.startSharing(game: game)
        await controller.close()
        await controller.startSharing(game: game)

        XCTAssertEqual(remote.createdCodes, ["HOST03", "HOST04"])
        XCTAssertEqual(controller.sessionCode, "HOST04")
        XCTAssertTrue(controller.isLive)
        XCTAssertNil(controller.errorMessage)
    }

    @MainActor
    func test_publishingController_reportsPublishAndCloseFailures() async throws {
        let remote = FakeScorekeeperSessionRemoteStore()
        let now = Date(timeIntervalSince1970: 4_500)
        let service = ScorekeeperSessionService(
            remote: remote,
            codeGenerator: { "FAIL01" },
            now: { now },
            expirationInterval: 600
        )
        let controller = ScorekeeperLivePublishingController(
            service: service,
            hostUidProvider: { "host-uid" }
        )
        let game = ScorekeeperGameState(playerNames: ["A", "B", "C", "D", "E", "F"])
        await controller.startSharing(game: game)

        remote.shouldThrowOnUpdate = true
        await controller.publish(game: game)

        XCTAssertEqual(controller.errorMessage, "Live sharing could not sync the latest scorecard.")
        XCTAssertFalse(controller.isBusy)

        await controller.close()

        XCTAssertEqual(controller.errorMessage, "Live sharing could not be closed.")
        XCTAssertEqual(controller.document?.isClosed, false)
        XCTAssertFalse(controller.isBusy)
    }

    @MainActor
    func test_publishingController_reportsStartFailure() async {
        let service = ScorekeeperSessionService(remote: ThrowingScorekeeperSessionRemoteStore())
        let controller = ScorekeeperLivePublishingController(
            service: service,
            hostUidProvider: { "host-uid" }
        )
        let game = ScorekeeperGameState(playerNames: ["A", "B", "C", "D", "E", "F"])

        await controller.startSharing(game: game)

        XCTAssertNil(controller.document)
        XCTAssertFalse(controller.isBusy)
        XCTAssertEqual(controller.errorMessage, "Could not start live sharing. Please try again.")
    }

    @MainActor
    func test_viewingController_rejectsInvalidCode() {
        let controller = ScorekeeperLiveViewingController()

        controller.startViewing(code: "bad")

        XCTAssertEqual(controller.state, .invalidCode)
        XCTAssertEqual(controller.errorMessage, "Enter exactly the 6-character code shown on the scorekeeper device.")
    }

    @MainActor
    func test_viewingController_observesLiveClosedAndMissingStates() async {
        let remote = FakeScorekeeperSessionRemoteStore()
        let now = Date(timeIntervalSince1970: 3_000)
        let service = ScorekeeperSessionService(remote: remote, now: { now })
        let controller = ScorekeeperLiveViewingController(service: service)
        let game = ScorekeeperGameState(playerNames: ["A", "B", "C", "D", "E", "F"])
        let live = ScorekeeperLiveSessionDocument(
            sessionCode: "VIEW01",
            hostUid: "host",
            game: game,
            createdAt: now,
            updatedAt: now,
            expiresAt: now.addingTimeInterval(600)
        )

        remote.seed(code: "VIEW01", data: live.firestoreData)
        controller.startViewing(code: "view01")
        await Task.yield()

        XCTAssertEqual(controller.sessionCode, "VIEW01")
        XCTAssertEqual(controller.state, .live)
        XCTAssertEqual(controller.document, live)

        remote.seed(code: "VIEW01", data: live.closed(updatedAt: now.addingTimeInterval(20)).firestoreData)
        await Task.yield()

        XCTAssertEqual(controller.state, .closed)

        controller.startViewing(code: "NONE01")
        await Task.yield()

        XCTAssertEqual(controller.state, .notFound)
        XCTAssertEqual(controller.errorMessage, "No live scorecard was found for NONE01. Check that the scorekeeper device shows Live View On, then re-enter the code.")
    }

    @MainActor
    func test_viewingController_marksExpiredSession() async {
        let remote = FakeScorekeeperSessionRemoteStore()
        let now = Date(timeIntervalSince1970: 3_000)
        let service = ScorekeeperSessionService(remote: remote, now: { now })
        let controller = ScorekeeperLiveViewingController(service: service)
        let game = ScorekeeperGameState(playerNames: ["A", "B", "C", "D", "E", "F"])
        let expired = ScorekeeperLiveSessionDocument(
            sessionCode: "OLD999",
            hostUid: "host",
            game: game,
            createdAt: now.addingTimeInterval(-1_000),
            updatedAt: now.addingTimeInterval(-100),
            expiresAt: now.addingTimeInterval(-1)
        )

        remote.seed(code: "OLD999", data: expired.firestoreData)
        controller.startViewing(code: "OLD999")
        await Task.yield()

        XCTAssertEqual(controller.state, .expired)
        XCTAssertEqual(controller.document, expired)
        XCTAssertNil(controller.errorMessage)
    }

    @MainActor
    func test_viewingController_reportsInvalidDataAndSyncErrorsAndStopsObservation() async {
        let remote = FakeScorekeeperSessionRemoteStore()
        let now = Date(timeIntervalSince1970: 5_000)
        let service = ScorekeeperSessionService(remote: remote, now: { now })
        let controller = ScorekeeperLiveViewingController(service: service)

        remote.seed(code: "BAD001", data: ["kind": "scorekeeper"])
        controller.startViewing(code: "BAD001")
        await Task.yield()

        XCTAssertEqual(controller.state, .syncError)
        XCTAssertEqual(controller.errorMessage, "This live scorecard data is not readable by this app version.")
        XCTAssertNil(controller.document)

        remote.emitError(code: "BAD001", error: URLError(.notConnectedToInternet))
        await Task.yield()

        XCTAssertEqual(controller.state, .syncError)
        XCTAssertEqual(controller.errorMessage, "Live scorecard could not sync. Check your connection and try again.")

        controller.stop()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.document)
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(remote.cancelCount, 1)
    }
}

private final class FakeScorekeeperSessionRemoteStore: ScorekeeperSessionRemoteStore {
    private var documents: [String: [String: Any]]
    private(set) var createdCodes: [String] = []
    private(set) var updatedCodes: [String] = []
    private(set) var sessionExistsLookups: [String] = []
    private(set) var cancelCount = 0
    var shouldThrowOnUpdate = false

    init(existingCodes: Set<String> = []) {
        documents = existingCodes.reduce(into: [:]) { result, code in
            result[code] = ["exists": true]
        }
    }

    func sessionExists(code: String) async throws -> Bool {
        sessionExistsLookups.append(code)
        return documents[code] != nil
    }

    func createSession(code: String, data: [String: Any]) async throws {
        createdCodes.append(code)
        documents[code] = data
    }

    func updateSession(code: String, data: [String: Any]) async throws {
        if shouldThrowOnUpdate {
            throw URLError(.cannotConnectToHost)
        }
        updatedCodes.append(code)
        var existing = documents[code] ?? [:]
        data.forEach { existing[$0.key] = $0.value }
        documents[code] = existing
    }

    func fetchSession(code: String) async throws -> [String: Any]? {
        documents[code]
    }

    func observeSession(
        code: String,
        onChange: @escaping (Result<[String: Any]?, Error>) -> Void
    ) -> ScorekeeperSessionObservation {
        observers[code, default: []].append(onChange)
        onChange(.success(documents[code]))
        return FakeScorekeeperSessionObservation { [weak self] in
            self?.cancelCount += 1
        }
    }

    func seed(code: String, data: [String: Any]) {
        documents[code] = data
        observers[code]?.forEach { $0(.success(data)) }
    }

    func emitError(code: String, error: Error) {
        observers[code]?.forEach { $0(.failure(error)) }
    }

    private var observers: [String: [(Result<[String: Any]?, Error>) -> Void]] = [:]
}

private struct FakeScorekeeperSessionObservation: ScorekeeperSessionObservation {
    var onCancel: () -> Void = {}

    func cancel() {
        onCancel()
    }
}

private struct ThrowingScorekeeperSessionRemoteStore: ScorekeeperSessionRemoteStore {
    func sessionExists(code: String) async throws -> Bool {
        throw URLError(.cannotConnectToHost)
    }

    func createSession(code: String, data: [String: Any]) async throws {
        throw URLError(.cannotConnectToHost)
    }

    func updateSession(code: String, data: [String: Any]) async throws {
        throw URLError(.cannotConnectToHost)
    }

    func fetchSession(code: String) async throws -> [String: Any]? {
        throw URLError(.cannotConnectToHost)
    }

    func observeSession(
        code: String,
        onChange: @escaping (Result<[String: Any]?, Error>) -> Void
    ) -> ScorekeeperSessionObservation {
        onChange(.failure(URLError(.cannotConnectToHost)))
        return FakeScorekeeperSessionObservation()
    }
}
