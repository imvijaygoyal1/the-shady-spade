import XCTest
@testable import MyApp

final class ScorekeeperWatchBridgeTests: XCTestCase {
    func test_watchMessageCodecRoundTripsSnapshot() {
        let snapshot = ScorekeeperWatchSnapshot(
            isActive: true,
            playerNames: ["A", "B", "C", "D", "E", "F"],
            roundNumber: 2,
            nextDealerIndex: 1,
            runningScores: [130, 65, 65, 0, 0, 0],
            lastRoundSummary: "Round 1: A made 130 Spades",
            statusMessage: "Ready for Round 2"
        )

        let message = ScorekeeperWatchMessageCodec.encode(snapshot)
        XCTAssertEqual(
            ScorekeeperWatchMessageCodec.decode(ScorekeeperWatchSnapshot.self, from: message),
            snapshot
        )
    }

    @MainActor
    func test_inactiveSnapshotTellsWatchThereIsNoActiveScorecard() {
        let snapshot = ScorekeeperWatchActionHandler.snapshot(from: nil)

        XCTAssertFalse(snapshot.isActive)
        XCTAssertEqual(snapshot.roundNumber, 1)
        XCTAssertEqual(snapshot.runningScores, [0, 0, 0, 0, 0, 0])
        XCTAssertEqual(snapshot.statusMessage, "No active scorecard")
    }

    @MainActor
    func test_addRoundActionAppliesToActiveScorekeeperGame() {
        let suite = UserDefaults(suiteName: "ScorekeeperWatchBridgeTests.addRound")!
        suite.removePersistentDomain(forName: "ScorekeeperWatchBridgeTests.addRound")
        let store = ScorekeeperStore(defaults: suite)
        store.start(playerNames: ["A", "B", "C", "D", "E", "F"])

        let action = ScorekeeperWatchActionPayload(
            type: .addRound,
            draft: ScorekeeperWatchRoundDraftPayload(
                dealerIndex: 0,
                bidderIndex: 1,
                bidAmount: 130,
                trumpSuitRaw: TrumpSuit.spades.rawValue,
                partner1Index: 2,
                partner2Index: 3,
                bidMade: true
            )
        )

        let result = ScorekeeperWatchActionHandler.apply(action, to: store)

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(store.activeGame?.rounds.count, 1)
        XCTAssertEqual(store.activeGame?.runningScores, [0, 130, 65, 65, 0, 0])
    }

