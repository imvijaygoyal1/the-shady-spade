import SwiftUI
import Observation
import FirebaseFirestore
import OSLog

private let ogVMLog = Logger(subsystem: "com.vijaygoyal.theshadyspade", category: "OnlineGameViewModel")

// MARK: - Phase

enum OnlineGamePhase: String {
    case dealing, lookingAtCards, bidding, calling, playing, roundComplete, gameOver
}

// MARK: - ViewModel

@Observable @MainActor
final class OnlineGameViewModel {

    static let winningScore = 500

    // MARK: Identity
    let myPlayerIndex: Int
    let isHost: Bool
    let sessionCode: String
    var playerNames: [String]
    var playerAvatars: [String]

    // MARK: Published — synced from Firestore
    var phase: OnlineGamePhase = .dealing
    var roundNumber: Int = 1
    var dealerIndex: Int = 0
    var currentActionPlayer: Int = -1
    var bids: [Int] = Array(repeating: -1, count: 6)
    var highBid: Int = 0
    var highBidderIndex: Int = -1
    var trumpSuit: TrumpSuit = .spades
    var calledCard1: String = ""
    var calledCard2: String = ""
    var partner1Index: Int = -1
    var partner2Index: Int = -1
    var currentTrick: [(playerIndex: Int, card: Card)] = []
    var currentLeaderIndex: Int = 0
    var trickNumber: Int = 0
    var lastCompletedTrick: [(playerIndex: Int, card: Card)] = []
    var lastTrickWinnerIndex: Int = -1
    var lastTrickPoints: Int = 0
    var completedTricks: [[(playerIndex: Int, card: Card)]] = []
    var trickWinners: [Int] = []
    var wonPointsPerPlayer: [Int] = Array(repeating: 0, count: 6)
    var runningScores: [Int] = Array(repeating: 0, count: 6)
    var message: String = ""
    /// Accumulates one HistoryRound per completed round — used by LB4 fix so
    /// multi-round games report all rounds to the leaderboard, not just the last.
    var completedRounds: [HistoryRound] = []
    var myHand: [Card] = []
    var myHandSorted: [Card] { myHand.sortedBySuit() }

    // MARK: Bidding cycle state (synced via Firestore)
    var playerHasPassed: [Bool] = Array(repeating: false, count: 6)
    var bidHistory: [(playerIndex: Int, amount: Int)] = []

    // MARK: UI state (local only — not synced from Firestore)
    var trumpSuitSelection: TrumpSuit = .spades
    var calledCard1Rank: String = "A"
    var calledCard1Suit: String = "♥"
    var calledCard2Rank: String = "K"
    var calledCard2Suit: String = "♦"
    var humanBidAmount: Double = 130
    var biddingToastMessage: String? = nil
    var bidWinnerInfo: BidWinnerInfo? = nil
    var partnerRevealMessage: String? = nil
    var errorMessage: String? = nil

    /// First player to bid (highBid == 0) must bid; all others may pass.
    var humanCanPass: Bool { highBid > 0 }

    // MARK: AI seats (custom game)
    var aiSeats: [Int] = []

    // MARK: Host-only private state
    private var allHands: [[Card]] = Array(repeating: [], count: 6)
    private var hostPartner1: Int = -1
    private var hostPartner2: Int = -1
    private var hostCalledCard1: String = ""
    private var hostCalledCard2: String = ""
    private var listener: ListenerRegistration?
    private var lastProcessedNonce: String = ""
    private var lastActionSentAt: Date = .distantPast
    /// Prevents two concurrent AI tasks from both passing the post-sleep guard and
    /// double-playing. Reset to false before every recursive re-trigger so the next
    /// processAITurnIfNeeded call can proceed.
    private var isProcessingAI = false

    // MARK: Presence tracking
    private var presenceTimer: Timer?
    private var monitoringTimer: Timer?
    private var prevAISeats: Set<Int> = []

    // Set to true when this player's own seat becomes AI mid-game (host removed them)
    var wasRemovedFromGame = false

    // MARK: Partner reveal tracking (all devices)
    private var hasInitializedCalling = false
    // Revealed in play order (slot 2 = first reveal, slot 3 = second reveal)
    var revealedPartner1Index: Int = -1
    var revealedPartner2Index: Int = -1

    // MARK: - Init

    init(
        myPlayerIndex: Int,
        isHost: Bool,
        sessionCode: String,
        playerNames: [String],
        playerAvatars: [String] = [],
        dealerIndex: Int,
        roundNumber: Int,
        aiSeats: [Int] = []
    ) {
        self.myPlayerIndex = myPlayerIndex
        self.isHost = isHost
        self.sessionCode = sessionCode
        self.playerNames = playerNames
        self.playerAvatars = playerAvatars
        self.dealerIndex = dealerIndex
        self.roundNumber = roundNumber
        self.aiSeats = aiSeats
    }

    func cleanup() {
        listener?.remove()
    }

    // MARK: - Computed

    var isMyTurn: Bool { myPlayerIndex == currentActionPlayer }

    var humanMinBid: Int { max(130, highBid + 5) }

    var humanMustPass: Bool { humanMinBid > 250 }

    var offenseSet: Set<Int> {
        Set([highBidderIndex, partner1Index, partner2Index].filter { $0 >= 0 })
    }

    var callingValid: Bool {
        let c1 = calledCard1Rank + calledCard1Suit
        let c2 = calledCard2Rank + calledCard2Suit
        guard c1 != c2 else { return false }
        let handIds = Set(myHand.map(\.id))
        return !handIds.contains(c1) && !handIds.contains(c2)
    }

    var validCardsToPlay: Set<String> {
        if currentTrick.isEmpty { return Set(myHand.map(\.id)) }
        let ledSuit = currentTrick[0].card.suit
        let canFollow = myHand.filter { $0.suit == ledSuit }
        return Set((canFollow.isEmpty ? myHand : canFollow).map(\.id))
    }

    var currentTrickWinnerIndex: Int? {
        guard !currentTrick.isEmpty else { return nil }
        return trickWinnerIndex(trick: currentTrick)
    }

    var bidHistoryOrdered: [(playerIndex: Int, amount: Int)] { bidHistory }

    var offensePoints: Int {
        (0..<6).filter { offenseSet.contains($0) }.map { wonPointsPerPlayer[$0] }.reduce(0, +)
    }

    var defensePoints: Int {
        (0..<6).filter { !offenseSet.contains($0) }.map { wonPointsPerPlayer[$0] }.reduce(0, +)
    }

    func playerName(_ index: Int) -> String {
        guard index >= 0 && index < playerNames.count else { return "Guest \(index + 1)" }
        let n = playerNames[index]
        return n.isEmpty ? "Guest \(index + 1)" : n
    }

    func playerAvatar(_ index: Int) -> String {
        guard index >= 0 && index < playerAvatars.count else { return "🃏" }
        let a = playerAvatars[index]
        return a.isEmpty ? "🃏" : a
    }

    func buildRound(nextRoundNumber: Int) -> Round {
        Round(
            roundNumber: nextRoundNumber,
            dealerIndex: dealerIndex,
            bidderIndex: max(0, highBidderIndex),
            bidAmount: max(130, highBid),
            trumpSuit: trumpSuit,
            callCard1: calledCard1,
            callCard2: calledCard2,
            partner1Index: max(0, partner1Index),
            partner2Index: max(0, partner2Index),
            offensePointsCaught: offensePoints,
            defensePointsCaught: defensePoints
        )
    }

    // MARK: - Start Game (host only)

