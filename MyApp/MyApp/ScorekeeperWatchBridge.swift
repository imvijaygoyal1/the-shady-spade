import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

struct ScorekeeperWatchActionResult: Equatable {
    var accepted: Bool
    var message: String
}

enum ScorekeeperWatchActionHandler {
    @MainActor
    static func snapshot(from game: ScorekeeperGameState?) -> ScorekeeperWatchSnapshot {
        guard let game else { return .inactive }
        let lastRound = game.rounds.last.map { round in
            let bidder = game.name(for: round.bidderIndex)
            let result = round.bidMade ? "made" : "set"
            return "Round \(round.roundNumber): \(bidder) \(result) \(round.bidAmount) \(round.trumpSuit.displayName)"
        }

        return ScorekeeperWatchSnapshot(
            isActive: true,
            playerNames: game.playerNames,
            roundNumber: game.nextRoundNumber,
            nextDealerIndex: game.nextDealerIndex,
            runningScores: game.runningScores,
            lastRoundSummary: lastRound,
            statusMessage: "Ready for Round \(game.nextRoundNumber)"
        )
    }

    /// The snapshot sent back to the Watch after an action, carrying that action's own outcome.
    ///
    /// `statusMessage` is a parameter rather than instance state on the bridge deliberately. It was
    /// previously latched in a `pendingStatusMessage` property, written synchronously in `handle`
    /// and read inside a spawned `Task`. For two messages arriving back-to-back the enqueue order is
    /// `handle(A)`, `handle(B)`, `replyA`, `replyB` — so the reply to A read B's message and cleared
    /// the latch, and B then fell back to the generic "Ready for Round N". Both replies were wrong.
    /// Passing the message in makes that interleaving unrepresentable.
    @MainActor
    static func replySnapshot(
        for game: ScorekeeperGameState?,
        statusMessage: String
    ) -> ScorekeeperWatchSnapshot {
        var result = snapshot(from: game)
        result.statusMessage = statusMessage
        return result
    }

    @MainActor
    static func apply(
        _ action: ScorekeeperWatchActionPayload,
        to store: ScorekeeperStore
    ) -> ScorekeeperWatchActionResult {
        switch action.type {
        case .requestSnapshot:
            return ScorekeeperWatchActionResult(accepted: true, message: "Snapshot sent.")
        case .undoLastRound:
            guard store.activeGame?.rounds.isEmpty == false else {
                return ScorekeeperWatchActionResult(accepted: false, message: "No round to undo.")
            }
            store.deleteLastRound()
            return ScorekeeperWatchActionResult(accepted: true, message: "Last round removed.")
        case .addRound:
            guard let payload = action.draft else {
                return ScorekeeperWatchActionResult(accepted: false, message: "Round details missing.")
            }
            guard let suit = TrumpSuit(rawValue: payload.trumpSuitRaw) else {
                return ScorekeeperWatchActionResult(accepted: false, message: "Choose a valid trump suit.")
            }
            guard store.activeGame != nil else {
                return ScorekeeperWatchActionResult(accepted: false, message: "Start scorekeeper on iPhone first.")
            }

            var draft = ScorekeeperRoundDraft(nextDealerIndex: payload.dealerIndex)
            draft.dealerIndex = payload.dealerIndex
            draft.bidderIndex = payload.bidderIndex
            draft.bidAmount = payload.bidAmount
            draft.trumpSuit = suit
            draft.partner1Index = payload.partner1Index
            draft.partner2Index = payload.partner2Index
            draft.bidMade = payload.bidMade

            if let validation = draft.validationMessage {
                return ScorekeeperWatchActionResult(accepted: false, message: validation)
            }

            store.addRound(draft)
            return ScorekeeperWatchActionResult(accepted: true, message: "Round added.")
        }
    }
}

#if canImport(WatchConnectivity) && os(iOS)
@MainActor
@Observable final class ScorekeeperWatchBridge: NSObject {
    private weak var store: ScorekeeperStore?
    private weak var livePublisher: ScorekeeperLivePublishingController?

    var isReachable = false
    var lastMessage = "Apple Watch companion is ready."

    override init() {
        super.init()
        activate()
    }

    func configure(store: ScorekeeperStore, livePublisher: ScorekeeperLivePublishingController) {
        self.store = store
        self.livePublisher = livePublisher
        sendSnapshot()
    }

    func sendSnapshot() {
        let snapshot = ScorekeeperWatchActionHandler.snapshot(from: store?.activeGame)
        guard WCSession.isSupported() else { return }
        let encoded = ScorekeeperWatchMessageCodec.encode(snapshot)
        updateApplicationContext(encoded)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(encoded, replyHandler: nil)
        } else if WCSession.default.activationState == .activated {
            WCSession.default.transferUserInfo(encoded)
        }
    }

    private func activate() {
        guard WCSession.isSupported() else {
            lastMessage = "Apple Watch is not available on this device."
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func handle(_ action: ScorekeeperWatchActionPayload, replyHandler: (([String: Any]) -> Void)?) {
        guard let store else {
            replyHandler?(ScorekeeperWatchMessageCodec.encode(ScorekeeperWatchSnapshot.inactive))
            return
        }

        let result = ScorekeeperWatchActionHandler.apply(action, to: store)
        lastMessage = result.message

        Task { @MainActor in
            if result.accepted, let activeGame = store.activeGame {
                await livePublisher?.publish(game: activeGame)
            }
            // `result.message` is captured, not read back off the bridge — see `replySnapshot`.
            let snapshot = ScorekeeperWatchActionHandler.replySnapshot(
                for: store.activeGame,
                statusMessage: result.message
            )
            let encoded = ScorekeeperWatchMessageCodec.encode(snapshot)
            updateApplicationContext(encoded)
            replyHandler?(encoded)
            if WCSession.default.isReachable {
                WCSession.default.sendMessage(encoded, replyHandler: nil)
            } else {
                WCSession.default.transferUserInfo(encoded)
            }
        }
    }

    private func updateApplicationContext(_ encodedSnapshot: [String: Any]) {
        guard WCSession.default.activationState == .activated,
              !encodedSnapshot.isEmpty else {
            return
        }

        do {
            try WCSession.default.updateApplicationContext(encodedSnapshot)
        } catch {
            lastMessage = "Could not sync Watch snapshot: \(error.localizedDescription)"
        }
    }
}

extension ScorekeeperWatchBridge: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.lastMessage = error?.localizedDescription ?? "Apple Watch companion connected."
            self.sendSnapshot()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.sendSnapshot()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let action = ScorekeeperWatchMessageCodec.decode(ScorekeeperWatchActionPayload.self, from: message) else {
            replyHandler(ScorekeeperWatchMessageCodec.encode(ScorekeeperWatchSnapshot.inactive))
            return
        }
        Task { @MainActor in
            self.handle(action, replyHandler: replyHandler)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let action = ScorekeeperWatchMessageCodec.decode(ScorekeeperWatchActionPayload.self, from: userInfo) else {
            return
        }
        Task { @MainActor in
            self.handle(action, replyHandler: nil)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
#endif
