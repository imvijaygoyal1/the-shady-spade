import Foundation
import SwiftUI
import WatchConnectivity

@Observable final class WatchScorekeeperViewModel: NSObject {
    struct TrumpChoice {
        let raw: String
        let name: String
    }

    static let trumpSuits = [
        TrumpChoice(raw: "♠", name: "Spades"),
        TrumpChoice(raw: "♥", name: "Hearts"),
        TrumpChoice(raw: "♦", name: "Diamonds"),
        TrumpChoice(raw: "♣", name: "Clubs")
    ]

    var snapshot = ScorekeeperWatchSnapshot.inactive
    var connectionStatus = "Waiting for iPhone"
    var syncStatus = "Not synced yet"
    var draft = ScorekeeperWatchRoundDraftPayload(
        dealerIndex: 0,
        bidderIndex: 1,
        bidAmount: 130,
        trumpSuitRaw: "♠",
        partner1Index: 2,
        partner2Index: 3,
        bidMade: true
    )

    override init() {
        super.init()
        activate()
    }

    var eligibleBidderIndices: [Int] {
        (0..<6).filter { $0 != draft.dealerIndex }
    }

    var eligiblePartner1Indices: [Int] {
        (0..<6).filter { $0 != draft.bidderIndex && $0 != draft.partner2Index }
    }

    var eligiblePartner2Indices: [Int] {
        (0..<6).filter { $0 != draft.bidderIndex && $0 != draft.partner1Index }
    }

    var validationMessage: String? {
        guard draft.bidderIndex != draft.dealerIndex else {
            return "Dealer cannot bid."
        }
        guard draft.partner1Index != draft.bidderIndex,
              draft.partner2Index != draft.bidderIndex else {
            return "Partners cannot be bidder."
        }
        guard draft.partner1Index != draft.partner2Index else {
            return "Partners must differ."
        }
        guard (130...240).contains(draft.bidAmount) else {
            return "Bid must be 130-240."
        }
        return nil
    }

    func playerName(_ index: Int) -> String {
        snapshot.playerNames[safe: index] ?? "Player \(index + 1)"
    }

    func resetDraft() {
        let dealer = snapshot.nextDealerIndex
        let bidder = (dealer + 1) % 6
        draft = ScorekeeperWatchRoundDraftPayload(
            dealerIndex: dealer,
            bidderIndex: bidder,
            bidAmount: 130,
            trumpSuitRaw: "♠",
            partner1Index: firstAvailable(excluding: [bidder]),
            partner2Index: firstAvailable(excluding: [bidder, firstAvailable(excluding: [bidder])]),
            bidMade: true
        )
    }

    func requestSnapshot() {
        connectionStatus = "Refreshing from iPhone"
        send(.requestSnapshot)
    }

    func addRound() {
        guard validationMessage == nil else { return }
        send(ScorekeeperWatchActionPayload(type: .addRound, draft: draft))
    }

    func undoLastRound() {
        send(.undoLastRound)
    }

    private func firstAvailable(excluding excluded: Set<Int>) -> Int {
        (0..<6).first { !excluded.contains($0) } ?? 0
    }

    private func activate() {
        guard WCSession.isSupported() else {
            connectionStatus = "iPhone unavailable"
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        Task { @MainActor in
            self.applyLatestApplicationContext()
        }
    }

    private func send(_ action: ScorekeeperWatchActionPayload) {
        guard WCSession.default.activationState == .activated else {
            connectionStatus = "Open iPhone app"
            return
        }
        let message = ScorekeeperWatchMessageCodec.encode(action)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message) { [weak self] reply in
                Task { @MainActor in
                    self?.apply(reply)
                }
            } errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.connectionStatus = error.localizedDescription
                }
            }
        } else {
            WCSession.default.transferUserInfo(message)
            connectionStatus = "Queued for iPhone"
        }
    }

    @MainActor
    private func apply(_ message: [String: Any]) {
        guard let snapshot = ScorekeeperWatchMessageCodec.decode(ScorekeeperWatchSnapshot.self, from: message) else {
            return
        }
        self.snapshot = snapshot
        resetDraft()
        self.connectionStatus = WCSession.default.isReachable ? "Connected to iPhone" : "Open iPhone app"
        self.syncStatus = "Last synced just now"
    }

    @MainActor
    private func applyLatestApplicationContext() {
        guard !WCSession.default.receivedApplicationContext.isEmpty else {
            return
        }
        apply(WCSession.default.receivedApplicationContext)
    }
}

extension WatchScorekeeperViewModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.connectionStatus = error?.localizedDescription ?? "Connected to iPhone"
            self.applyLatestApplicationContext()
            self.requestSnapshot()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.connectionStatus = session.isReachable ? "Connected to iPhone" : "Open iPhone app"
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.apply(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            self.apply(userInfo)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.apply(applicationContext)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