    func startGame() async {
        guard isHost else { return }
        let db = Firestore.firestore()
        let ref = db.collection("sessions").document(sessionCode)

        // Show dealing animation on all clients first
        let dealingGs: [String: Any] = ["phase": OnlineGamePhase.dealing.rawValue]
        try? await ref.updateData(["gameState": dealingGs])

        // Wait for animation to play (~3s)
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        // Deal
        let deck = ComputerGameViewModel.freshDeck().shuffled()
        allHands = (0..<6).map { i in Array(deck[(i * 8)..<((i + 1) * 8)]) }

        // Hands dict for Firestore
        var handsDict: [String: Any] = [:]
        for i in 0..<6 { handsDict["\(i)"] = allHands[i].map(\.id) }

        // Reset host tracking
        hostPartner1 = -1; hostPartner2 = -1
        hostCalledCard1 = ""; hostCalledCard2 = ""

        let firstBidder = (dealerIndex + 1) % 6
        let gs: [String: Any] = [
            "phase": OnlineGamePhase.lookingAtCards.rawValue,
            "roundNumber": roundNumber,
            "dealerIndex": dealerIndex,
            "currentActionPlayer": firstBidder,
            "bids": Array(repeating: -1, count: 6),
            "highBid": 0,
            "highBidderIndex": -1,
            "playerHasPassed": Array(repeating: false, count: 6),
            "bidHistory": [] as [[String: Any]],
            "trumpSuit": TrumpSuit.spades.rawValue,
            "calledCard1": "",
            "calledCard2": "",
            "partner1Index": -1,
            "partner2Index": -1,
            "currentTrick": [] as [[String: Any]],
            "currentLeaderIndex": firstBidder,
            "trickNumber": 0,
            "wonPointsPerPlayer": Array(repeating: 0, count: 6),
            "runningScores": runningScores,
            "message": "Study your cards, then the host will start bidding."
        ]
        try? await ref.updateData([
            "gameState": gs,
            "hands": handsDict,
            "pendingAction": [:] as [String: Any]
        ])
    }

    func startNextRound() async {
        guard isHost else { return }
        dealerIndex = (dealerIndex + 1) % 6
        roundNumber += 1
        await startGame()
    }

    func startBidding() async {
        guard isHost else { return }
        let firstBidder = (dealerIndex + 1) % 6
        let gs = buildGS(
            phase: .bidding,
            currentActionPlayer: firstBidder,
            bids: Array(repeating: -1, count: 6),
            highBid: 0,
            highBidderIndex: -1,
            playerHasPassed: Array(repeating: false, count: 6),
            bidHistory: [],
            message: "\(playerName(firstBidder)) starts the bid!"
        )
        await criticalWrite(["gameState": gs, "pendingAction": [:] as [String: Any]])
    }

    // MARK: - Presence tracking

