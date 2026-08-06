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

// MARK: - Reply snapshot

/// The snapshot the Watch receives after an action. The rule under test is that the reply carries
/// *that action's own* outcome, which is what tells the Watch user whether their round was recorded
/// and why not when it was refused.
///
/// This was previously latched in a `pendingStatusMessage` property on the bridge — written
/// synchronously in `handle`, read inside a spawned `Task`. Two messages arriving back-to-back
/// enqueue as `handle(A)`, `handle(B)`, `replyA`, `replyB`, so A's reply read B's message and
/// cleared the latch, and B fell back to the generic "Ready for Round N". Both replies were wrong.
/// The message is now a parameter, so it cannot be read off shared state at all.
///
/// Not covered here: the bridge's `handle` and its `WCSessionDelegate` methods, which reach
/// `WCSession.default` (a singleton) and cannot be exercised without a transport seam. A seam-based
/// test there would assert what the fake returned, not what the app does.
final class ScorekeeperWatchReplySnapshotTests: XCTestCase {

    @MainActor
    private func makeStore(_ name: String) -> ScorekeeperStore {
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return ScorekeeperStore(defaults: suite)
    }

    /// A refusal must reach the Watch. Falling back to the default "Ready for Round N" would tell
    /// the user their round was accepted when it was rejected.
    @MainActor
    func test_replySnapshotCarriesTheGivenMessageOverTheDefault() {
        let store = makeStore("ScorekeeperWatchReplySnapshotTests.refusal")
        store.start(playerNames: ["A", "B", "C", "D", "E", "F"])

        let defaultSnapshot = ScorekeeperWatchActionHandler.snapshot(from: store.activeGame)
        XCTAssertEqual(defaultSnapshot.statusMessage, "Ready for Round 1")

        let reply = ScorekeeperWatchActionHandler.replySnapshot(
            for: store.activeGame,
            statusMessage: "No round to undo."
        )

        XCTAssertEqual(reply.statusMessage, "No round to undo.")
    }

    /// Only the status message may differ. If the reply also changed scores or the round number the
    /// Watch would render a scorecard that never existed.
    @MainActor
    func test_replySnapshotChangesNothingButTheMessage() {
        let store = makeStore("ScorekeeperWatchReplySnapshotTests.fields")
        store.start(playerNames: ["A", "B", "C", "D", "E", "F"])
        _ = ScorekeeperWatchActionHandler.apply(
            ScorekeeperWatchActionPayload(
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
            ),
            to: store
        )

        var expected = ScorekeeperWatchActionHandler.snapshot(from: store.activeGame)
        expected.statusMessage = "Last round removed."

        let reply = ScorekeeperWatchActionHandler.replySnapshot(
            for: store.activeGame,
            statusMessage: "Last round removed."
        )

        XCTAssertEqual(reply, expected)
        XCTAssertEqual(reply.runningScores, [0, 130, 65, 65, 0, 0])
        XCTAssertTrue(reply.isActive)
    }

    /// A refusal with no scorecard must still explain itself. Returning the bare `.inactive`
    /// snapshot would replace the reason with "No active scorecard" — the state, not the outcome.
    @MainActor
    func test_replySnapshotExplainsARefusalEvenWithNoActiveGame() {
        let reply = ScorekeeperWatchActionHandler.replySnapshot(
            for: nil,
            statusMessage: "No round to undo."
        )

        XCTAssertEqual(reply.statusMessage, "No round to undo.")
        XCTAssertFalse(reply.isActive)
        XCTAssertEqual(reply.runningScores, [0, 0, 0, 0, 0, 0])
    }

    /// The anti-interleaving property, stated directly: two replies built from one game state must
    /// each keep their own message. The latch this replaced could not satisfy this.
    @MainActor
    func test_twoRepliesFromTheSameStateKeepTheirOwnMessages() {
        let store = makeStore("ScorekeeperWatchReplySnapshotTests.interleave")
        store.start(playerNames: ["A", "B", "C", "D", "E", "F"])

        let first = ScorekeeperWatchActionHandler.replySnapshot(
            for: store.activeGame, statusMessage: "Round details missing.")
        let second = ScorekeeperWatchActionHandler.replySnapshot(
            for: store.activeGame, statusMessage: "Snapshot sent.")

        XCTAssertEqual(first.statusMessage, "Round details missing.")
        XCTAssertEqual(second.statusMessage, "Snapshot sent.")
    }

    /// A malformed message must decode to `nil` so the delegate replies with the inactive snapshot
    /// rather than acting on a half-parsed action.
    func test_malformedWatchMessageDoesNotDecodeIntoAnAction() {
        XCTAssertNil(ScorekeeperWatchMessageCodec.decode(
            ScorekeeperWatchActionPayload.self, from: [:]))
        XCTAssertNil(ScorekeeperWatchMessageCodec.decode(
            ScorekeeperWatchActionPayload.self, from: ["payload": "not-json"]))
        XCTAssertNil(ScorekeeperWatchMessageCodec.decode(
            ScorekeeperWatchActionPayload.self, from: ["type": "notARealActionType"]))
    }
}
