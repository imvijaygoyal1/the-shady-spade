import XCTest
@testable import MyApp

final class AppRegressionTests: XCTestCase {
    func test_deepLinkRouter_normalizesJoinAndScorekeeperRoutes() {
        XCTAssertEqual(
            AppDeepLinkRouter.route(for: URL(string: "shadyspade://join/ab-c123!")!),
            .join("ABC123")
        )
        XCTAssertEqual(
            AppDeepLinkRouter.route(for: URL(string: "https://shadyspade-d6b84.web.app/shadyspade/scorekeeper/view01")!),
            .scorekeeper("VIEW01")
        )
        XCTAssertNil(AppDeepLinkRouter.route(for: URL(string: "shadyspade://scorekeeper/short")!))
        XCTAssertNil(AppDeepLinkRouter.route(for: URL(string: "https://shadyspade-d6b84.web.app/shadyspade/help/ABC123")!))
    }

    func test_leaderboardConsentResolution_requiresCurrentDisclosureForGrantedState() {
        XCTAssertEqual(
            LeaderboardConsentState.resolvedStoredState(
                rawValue: LeaderboardConsentState.granted.rawValue,
                storedDisclosureVersion: 1,
                currentDisclosureVersion: 2
            ),
            .undecided
        )
        XCTAssertEqual(
            LeaderboardConsentState.resolvedStoredState(
                rawValue: LeaderboardConsentState.granted.rawValue,
                storedDisclosureVersion: 2,
                currentDisclosureVersion: 2
            ),
            .granted
        )
        XCTAssertEqual(
            LeaderboardConsentState.resolvedStoredState(
                rawValue: LeaderboardConsentState.denied.rawValue,
                storedDisclosureVersion: 1,
                currentDisclosureVersion: 2
            ),
            .denied
        )
        XCTAssertFalse(LeaderboardConsentState.undecided.allowsLeaderboardUpload)
        XCTAssertFalse(LeaderboardConsentState.denied.allowsLeaderboardUpload)
        XCTAssertTrue(LeaderboardConsentState.granted.allowsLeaderboardUpload)
    }

    func test_pendingLeaderboardRecord_sanitizesAndShapesCompletedRoundPayload() {
        let round = HistoryRound(
            roundNumber: 12,
            dealerIndex: 0,
            bidderIndex: 1,
            bidAmount: 155,
            trumpSuit: .hearts,
            callCard1: "A♥",
            callCard2: "K♦",
            partner1Index: 2,
            partner2Index: 3,
            offensePointsCaught: 155,
            defensePointsCaught: 95,
            runningScores: [0, 155, 77, 77, 0, 0]
        )

        let record = PendingGameRecord.makeValidated(
            sessionCode: "ROOM-CODE-123",
            gameMode: "Online",
            playerNames: ["Amit", "shit", "Manish", "Vijay", "Sweta", "Megha"],
            finalScores: [0, 155, 77, 77, 0, 0],
            winnerIndex: 1,
            aiSeats: [-1, 0, 5, 6],
            rounds: [round]
        )

        XCTAssertEqual(record?.sessionCode, "ROOMCODR12")
        XCTAssertEqual(record?.playerNames, ["Amit", "Guest 2", "Manish", "Vijay", "Sweta", "Megha"])
        XCTAssertEqual(record?.aiSeats, [0, 5])
        XCTAssertEqual(record?.bid, 155)
        XCTAssertEqual(record?.bidMade, true)
        XCTAssertEqual(record?.bidderIndex, 1)
        XCTAssertEqual(record?.partner1Index, 2)
        XCTAssertEqual(record?.partner2Index, 3)
        XCTAssertEqual(record?.defensePointsCaught, 95)
        XCTAssertEqual(record?.roundCount, 12)
    }