    func startPresenceTracking() {
        guard !isHost else { return }
        let db = Firestore.firestore()
        let ref = db.collection("sessions").document(sessionCode)
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                try? await ref.updateData([
                    "presence.\(self.myPlayerIndex)": Timestamp()
                ])
            }
        }
        presenceTimer?.fire()
    }

    func stopPresenceTracking() {
        presenceTimer?.invalidate()
        presenceTimer = nil
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }

    func removePlayerMidGame(atIndex index: Int) async {
        guard isHost, index != myPlayerIndex, !aiSeats.contains(index) else { return }
        let db = Firestore.firestore()
        let ref = db.collection("sessions").document(sessionCode)
        guard let data = (try? await ref.getDocument())?.data(),
              var slotsData = data["playerSlots"] as? [[String: Any]] else { return }

        var currentAISeats = (data["aiSeats"] as? [Any] ?? []).compactMap {
            ($0 as? Int) ?? ($0 as? Int64).map(Int.init)
        }
        let removedName = slotsData[safe: index]?["name"] as? String ?? "Player"
        let aiNamePool = ["Drew", "Jamie", "Casey", "Morgan", "Riley"]
        let usedNames = slotsData.compactMap { $0["name"] as? String }
        let aiName = aiNamePool.first { !usedNames.contains($0) } ?? "Bot"

        slotsData[index] = ["uid": "AI-\(index)", "name": aiName, "avatar": "🤖", "joined": true]
        currentAISeats.append(index)
        currentAISeats.sort()

        try? await ref.updateData([
            "playerSlots": slotsData,
            "aiSeats": currentAISeats,
            "gameState.aiSeats": currentAISeats,
            "removedSlot": index,
            "gameState.message": "\(removedName) was removed. AI took over."
        ])
    }

    func monitorPresence() {
        guard isHost else { return }
        let db = Firestore.firestore()
        let ref = db.collection("sessions").document(sessionCode)

        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let snap = try? await ref.getDocument()
                guard let data = snap?.data(),
                      let presence = data["presence"] as? [String: Any]
                else { return }

                let now = Date()
                var slotsData = data["playerSlots"] as? [[String: Any]] ?? []
                var currentAISeats = (data["aiSeats"] as? [Any] ?? []).compactMap {
                    ($0 as? Int) ?? ($0 as? Int64).map(Int.init)
                }
                var droppedNames: [String] = []
                var changed = false

                let aiNamePool = ["Drew", "Jamie", "Casey", "Morgan", "Riley"]

                for i in 0..<6 {
                    guard !currentAISeats.contains(i), i != self.myPlayerIndex else { continue }
                    let lastSeen = (presence["\(i)"] as? Timestamp)?.dateValue()
                    let isDropped = lastSeen == nil || now.timeIntervalSince(lastSeen!) > 30
                    if isDropped, let name = slotsData[safe: i]?["name"] as? String {
                        let usedNames = slotsData.compactMap { $0["name"] as? String }
                        let aiName = aiNamePool.first { !usedNames.contains($0) } ?? "Bot"
                        slotsData[i] = ["uid": "AI-\(i)", "name": aiName, "avatar": "🤖", "joined": true]
                        currentAISeats.append(i)
                        currentAISeats.sort()
                        droppedNames.append(name)
                        changed = true
                    }
                }

                if changed {
                    let droppedMsg = droppedNames.joined(separator: ", ")
                    try? await ref.updateData([
                        "playerSlots": slotsData,
                        "aiSeats": currentAISeats,
                        "gameState.aiSeats": currentAISeats,
                        "droppedPlayers": FieldValue.arrayUnion(droppedNames),
                        "gameState.message": "\(droppedMsg) left. AI took over."
                    ])
                }
            }
        }
    }

    // MARK: - Listener

    func attachListener() {
        let db = Firestore.firestore()
        listener = db.collection("sessions").document(sessionCode)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                // Fix 7: handle listener errors — Firestore listeners can die silently on
                // network failure or session expiry. Re-attach after a delay so the host
                // continues receiving state updates and AI turns don't freeze permanently.
                if let error = error {
                    ogVMLog.error("[listener] Firestore error: \(error.localizedDescription) — reattaching in 3s")
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        self?.reattachListener()
                    }
                    return
                }
                guard let data = snapshot?.data() else { return }
                Task { @MainActor [weak self] in
                    await self?.handleSnapshot(data)
                }
            }
    }

    private func reattachListener() {
        listener?.remove()
        listener = nil
        attachListener()
    }

    private func handleSnapshot(_ data: [String: Any]) async {
        // Sync aiSeats from session document root, or gameState.aiSeats if updated mid-game
        let rawAI = (data["aiSeats"] as? [Any])
            ?? (data["gameState"] as? [String: Any])?["aiSeats"] as? [Any]
            ?? []
        aiSeats = rawAI.compactMap { ($0 as? Int) ?? ($0 as? Int64).map(Int.init) }

        // Detect if this player was removed mid-game (their seat just entered aiSeats)
        if !isHost && !prevAISeats.contains(myPlayerIndex) && Set(aiSeats).contains(myPlayerIndex) {
            wasRemovedFromGame = true
        }
        prevAISeats = Set(aiSeats)

        // Parse game state
        if let gs = data["gameState"] as? [String: Any] {
            parseGameState(gs)
        }

        // Parse hands
        if let handsData = data["hands"] as? [String: Any] {
            // Parse my hand
            if let myCards = handsData["\(myPlayerIndex)"] as? [String] {
                myHand = myCards.compactMap { parseCard($0) }
            }
            // Host: sync allHands for AI use
            if isHost {
                for i in 0..<6 {
                    if let cards = handsData["\(i)"] as? [String] {
                        allHands[i] = cards.compactMap { parseCard($0) }
                    }
                }
            }
        }

        // Host: process pending action or trigger AI
        if isHost, let actionData = data["pendingAction"] as? [String: Any],
           let nonce = actionData["nonce"] as? String,
           !nonce.isEmpty, nonce != lastProcessedNonce {
            await processPendingAction(actionData)
        } else if isHost {
            await processAITurnIfNeeded()
        }
    }

    private func parseGameState(_ gs: [String: Any]) {
        func i(_ key: String) -> Int { (gs[key] as? Int) ?? (gs[key] as? Int64).map(Int.init) ?? 0 }
        func iDef(_ key: String, _ def: Int) -> Int { (gs[key] as? Int) ?? (gs[key] as? Int64).map(Int.init) ?? def }

        let newPhase = OnlineGamePhase(rawValue: gs["phase"] as? String ?? "") ?? .dealing
        let newRoundNumber = i("roundNumber")
        let newCurrentActionPlayer = iDef("currentActionPlayer", -1)
        let newP1 = iDef("partner1Index", -1)
        let newP2 = iDef("partner2Index", -1)

        // Partner reveal detection — index being >= 0 IS the boolean (no separate flags)
        // partner1Index from Firestore maps directly to revealedPartner1Index (card1 → slot1)
        // partner2Index from Firestore maps directly to revealedPartner2Index (card2 → slot2)
        if newPhase == .playing || newPhase == .roundComplete || newPhase == .gameOver {
            if newP1 >= 0 && revealedPartner1Index == -1 {
                revealedPartner1Index = newP1
                let name = playerName(newP1)
                let isSelf = newP1 == myPlayerIndex
                partnerRevealMessage = isSelf ? "You are a partner!" : "\(name) is a partner!"
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    self.partnerRevealMessage = nil
                }
            }
            if newP2 >= 0 && revealedPartner2Index == -1 {
                revealedPartner2Index = newP2
                let name = playerName(newP2)
                let isSelf = newP2 == myPlayerIndex
                let msg = isSelf ? "You are a partner!" : "\(name) is a partner!"
                if msg != partnerRevealMessage {
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        self.partnerRevealMessage = msg
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        self.partnerRevealMessage = nil
                    }
                }
            }
        }

        // Reset index slots on new round — index being -1 means unrevealed
        if newP1 == -1 { revealedPartner1Index = -1 }
        if newP2 == -1 { revealedPartner2Index = -1 }

        // Bid winner announcement (detect .bidding → .calling before updating phase)
        if newPhase == .calling && phase == .bidding {
            let winnerIdx = iDef("highBidderIndex", -1)
            let winnerBid = i("highBid")
            if winnerIdx >= 0 {
                bidWinnerInfo = BidWinnerInfo(name: playerName(winnerIdx), avatar: "", bid: winnerBid)
                if winnerIdx != myPlayerIndex {
                    // Not our win — auto-dismiss after 2.5s
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                        self?.bidWinnerInfo = nil
                    }
                }
                // Human winner: banner stays until they tap Continue (proceedFromBidWinner)
            }
        }
        // If the calling phase ended before the 2.5s auto-dismiss fired, the banner
        // would remain on-screen during play, absorbing all card taps. Clear it now.
        if newPhase == .playing || newPhase == .roundComplete || newPhase == .gameOver {
            bidWinnerInfo = nil
        }

        // Update published props
        phase = newPhase
        roundNumber = newRoundNumber
        dealerIndex = i("dealerIndex")
        currentActionPlayer = newCurrentActionPlayer
        if let bidsAny = gs["bids"] as? [Any] {
            bids = bidsAny.map { ($0 as? Int) ?? ($0 as? Int64).map(Int.init) ?? -1 }
        }
        if let passedAny = gs["playerHasPassed"] as? [Any] {
            playerHasPassed = passedAny.map { ($0 as? Bool) ?? false }
        }
        if let histArr = gs["bidHistory"] as? [[String: Any]] {
            let parsed = histArr.compactMap { entry -> (playerIndex: Int, amount: Int)? in
                guard let pi  = (entry["pi"]  as? Int) ?? (entry["pi"]  as? Int64).map(Int.init),
                      let amt = (entry["amt"] as? Int) ?? (entry["amt"] as? Int64).map(Int.init)
                else { return nil }
                return (playerIndex: pi, amount: amt)
            }
            var seen = Set<Int>()
            bidHistory = parsed.filter { seen.insert($0.playerIndex).inserted }
        }
        highBid = i("highBid")
        highBidderIndex = iDef("highBidderIndex", -1)

        // Show toast when bidding phase begins
        if newPhase == .bidding && phase != .bidding {
            biddingToastMessage = "\(playerName(newCurrentActionPlayer)) starts the bid!"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.biddingToastMessage = nil
            }
        }
        if newPhase != .calling {
            if let ts = gs["trumpSuit"] as? String, let suit = TrumpSuit(rawValue: ts) {
                trumpSuit = suit
            }
        }
        calledCard1 = gs["calledCard1"] as? String ?? ""
        calledCard2 = gs["calledCard2"] as? String ?? ""
        partner1Index = newP1
        partner2Index = newP2
        let prevTrickNumber = trickNumber
        let prevWonTotal = wonPointsPerPlayer.reduce(0, +)
        let newTrickNumber = i("trickNumber")
        currentLeaderIndex = i("currentLeaderIndex")
        trickNumber = newTrickNumber

        // Trick just completed — capture it as lastCompletedTrick
        if newTrickNumber > prevTrickNumber && !currentTrick.isEmpty {
            lastCompletedTrick = currentTrick
            lastTrickWinnerIndex = currentLeaderIndex
            lastTrickPoints = currentTrick.map { $0.card.pointValue }.reduce(0, +)
            completedTricks.append(currentTrick)
            trickWinners.append(currentLeaderIndex)
        }
        // New round — reset
        if newTrickNumber == 0 {
            lastCompletedTrick = []
            lastTrickWinnerIndex = -1
            lastTrickPoints = 0
            completedTricks = []
            trickWinners = []
        }

        if let wpp = gs["wonPointsPerPlayer"] as? [Any] {
            wonPointsPerPlayer = wpp.map { ($0 as? Int) ?? ($0 as? Int64).map(Int.init) ?? 0 }
        }
        if let rs = gs["runningScores"] as? [Any] {
            runningScores = rs.map { ($0 as? Int) ?? ($0 as? Int64).map(Int.init) ?? 0 }
        }
        message = gs["message"] as? String ?? ""

        // Parse currentTrick
        if let trickArr = gs["currentTrick"] as? [[String: Any]] {
            currentTrick = trickArr.compactMap { entry in
                guard let pi = (entry["pi"] as? Int) ?? (entry["pi"] as? Int64).map(Int.init),
                      pi >= 0 && pi < 6,
                      let cardId = entry["card"] as? String,
                      let card = parseCard(cardId) else { return nil }
                return (playerIndex: pi, card: card)
            }
        }

        // Calling phase defaults for this player
        if newPhase == .calling && newCurrentActionPlayer == myPlayerIndex && !hasInitializedCalling {
            hasInitializedCalling = true
            setSmartCallingDefaults()
        }
        if newPhase != .calling { hasInitializedCalling = false }

        // Bid amount update when it's our turn to bid
        if newPhase == .bidding && newCurrentActionPlayer == myPlayerIndex {
            humanBidAmount = Double(max(130, highBid + 5))
        }

        // LB4: Accumulate a HistoryRound whenever a round ends so the leaderboard
        // receives stats for every round, not just the last one.
        if (newPhase == .roundComplete || newPhase == .gameOver),
           completedRounds.last?.roundNumber != roundNumber {
            completedRounds.append(HistoryRound(
                roundNumber: roundNumber,
                dealerIndex: dealerIndex,
                bidderIndex: highBidderIndex >= 0 ? highBidderIndex : 0,
                bidAmount: highBid,
                trumpSuit: trumpSuit,
                callCard1: calledCard1,
                callCard2: calledCard2,
                partner1Index: partner1Index >= 0 ? partner1Index : 0,
                partner2Index: partner2Index >= 0 ? partner2Index : 0,
                offensePointsCaught: offensePoints,
                defensePointsCaught: defensePoints,
                runningScores: runningScores
            ))
        }

        // No next-hand confirmation overlay in online mode.
        // The host controls round progression via Firestore.
    }

    private func parseCard(_ id: String) -> Card? {
        guard !id.isEmpty, let lastChar = id.last else { return nil }
        let rank = String(id.dropLast())
        guard !rank.isEmpty else { return nil }
        return Card(rank: rank, suit: String(lastChar))
    }

    // MARK: - Player Actions

    func placeBid(_ amount: Int) async {
        guard Date().timeIntervalSince(lastActionSentAt) > 0.3 else { return }
        lastActionSentAt = Date()
        let action: [String: Any] = [
            "nonce": UUID().uuidString,
            "playerIndex": myPlayerIndex,
            "type": "bid",
            "bidAmount": amount
        ]
        await criticalWrite(["pendingAction": action])
    }

    func pass() async {
        guard Date().timeIntervalSince(lastActionSentAt) > 0.3 else { return }
        lastActionSentAt = Date()
        let action: [String: Any] = [
            "nonce": UUID().uuidString,
            "playerIndex": myPlayerIndex,
            "type": "pass"
        ]
        await criticalWrite(["pendingAction": action])
    }

    func proceedFromBidWinner() {
        bidWinnerInfo = nil
    }


    func confirmCalling() async {
        guard Date().timeIntervalSince(lastActionSentAt) > 0.3 else { return }
        lastActionSentAt = Date()
        let c1 = calledCard1Rank + calledCard1Suit
        let c2 = calledCard2Rank + calledCard2Suit
        let action: [String: Any] = [
            "nonce": UUID().uuidString,
            "playerIndex": myPlayerIndex,
            "type": "callCards",
            "trump": trumpSuitSelection.rawValue,
            "calledCard1": c1,
            "calledCard2": c2
        ]
        await criticalWrite(["pendingAction": action])
    }

    func playCard(_ card: Card) async {
        guard Date().timeIntervalSince(lastActionSentAt) > 0.3 else { return }
        lastActionSentAt = Date()
        let action: [String: Any] = [
            "nonce": UUID().uuidString,
            "playerIndex": myPlayerIndex,
            "type": "playCard",
            "cardId": card.id
        ]
        await criticalWrite(["pendingAction": action])
    }

    // MARK: - Host: Process Pending Action

    private func processPendingAction(_ actionData: [String: Any]) async {
        guard let nonce = actionData["nonce"] as? String,
              let type = actionData["type"] as? String,
              let playerIndex = (actionData["playerIndex"] as? Int) ??
                  (actionData["playerIndex"] as? Int64).map(Int.init)
        else { return }

        guard playerIndex >= 0 && playerIndex < 6 else { return }
        guard playerIndex == currentActionPlayer else { return }

        lastProcessedNonce = nonce

        switch type {
        case "bid":
            let amount = (actionData["bidAmount"] as? Int) ??
                (actionData["bidAmount"] as? Int64).map(Int.init) ?? 0
            guard amount >= 130 && amount <= 250 else { return }
            var newBids = bids
            newBids[playerIndex] = amount
            var newHighBid = highBid
            var newHighBidder = highBidderIndex
            if amount > newHighBid { newHighBid = amount; newHighBidder = playerIndex }
            let newPassed = playerHasPassed       // bidder stays active (not marked passed)
            var newHistory = bidHistory
            newHistory.append((playerIndex: playerIndex, amount: amount))

            // End bidding when only one player hasn't passed; otherwise rotate clockwise
            let activePlayers = (0..<6).filter { !newPassed[$0] }
            if activePlayers.count <= 1 {
                await concludeBidding(bids: newBids, highBid: newHighBid, highBidder: newHighBidder)
            } else {
                var next = (playerIndex + 1) % 6
                while newPassed[next] { next = (next + 1) % 6 }
                let gs = buildGS(phase: .bidding, currentActionPlayer: next,
                    bids: newBids, highBid: newHighBid, highBidderIndex: newHighBidder,
                    playerHasPassed: newPassed, bidHistory: newHistory,
                    message: "\(playerName(playerIndex)) bid \(amount)")
                await criticalWrite(["gameState": gs, "pendingAction": [:] as [String: Any]])
            }

        case "pass":
            var newBids = bids
            newBids[playerIndex] = 0
            var newPassed = playerHasPassed
            newPassed[playerIndex] = true
            var newHistory = bidHistory
            newHistory.append((playerIndex: playerIndex, amount: 0))

            // End bidding when only one active player remains
            let activePlayers = (0..<6).filter { !newPassed[$0] }
            if activePlayers.count <= 1 {
                await concludeBidding(bids: newBids, highBid: highBid, highBidder: highBidderIndex)
            } else {
                var next = (playerIndex + 1) % 6
                while newPassed[next] { next = (next + 1) % 6 }
                let gs = buildGS(phase: .bidding, currentActionPlayer: next,
                    bids: newBids, highBid: highBid, highBidderIndex: highBidderIndex,
                    playerHasPassed: newPassed, bidHistory: newHistory,
                    message: "\(playerName(playerIndex)) passed")
                await criticalWrite(["gameState": gs, "pendingAction": [:] as [String: Any]])
            }

        case "callCards":
            let trumpStr = actionData["trump"] as? String ?? TrumpSuit.spades.rawValue
            let c1 = actionData["calledCard1"] as? String ?? ""
            let c2 = actionData["calledCard2"] as? String ?? ""
            // Validate cards exist in the deck, are distinct, and the bidder doesn't hold them
            let validCardIds: Set<String> = {
                let ranks = ["A","K","Q","J","10","9","8","7","6","5","4","3","2"]
                let suits = ["♠","♥","♦","♣"]
                return Set(ranks.flatMap { r in suits.map { r + $0 } })
            }()
            guard validCardIds.contains(c1), validCardIds.contains(c2), c1 != c2,
                  !allHands[playerIndex].map(\.id).contains(c1),
                  !allHands[playerIndex].map(\.id).contains(c2) else { return }
            let (p1, p2) = resolvePartners(c1: c1, c2: c2)
            hostPartner1 = p1; hostPartner2 = p2
            hostCalledCard1 = c1; hostCalledCard2 = c2

            let leader = highBidderIndex
            var gs = buildGS(phase: .playing, currentActionPlayer: leader,
                bids: bids, highBid: highBid, highBidderIndex: highBidderIndex,
                message: "\(playerName(highBidderIndex)) called — play begins!")
            gs["trumpSuit"] = trumpStr
            gs["calledCard1"] = c1
            gs["calledCard2"] = c2
            gs["partner1Index"] = -1
            gs["partner2Index"] = -1
            gs["currentLeaderIndex"] = leader
            gs["trickNumber"] = 0
            gs["currentTrick"] = [] as [[String: Any]]
            gs["wonPointsPerPlayer"] = Array(repeating: 0, count: 6)
            await criticalWrite(["gameState": gs, "pendingAction": [:] as [String: Any]])

        case "playCard":
            let cardId = actionData["cardId"] as? String ?? ""
            guard let card = parseCard(cardId),
                  allHands[playerIndex].contains(where: { $0.id == cardId }) else {
                // Card invalid or already played (stale action). Reset the AI lock flag
                // first — a sleeping AI task may hold it, which would cause the re-trigger
                // below to bail silently and leave the game frozen.
                isProcessingAI = false
                if aiSeats.contains(currentActionPlayer) {
                    await processAITurnIfNeeded()
                }
                return
            }

            allHands[playerIndex].removeAll { $0.id == cardId }

            var handsDict: [String: Any] = [:]
            for i in 0..<6 { handsDict["\(i)"] = allHands[i].map(\.id) }

            var newTrick = currentTrick
            newTrick.append((playerIndex: playerIndex, card: card))

            // Check partner reveal
            var newP1 = partner1Index
            var newP2 = partner2Index
            if cardId == hostCalledCard1 && newP1 == -1 { newP1 = hostPartner1 }
            if cardId == hostCalledCard2 && newP2 == -1 { newP2 = hostPartner2 }

            let trickData = newTrick.map { e -> [String: Any] in ["pi": e.playerIndex, "card": e.card.id] }

            if newTrick.count == 6 {
                // Show all 6 cards to every client before resolving so the
                // 6th card has a chance to render on all screens.
                var showGs = buildGS(phase: .playing, currentActionPlayer: -1,
                    bids: bids, highBid: highBid, highBidderIndex: highBidderIndex,
                    message: "\(playerName(playerIndex)) played \(card.rank)\(card.suit)")
                showGs["currentTrick"] = trickData
                showGs["partner1Index"] = newP1
                showGs["partner2Index"] = newP2
                let showOk = await criticalWrite(["gameState": showGs, "hands": handsDict, "pendingAction": [:] as [String: Any]])
                // Fix 5: if the show-state write fails, apply state locally so the host's
                // trick display is consistent during the 1s pause. Clients will re-sync
                // on the resolution write that follows.
                if !showOk {
                    ogVMLog.error("[playCard] 6th-card show-state write failed — applying locally")
                    currentTrick = newTrick
                    partner1Index = newP1
                    partner2Index = newP2
                    currentActionPlayer = -1
                }

                // Capture accumulated state before sleeping — a Firestore snapshot
                // arriving during the sleep triggers handleSnapshot on the host which
                // calls parseGameState, potentially overwriting these instance properties.
                let capturedWonPoints = wonPointsPerPlayer
                let capturedTrickNumber = trickNumber
                let capturedRunningScores = runningScores

                // 1 second for clients to render the 6th card
                try? await Task.sleep(nanoseconds: 1_000_000_000)

                let winner = trickWinnerIndex(trick: newTrick)
                let pts = newTrick.map(\.card.pointValue).reduce(0, +)
                var newWon = capturedWonPoints
                newWon[winner] += pts
                let newTrickNum = capturedTrickNumber + 1

                if newTrickNum == 8 {
                    let offSet = Set([highBidderIndex, hostPartner1, hostPartner2].filter { $0 >= 0 })
                    let offPts = (0..<6).filter { offSet.contains($0) }.map { newWon[$0] }.reduce(0, +)
                    let defPts = (0..<6).filter { !offSet.contains($0) }.map { newWon[$0] }.reduce(0, +)
                    let bidMade = offPts >= highBid

                    let scoring = ScoringEngine.calculateRoundScores(
                        bidAmount: highBid,
                        bidderIndex: highBidderIndex,
                        offenseIndices: offSet,
                        bidMade: bidMade
                    )
                    var newRS = capturedRunningScores
                    for i in 0..<6 { newRS[i] += scoring.playerDeltas[i] }

                    let nextPhase: OnlineGamePhase = (newRS.max() ?? 0) >= Self.winningScore ? .gameOver : .roundComplete
                    var gs = buildGS(phase: nextPhase, currentActionPlayer: -1,
                        bids: bids, highBid: highBid, highBidderIndex: highBidderIndex,
                        message: "\(playerName(winner)) wins! \(bidMade ? "Bid made!" : "SET!")")
                    gs["currentTrick"] = [] as [[String: Any]]
                    gs["trickNumber"] = newTrickNum
                    gs["wonPointsPerPlayer"] = newWon
                    gs["runningScores"] = newRS
                    gs["currentLeaderIndex"] = winner
                    gs["partner1Index"] = hostPartner1
                    gs["partner2Index"] = hostPartner2
                    let writeOk = await criticalWrite(["gameState": gs, "pendingAction": [:] as [String: Any]])
                    // Fix 3: if all Firestore retries failed, apply the resolved state locally
                    // on the host so the game loop advances despite the network failure.
                    // Clients will re-sync when connectivity is restored.
                    if !writeOk {
                        ogVMLog.error("[playCard] round-complete write failed — applying state locally")
                        wonPointsPerPlayer = newWon
                        runningScores = newRS
                        currentTrick = []
                        trickNumber = newTrickNum
                        currentLeaderIndex = winner
                        partner1Index = hostPartner1
                        partner2Index = hostPartner2
                        phase = nextPhase
                    }
                } else {
                    var gs = buildGS(phase: .playing, currentActionPlayer: winner,
                        bids: bids, highBid: highBid, highBidderIndex: highBidderIndex,
                        message: "\(playerName(winner)) wins the hand!")
                    gs["currentTrick"] = [] as [[String: Any]]
                    gs["trickNumber"] = newTrickNum
                    gs["wonPointsPerPlayer"] = newWon
                    gs["currentLeaderIndex"] = winner
                    gs["partner1Index"] = newP1
                    gs["partner2Index"] = newP2
                    let writeOk = await criticalWrite(["gameState": gs, "pendingAction": [:] as [String: Any]])
                    // Fix 3: if all Firestore retries failed, apply state locally so the next
                    // trick can begin on the host, then re-trigger the AI if the trick winner is AI.
                    if !writeOk {
                        ogVMLog.error("[playCard] trick-advance write failed — applying state locally")
                        currentActionPlayer = winner
                        currentTrick = []
                        trickNumber = newTrickNum
                        wonPointsPerPlayer = newWon
                        currentLeaderIndex = winner
                        partner1Index = newP1
                        partner2Index = newP2
                        await processAITurnIfNeeded()
                    }
                }
            } else {
                // Trick in progress — advance to next in order
                let trickOrder = (0..<6).map { (currentLeaderIndex + $0) % 6 }
                let pos = trickOrder.firstIndex(of: playerIndex) ?? 0
                // Fix: use modulo instead of min() so a stale/defaulted pos=0 can't
                // wrap back to trickOrder[5] and re-pick the same player (or skip anyone).
                let nextPlayer = trickOrder[(pos + 1) % 6]

                var gs = buildGS(phase: .playing, currentActionPlayer: nextPlayer,
                    bids: bids, highBid: highBid, highBidderIndex: highBidderIndex,
                    message: "\(playerName(playerIndex)) played \(card.rank)\(card.suit)")
                gs["currentTrick"] = trickData
                gs["partner1Index"] = newP1
                gs["partner2Index"] = newP2
                let writeOk = await criticalWrite(["gameState": gs, "hands": handsDict, "pendingAction": [:] as [String: Any]])
                // Fix 3: if write fails, apply state locally and re-trigger so the trick
                // doesn't freeze waiting for a Firestore snapshot that was never written.
                if !writeOk {
                    ogVMLog.error("[playCard] trick-in-progress write failed — applying state locally")
                    currentActionPlayer = nextPlayer
                    currentTrick = newTrick
                    partner1Index = newP1
                    partner2Index = newP2
                    await processAITurnIfNeeded()
                }
            }

        default:
            break
        }
    }

    // MARK: - Host Helpers

    private func concludeBidding(bids: [Int], highBid: Int, highBidder: Int) async {
        var finalBids = bids
        var finalHigh = highBid
        var finalBidder = highBidder
        var msg = "\(playerName(finalBidder)) won the bid with \(finalHigh)!"

        if finalBidder == -1 {
            finalBidder = dealerIndex
            finalHigh = 130
            finalBids[dealerIndex] = 130
            msg = "\(playerName(finalBidder)) is forced to bid 130"
        }

        var gs = buildGS(phase: .calling, currentActionPlayer: finalBidder,
            bids: finalBids, highBid: finalHigh, highBidderIndex: finalBidder,
            message: msg)
        gs["calledCard1"] = ""
        gs["calledCard2"] = ""
        gs["partner1Index"] = -1
        gs["partner2Index"] = -1
        gs["currentTrick"] = [] as [[String: Any]]
        gs["trickNumber"] = 0
        gs["wonPointsPerPlayer"] = Array(repeating: 0, count: 6)
        await criticalWrite(["gameState": gs, "pendingAction": [:] as [String: Any]])
    }

    /// Writes `update` to the session document with up to 3 attempts (2 s then 4 s backoff).
    /// Sets `errorMessage` after all retries fail so the player knows the network is broken.
    @discardableResult
    private func criticalWrite(_ update: [String: Any]) async -> Bool {
        let ref = Firestore.firestore().collection("sessions").document(sessionCode)
        let delays: [UInt64] = [2_000_000_000, 4_000_000_000]
        for attempt in 1...3 {
            do {
                try await ref.updateData(update)
                return true
            } catch {
                ogVMLog.warning("[criticalWrite] attempt \(attempt)/3 failed: \(error.localizedDescription)")
                if attempt - 1 < delays.count {
                    try? await Task.sleep(nanoseconds: delays[attempt - 1])
                }
            }
        }
        ogVMLog.error("[criticalWrite] all retries failed — update dropped")
        errorMessage = "Network error — couldn't save game state. Check your connection."
        return false
    }

    private func buildGS(
        phase: OnlineGamePhase,
        currentActionPlayer: Int,
        bids: [Int],
        highBid: Int,
        highBidderIndex: Int,
        playerHasPassed: [Bool] = Array(repeating: false, count: 6),
        bidHistory: [(playerIndex: Int, amount: Int)] = [],
        message: String
    ) -> [String: Any] {
        [
            "phase": phase.rawValue,
            "roundNumber": roundNumber,
            "dealerIndex": dealerIndex,
            "currentActionPlayer": currentActionPlayer,
            "bids": bids,
            "highBid": highBid,
            "highBidderIndex": highBidderIndex,
            "playerHasPassed": playerHasPassed,
            "bidHistory": bidHistory.map { ["pi": $0.playerIndex, "amt": $0.amount] as [String: Any] },
            "trumpSuit": trumpSuit.rawValue,
            "calledCard1": calledCard1,
            "calledCard2": calledCard2,
            "partner1Index": partner1Index,
            "partner2Index": partner2Index,
            "currentTrick": currentTrick.map { e -> [String: Any] in ["pi": e.playerIndex, "card": e.card.id] },
            "currentLeaderIndex": currentLeaderIndex,
            "trickNumber": trickNumber,
            "wonPointsPerPlayer": wonPointsPerPlayer,
            "runningScores": runningScores,
            "message": message
        ]
    }

    // MARK: - Game Logic Helpers

    private func trickWinnerIndex(trick: [(playerIndex: Int, card: Card)]) -> Int {
        let ledSuit = trick[0].card.suit
        let trumpRaw = trumpSuit.rawValue
        let trumpPlays = trick.filter { $0.card.suit == trumpRaw }
        if !trumpPlays.isEmpty {
            return trumpPlays.max(by: {
                (Card.rankOrder[$0.card.rank] ?? 0) < (Card.rankOrder[$1.card.rank] ?? 0)
            })!.playerIndex
        }
        let ledPlays = trick.filter { $0.card.suit == ledSuit }
        return ledPlays.max(by: {
            (Card.rankOrder[$0.card.rank] ?? 0) < (Card.rankOrder[$1.card.rank] ?? 0)
        })!.playerIndex
    }

    private func resolvePartners(c1: String, c2: String) -> (Int, Int) {
        var p1 = -1, p2 = -1
        for (i, hand) in allHands.enumerated() where i != highBidderIndex {
            if hand.contains(where: { $0.id == c1 }) { p1 = i }
            if hand.contains(where: { $0.id == c2 }) { p2 = i }
        }
        return (p1, p2)
    }

    // MARK: - AI Auto-play (custom game, host only)

    private var hostOffenseSet: Set<Int> {
        Set([highBidderIndex, hostPartner1, hostPartner2].filter { $0 >= 0 })
    }

    private func processAITurnIfNeeded(retriesRemaining: Int = 2) async {
        // Fix 2: prevent two concurrent tasks (from back-to-back Firestore snapshots) from
        // both passing the post-sleep guard and double-playing the same seat. Reset to false
        // before every recursive re-trigger so the next call can proceed normally.
        guard !isProcessingAI else { return }
        guard isHost, !aiSeats.isEmpty, aiSeats.contains(currentActionPlayer) else { return }
        isProcessingAI = true
        let seat = currentActionPlayer
        let capturedPhase = phase
        let delay = UInt64.random(in: 800_000_000...1_200_000_000)
        try? await Task.sleep(nanoseconds: delay)
        // Verify state hasn't changed during the sleep — another snapshot may have
        // advanced the turn to a different player or a different phase.
        // If the guard fires but it's still an AI's turn in an active phase, re-trigger
        // so a stale snapshot can't permanently freeze the AI (mirrors BT recovery path).
        let activePhases: [OnlineGamePhase] = [.bidding, .calling, .playing]
        guard currentActionPlayer == seat, phase == capturedPhase else {
            isProcessingAI = false  // reset before re-trigger
            if aiSeats.contains(currentActionPlayer) && activePhases.contains(phase) {
                await processAITurnIfNeeded(retriesRemaining: retriesRemaining)
            }
            return
        }
        // Reset flag before action — the action (processPendingAction) triggers a Firestore
        // write and the resulting snapshot re-enters processAITurnIfNeeded. If the flag
        // were still true, that next call would bail immediately and the chain would break.
        isProcessingAI = false
        switch capturedPhase {
        case .bidding:
            let canPass = highBid > 0
            let amount = aiComputeBid(seat: seat, canPass: canPass)
            let actionData: [String: Any] = [
                "nonce": UUID().uuidString,
                "playerIndex": seat,
                "type": amount == 0 ? "pass" : "bid",
                "bidAmount": amount
            ]
            await processPendingAction(actionData)
        case .calling:
            // Issue #5 fix: allHands[seat] may be stale if the startGame hands write
            // failed silently (try?) and a later snapshot re-synced allHands from the
            // previous round's Firestore data. A calling AI with the wrong hand calls
            // invalid partners → resolvePartners returns (-1,-1) → point corruption.
            // Guard: require exactly 8 cards. On mismatch, do a one-shot Firestore
            // fetch to re-sync allHands before computing calling.
            if allHands[seat].count != 8 {
                await refetchAndSyncHands()
            }
            guard allHands[seat].count == 8 else {
                // RC-A fix: refetch failed or returned wrong count. Retry up to
                // retriesRemaining times (default 2) with a 1s delay so transient
                // Firestore failures don't permanently freeze the AI calling turn.
                if retriesRemaining > 0 {
                    ogVMLog.warning("[AI Calling] seat \(seat) has \(self.allHands[seat].count) cards after refetch — retrying (\(retriesRemaining) left)")
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await processAITurnIfNeeded(retriesRemaining: retriesRemaining - 1)
                } else {
                    ogVMLog.error("[AI Calling] seat \(seat) still has \(self.allHands[seat].count) cards after all retries — giving up")
                }
                return
            }
            let result = aiComputeCalling(seat: seat)
            let actionData: [String: Any] = [
                "nonce": UUID().uuidString,
                "playerIndex": seat,
                "type": "callCards",
                "trump": result.trump.rawValue,
                "calledCard1": result.c1,
                "calledCard2": result.c2
            ]
            await processPendingAction(actionData)
        case .playing:
            // Fix 1: aiComputeCard returns nil when hand is empty (stale state / sync lag).
            // Retry after 1s rather than injecting a phantom card.
            guard let cardId = aiComputeCard(seat: seat) else {
                ogVMLog.error("[AI Playing] seat \(seat) has empty hand — retrying in 1s")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                // Fix 2: state may have changed during the 1s sleep — only recurse if
                // this seat is still the current action player in the playing phase.
                // If a different AI now needs to act, the recovery re-triggers for them.
                guard currentActionPlayer == seat, phase == .playing else {
                    if aiSeats.contains(currentActionPlayer) && phase == .playing {
                        await processAITurnIfNeeded(retriesRemaining: retriesRemaining)
                    }
                    return
                }
                await processAITurnIfNeeded(retriesRemaining: retriesRemaining)
                return
            }
            let actionData: [String: Any] = [
                "nonce": UUID().uuidString,
                "playerIndex": seat,
                "type": "playCard",
                "cardId": cardId
            ]
            await processPendingAction(actionData)
        default:
            break
        }
    }

    private func aiComputeBid(seat: Int, canPass: Bool) -> Int {
        let hand = allHands[seat]
        let myPoints = hand.map(\.pointValue).reduce(0, +)
        let myIds = Set(hand.map(\.id))
        let topExternal = ComputerGameViewModel.freshDeck()
            .filter { !myIds.contains($0.id) }
            .sorted { lhs, rhs in
                lhs.pointValue != rhs.pointValue
                    ? lhs.pointValue > rhs.pointValue
                    : (Card.rankOrder[lhs.rank] ?? 0) > (Card.rankOrder[rhs.rank] ?? 0)
            }
        let call1Pts = topExternal.first?.pointValue ?? 0
        let call2Pts = topExternal.dropFirst().first?.pointValue ?? 0

        // Phase 1a — Position-aware partner bonus
        let position = (seat - dealerIndex + 6) % 6
        let bonusFraction: Double
        switch position {
        case 1, 2: bonusFraction = 0.25
        case 3:    bonusFraction = 0.33
        case 4, 5: bonusFraction = 0.42
        default:   bonusFraction = 0.38   // dealer
        }
        let remaining = max(0, 250 - myPoints - call1Pts - call2Pts)
        let partnerBonus = Int(Double(remaining) * bonusFraction)

        // Phase 1b — Suit-clustering bonus (2+ high cards in same suit)
        var clusterBonus = 0
        for suit in TrumpSuit.allCases {
            let suitCards = hand.filter { $0.suit == suit.rawValue }
            guard suitCards.count >= 2 else { continue }
            let sortedRanks = suitCards.compactMap { Card.rankOrder[$0.rank] }.sorted(by: >)
            if let top = sortedRanks.first, let second = sortedRanks.dropFirst().first,
               top >= 10 && second >= 10 {
                clusterBonus += suitCards.count * 4
            }
        }

        // Phase 1c — Shortness penalty (3+ thin suits)
        let thinSuits = TrumpSuit.allCases.filter { suit in
            hand.filter { $0.suit == suit.rawValue }.count <= 1
        }.count
        let shortnessPenalty = max(0, thinSuits - 2) * 8

        let estimated = myPoints + call1Pts + call2Pts + partnerBonus + clusterBonus - shortnessPenalty
        let minBid = max(130, highBid + 5)
        if !canPass {
            let rounded = (max(estimated, minBid) / 5) * 5
            return min(max(rounded, minBid), 250)
        }
        guard estimated >= minBid else { return 0 }
        let rounded = (estimated / 5) * 5
        return min(max(rounded, minBid), 250)
    }

    private func aiComputeCalling(seat: Int) -> (trump: TrumpSuit, c1: String, c2: String) {
        let hand = allHands[seat]

        // Phase 2a — Tier-based trump selection
        func trumpTier(_ suit: TrumpSuit) -> Int {
            let topRank = hand.filter { $0.suit == suit.rawValue }
                .compactMap { Card.rankOrder[$0.rank] }.max() ?? 0
            if topRank >= 12 { return 3 }
            if topRank >= 11 { return 2 }
            if topRank >= 10 { return 1 }
            return 0
        }
        let suitRankings = TrumpSuit.allCases.map { suit -> (TrumpSuit, Int) in
            let pts   = hand.filter { $0.suit == suit.rawValue }.map(\.pointValue).reduce(0, +)
            let count = hand.filter { $0.suit == suit.rawValue }.count
            return (suit, pts + trumpTier(suit) * 15 + count * 2)
        }
        let trump = suitRankings.max(by: { $0.1 < $1.1 })?.0 ?? .spades

        // Phase 2b — Void-feeding called cards, diversified across suits
        let handIds = Set(hand.map(\.id))
        let candidates = ComputerGameViewModel.freshDeck()
            .filter { !handIds.contains($0.id) }
            .sorted { lhs, rhs in
                lhs.pointValue != rhs.pointValue
                    ? lhs.pointValue > rhs.pointValue
                    : (Card.rankOrder[lhs.rank] ?? 0) > (Card.rankOrder[rhs.rank] ?? 0)
            }
        let voidSuits  = TrumpSuit.allCases.filter { suit in
            suit != trump && hand.filter { $0.suit == suit.rawValue }.isEmpty
        }
        let shortSuits = TrumpSuit.allCases.filter { suit in
            suit != trump && hand.filter { $0.suit == suit.rawValue }.count == 1
        }
        var ordered: [Card] = []
        for suit in voidSuits {
            if let top = candidates.first(where: { $0.suit == suit.rawValue }) { ordered.append(top) }
        }
        let coveredSuits = Set(ordered.map(\.suit))
        for suit in shortSuits where !coveredSuits.contains(suit.rawValue) {
            if let top = candidates.first(where: { $0.suit == suit.rawValue }) { ordered.append(top) }
        }
        let chosenIds = Set(ordered.map(\.id))
        ordered += candidates.filter { !chosenIds.contains($0.id) }

        let c1Card = ordered.first
        let c2Card = ordered.first(where: { $0.suit != c1Card?.suit }) ?? ordered.dropFirst().first
        let c1 = c1Card?.id ?? "A♥"
        let c2 = c2Card?.id ?? (ordered.count > 1 ? ordered[1].id : "K♥")
        return (trump: trump, c1: c1, c2: c2)
    }

    /// One-shot Firestore read to re-sync allHands on the host.
    /// Called when allHands[seat] has the wrong card count before AI calling —
    /// this happens if the startGame hands write failed silently (try?) and a
    /// later snapshot overwrote allHands with the previous round's Firestore data.
    private func refetchAndSyncHands() async {
        let ref = Firestore.firestore().collection("sessions").document(sessionCode)
        guard let doc = try? await ref.getDocument(),
              let data = doc.data(),
              let handsData = data["hands"] as? [String: Any] else {
            ogVMLog.warning("[refetchAndSyncHands] failed to fetch document or missing hands field")
            return
        }
        for i in 0..<6 {
            if let cards = handsData["\(i)"] as? [String] {
                allHands[i] = cards.compactMap { parseCard($0) }
            }
        }
        ogVMLog.info("[refetchAndSyncHands] re-synced allHands from Firestore")
    }

    // Fix 1: returns nil when hand is empty so the caller can retry rather than
    // injecting a phantom "A♠" card that corrupts trick resolution.
    private func aiComputeCard(seat: Int) -> String? {
        let hand = allHands[seat]
        guard !hand.isEmpty else {
            ogVMLog.error("[aiComputeCard] seat=\(seat) has empty hand — returning nil")
            return nil
        }
        let isOffense = hostOffenseSet.contains(seat)
        let isBidder  = seat == highBidderIndex
        let trumpRaw  = trumpSuit.rawValue

        func rankScore(_ c: Card) -> Int  { Card.rankOrder[c.rank] ?? 0 }
        func valueScore(_ c: Card) -> Int { c.pointValue * 100 + rankScore(c) }

        // Phase 3 — Deficit tracking
        let offensePts = hostOffenseSet.map { wonPointsPerPlayer[$0] }.reduce(0, +)
        let totalPts   = wonPointsPerPlayer.reduce(0, +)
        let remaining  = 250 - totalPts
        let shortfall  = max(0, highBid - offensePts)
        let isUrgent   = isOffense && remaining > 0 && shortfall * 10 > remaining * 6

        // Phase 4 — Void memory from completed tricks
        var knownVoids: [Int: Set<String>] = [:]
        for trick in completedTricks {
            guard let ledSuit = trick.first?.card.suit else { continue }
            for entry in trick where entry.card.suit != ledSuit {
                knownVoids[entry.playerIndex, default: []].insert(ledSuit)
            }
        }
        let opponentIndices = (0..<6).filter { isOffense ? !hostOffenseSet.contains($0) : hostOffenseSet.contains($0) }

        // ── LEADING ──────────────────────────────────────────────────────
        if currentTrick.isEmpty {
            let nonTrump = hand.filter { $0.suit != trumpRaw }
            if isBidder {
                let bidSecured = offensePts >= highBid
                let trumpCards = hand.filter { $0.suit == trumpRaw }
                if !bidSecured || trickNumber < 3 {
                    if let highTrump = trumpCards.max(by: { rankScore($0) < rankScore($1) }),
                       rankScore(highTrump) >= (Card.rankOrder["Q"] ?? 0) {
                        return highTrump.id
                    }
                }
            }
            if isUrgent, let best = nonTrump.max(by: { valueScore($0) < valueScore($1) }) { return best.id }
            let scored = nonTrump.map { card -> (Card, Int) in
                let voidCount = opponentIndices.filter { knownVoids[$0]?.contains(card.suit) == true }.count
                return (card, rankScore(card) + card.pointValue - voidCount * 4)
            }
            if let best = scored.max(by: { $0.1 < $1.1 })?.0 { return best.id }
            if let best = nonTrump.max(by: { rankScore($0) < rankScore($1) }) { return best.id }
            return (hand.min(by: { rankScore($0) < rankScore($1) }) ?? hand[0]).id
        }

        // ── FOLLOWING ────────────────────────────────────────────────────
        let ledSuit  = currentTrick[0].card.suit
        let sameSuit = hand.filter { $0.suit == ledSuit }

        guard let winnerEntry = currentTrick.max(by: { (a, b) in
            let aTrump = a.card.suit == trumpRaw
            let bTrump = b.card.suit == trumpRaw
            if aTrump != bTrump { return bTrump }
            if a.card.suit == b.card.suit { return rankScore(a.card) < rankScore(b.card) }
            return true
        }) else { return hand[0].id }

        let winner = winnerEntry
        let winnerIsOffense = hostOffenseSet.contains(winner.playerIndex)
        let teammateWinning = isOffense ? winnerIsOffense : !winnerIsOffense

        if !sameSuit.isEmpty {
            if teammateWinning {
                return (sameSuit.max(by: { valueScore($0) < valueScore($1) }) ?? sameSuit[0]).id
            }
            if winner.card.suit == ledSuit {
                let canBeat = sameSuit.filter { rankScore($0) > rankScore(winner.card) }
                if let best = canBeat.max(by: { rankScore($0) < rankScore($1) }) { return best.id }
            }
            return (sameSuit.min(by: { valueScore($0) < valueScore($1) }) ?? sameSuit[0]).id
        }

        // ── CAN'T FOLLOW ─────────────────────────────────────────────────
        if teammateWinning {
            let nonTrump = hand.filter { $0.suit != trumpRaw }
            if let best = nonTrump.max(by: { valueScore($0) < valueScore($1) }) { return best.id }
        }
        // Phase 3: only trump in if points are at stake or offense is in urgent mode
        let trickPoints = currentTrick.map(\.card.pointValue).reduce(0, +)
        let trumpCards  = hand.filter { $0.suit == trumpRaw }
        if !trumpCards.isEmpty && (trickPoints > 0 || isUrgent) {
            return (trumpCards.min(by: { rankScore($0) < rankScore($1) }) ?? trumpCards[0]).id
        }
        let nonTrump = hand.filter { $0.suit != trumpRaw }
        if let discard = nonTrump.min(by: { valueScore($0) < valueScore($1) }) { return discard.id }
        return (trumpCards.min(by: { rankScore($0) < rankScore($1) }) ?? hand[0]).id
    }

    private func setSmartCallingDefaults() {
        let hand = myHand

        let suitScores = TrumpSuit.allCases.map { suit -> (TrumpSuit, Int) in
            let pts = hand.filter { $0.suit == suit.rawValue }.map(\.pointValue).reduce(0, +)
            return (suit, pts)
        }
        trumpSuitSelection = suitScores.max(by: { $0.1 < $1.1 })?.0 ?? .spades

        let handIds = Set(hand.map(\.id))
        let candidates = ComputerGameViewModel.freshDeck()
            .filter { !handIds.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.pointValue != rhs.pointValue { return lhs.pointValue > rhs.pointValue }
                return (Card.rankOrder[lhs.rank] ?? 0) > (Card.rankOrder[rhs.rank] ?? 0)
            }
        if candidates.count >= 2 {
            calledCard1Rank = candidates[0].rank
            calledCard1Suit = candidates[0].suit
            calledCard2Rank = candidates[1].rank
            calledCard2Suit = candidates[1].suit
        }
    }
}