    @MainActor
    func test_addRoundActionRejectsBidderAsPartner() {
        let suite = UserDefaults(suiteName: "ScorekeeperWatchBridgeTests.rejectPartner")!
        suite.removePersistentDomain(forName: "ScorekeeperWatchBridgeTests.rejectPartner")
        let store = ScorekeeperStore(defaults: suite)
        store.start(playerNames: ["A", "B", "C", "D", "E", "F"])

        let action = ScorekeeperWatchActionPayload(
            type: .addRound,
            draft: ScorekeeperWatchRoundDraftPayload(
                dealerIndex: 0,
                bidderIndex: 1,
                bidAmount: 130,
                trumpSuitRaw: TrumpSuit.hearts.rawValue,
                partner1Index: 1,
                partner2Index: 3,
                bidMade: true
            )
        )

        let result = ScorekeeperWatchActionHandler.apply(action, to: store)

        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.message, "Partners cannot be the bidder.")
        XCTAssertEqual(store.activeGame?.rounds.count, 0)
    }

    @MainActor
    func test_addRoundActionRejectsInactiveScorekeeperGame() {
        let store = makeStore(name: "inactive")
        let action = addRoundAction()

        let result = ScorekeeperWatchActionHandler.apply(action, to: store)

        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.message, "Start scorekeeper on iPhone first.")
        XCTAssertNil(store.activeGame)
    }

    @MainActor
    func test_addRoundActionRejectsMissingDraft() {
        let store = makeStore(name: "missingDraft")
        store.start(playerNames: ["A", "B", "C", "D", "E", "F"])

        let result = ScorekeeperWatchActionHandler.apply(
            ScorekeeperWatchActionPayload(type: .addRound, draft: nil),
            to: store
        )

        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.message, "Round details missing.")
        XCTAssertEqual(store.activeGame?.rounds.count, 0)
    }

    @MainActor
    func test_addRoundActionRejectsInvalidTrump() {
        let store = makeStore(name: "invalidTrump")
        store.start(playerNames: ["A", "B", "C", "D", "E", "F"])

        let result = ScorekeeperWatchActionHandler.apply(
            addRoundAction(trumpSuitRaw: "x"),
            to: store
        )

        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.message, "Choose a valid trump suit.")
        XCTAssertEqual(store.activeGame?.rounds.count, 0)
    }

    @MainActor
    func test_addRoundActionRejectsDealerAsBidder() {
        let store = makeStore(name: "dealerBidder")
        store.start(playerNames: ["A", "B", "C", "D", "E", "F"])

        let result = ScorekeeperWatchActionHandler.apply(
            addRoundAction(dealerIndex: 0, bidderIndex: 0),
            to: store
        )

        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.message, "Dealer cannot be the bidder.")
        XCTAssertEqual(store.activeGame?.rounds.count, 0)
    }

    @MainActor
    func test_undoLastRoundRejectsWhenNoRoundsExist() {
        let store = makeStore(name: "undoEmpty")
        store.start(playerNames: ["A", "B", "C", "D", "E", "F"])

        let result = ScorekeeperWatchActionHandler.apply(.undoLastRound, to: store)

        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.message, "No round to undo.")
    }

    @MainActor
    func test_undoLastRoundRemovesLastRound() {
        let store = makeStore(name: "undoRound")
        store.start(playerNames: ["A", "B", "C", "D", "E", "F"])
        store.addRound(ScorekeeperRoundDraft(nextDealerIndex: 0))

        let result = ScorekeeperWatchActionHandler.apply(.undoLastRound, to: store)

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.message, "Last round removed.")
        XCTAssertEqual(store.activeGame?.rounds.count, 0)
    }

    @MainActor
    func test_snapshotContainsNextRoundAndRunningTotals() {
        let suite = UserDefaults(suiteName: "ScorekeeperWatchBridgeTests.snapshot")!
        suite.removePersistentDomain(forName: "ScorekeeperWatchBridgeTests.snapshot")
        let store = ScorekeeperStore(defaults: suite)
        store.start(playerNames: ["A", "B", "C", "D", "E", "F"])
        store.addRound(ScorekeeperRoundDraft(nextDealerIndex: 0))

        let snapshot = ScorekeeperWatchActionHandler.snapshot(from: store.activeGame)

        XCTAssertTrue(snapshot.isActive)
        XCTAssertEqual(snapshot.roundNumber, 2)
        XCTAssertEqual(snapshot.nextDealerIndex, 1)
        XCTAssertEqual(snapshot.runningScores, [0, 130, 65, 65, 0, 0])
        XCTAssertEqual(snapshot.statusMessage, "Ready for Round 2")
        XCTAssertNotNil(snapshot.lastRoundSummary)
    }

    private func makeStore(name: String) -> ScorekeeperStore {
        let suiteName = "ScorekeeperWatchBridgeTests.\(name)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        return ScorekeeperStore(defaults: suite)
    }

    private func addRoundAction(
        dealerIndex: Int = 0,
        bidderIndex: Int = 1,
        bidAmount: Int = 130,
        trumpSuitRaw: String = TrumpSuit.spades.rawValue,
        partner1Index: Int = 2,
        partner2Index: Int = 3,
        bidMade: Bool = true
    ) -> ScorekeeperWatchActionPayload {
        ScorekeeperWatchActionPayload(
            type: .addRound,
            draft: ScorekeeperWatchRoundDraftPayload(
                dealerIndex: dealerIndex,
                bidderIndex: bidderIndex,
                bidAmount: bidAmount,
                trumpSuitRaw: trumpSuitRaw,
                partner1Index: partner1Index,
                partner2Index: partner2Index,
                bidMade: bidMade
            )
        )
    }
}