    func test_pendingLeaderboardRecord_rejectsInvalidDimensionsAndEmptyRounds() {
        let validRound = HistoryRound(
            roundNumber: 1,
            dealerIndex: 0,
            bidderIndex: 1,
            bidAmount: 130,
            trumpSuit: .spades,
            callCard1: "A♠",
            callCard2: "K♠",
            partner1Index: 2,
            partner2Index: 3,
            offensePointsCaught: 125,
            defensePointsCaught: 125,
            runningScores: [0, -130, -65, -65, 0, 0]
        )
        let invalidRunningScores = HistoryRound(
            roundNumber: 1,
            dealerIndex: 0,
            bidderIndex: 1,
            bidAmount: 130,
            trumpSuit: .spades,
            callCard1: "A♠",
            callCard2: "K♠",
            partner1Index: 2,
            partner2Index: 3,
            offensePointsCaught: 125,
            defensePointsCaught: 125,
            runningScores: [0, -130]
        )

        XCTAssertNil(PendingGameRecord.makeValidated(
            sessionCode: "",
            gameMode: "Solo",
            playerNames: ["A", "B"],
            finalScores: [0, 0, 0, 0, 0, 0],
            winnerIndex: 0,
            rounds: [validRound]
        ))
        XCTAssertNil(PendingGameRecord.makeValidated(
            sessionCode: "",
            gameMode: "Solo",
            playerNames: ["A", "B", "C", "D", "E", "F"],
            finalScores: [0, 0],
            winnerIndex: 0,
            rounds: [validRound]
        ))
        XCTAssertNil(PendingGameRecord.makeValidated(
            sessionCode: "",
            gameMode: "Solo",
            playerNames: ["A", "B", "C", "D", "E", "F"],
            finalScores: [0, 0, 0, 0, 0, 0],
            winnerIndex: 0,
            rounds: [invalidRunningScores]
        ))
        XCTAssertNil(PendingGameRecord.makeValidated(
            sessionCode: "",
            gameMode: "Solo",
            playerNames: ["A", "B", "C", "D", "E", "F"],
            finalScores: [0, 0, 0, 0, 0, 0],
            winnerIndex: 0,
            rounds: []
        ))
    }

    func test_roundAndHistoryRoundExposeRolesAndScoringForSaveDisplays() {
        let round = Round(
            roundNumber: 1,
            dealerIndex: 0,
            bidderIndex: 1,
            bidAmount: 131,
            trumpSuit: .diamonds,
            callCard1: "A♦",
            callCard2: "K♦",
            partner1Index: 2,
            partner2Index: 4,
            offensePointsCaught: 120,
            defensePointsCaught: 130
        )

        XCTAssertTrue(round.isSet)
        XCTAssertEqual(round.role(of: 1), .bidder)
        XCTAssertEqual(round.role(of: 2), .partner)
        XCTAssertEqual(round.role(of: 0), .defense)
        XCTAssertEqual(round.score(for: 1), -131)
        XCTAssertEqual(round.score(for: 2), -66)
        XCTAssertEqual(round.score(for: 4), -66)
        XCTAssertEqual(round.score(for: 0), 0)

        let historyRound = HistoryRound(
            roundNumber: 1,
            dealerIndex: round.dealerIndex,
            bidderIndex: round.bidderIndex,
            bidAmount: round.bidAmount,
            trumpSuit: round.trumpSuit,
            callCard1: round.callCard1,
            callCard2: round.callCard2,
            partner1Index: round.partner1Index,
            partner2Index: round.partner2Index,
            offensePointsCaught: round.offensePointsCaught,
            defensePointsCaught: round.defensePointsCaught,
            runningScores: [-1, -131, -66, 0, -66, 0]
        )

        XCTAssertTrue(historyRound.isSet)
        XCTAssertEqual(historyRound.role(of: 4), .partner)
        XCTAssertEqual(historyRound.scoreDelta(for: 1), -131)
        XCTAssertEqual(historyRound.scoreDelta(for: 2), -66)
        XCTAssertEqual(historyRound.scoreDelta(for: 3), 0)
    }
}
