import SwiftUI
import Observation
import MultipeerConnectivity
import OSLog

private let aiLog = Logger(subsystem: "com.vijaygoyal.theshadyspade", category: "AI")

// MARK: - BTSessionState

enum BTSessionState: Equatable {
    case idle
    case hosting
    case browsing
    case connected
    case playing
}

// MARK: - BidWinnerInfo (reuse from Online if not already defined)
// Note: BidWinnerInfo is defined in OnlineGameViewModel.swift already

// MARK: - ViewModel

@Observable @MainActor
final class BluetoothGameViewModel: NSObject {

    static let serviceType = "shady-spade"
    static let winningScore = 500

    // MARK: Identity
    var myPlayerIndex: Int = 0
    var isHost: Bool = false
    var playerNames: [String] = Array(repeating: "", count: 6)
    var playerAvatars: [String] = Array(repeating: "🃏", count: 6)

    // MARK: Phase / Game State
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

    // MARK: Bidding
    var playerHasPassed: [Bool] = Array(repeating: false, count: 6)
    var bidHistory: [(playerIndex: Int, amount: Int)] = []
    var bidHistoryOrdered: [(playerIndex: Int, amount: Int)] { bidHistory }

    // MARK: Partner reveal
    var revealedPartner1Index: Int = -1
    var revealedPartner2Index: Int = -1
    var partnerRevealMessage: String? = nil

    // MARK: UI state
    var trumpSuitSelection: TrumpSuit = .spades
    var calledCard1Rank: String = "A"
    var calledCard1Suit: String = "♥"
    var calledCard2Rank: String = "K"
    var calledCard2Suit: String = "♦"
    var humanBidAmount: Double = 130
    var bidWinnerInfo: BidWinnerInfo? = nil
    var errorMessage: String? = nil
    var wasRemovedFromGame = false
    // Set to true on non-host clients when the host explicitly ends the game
    var hostEndedGame = false

    // MARK: AI seats (filled if < 6 humans)
    var aiSeats: [Int] = []

    /// Stable identifier for this BT game session — generated once by the host in
    /// startHosting() and broadcast to all peers via gameState. Used as sessionCode
    /// so all 6 clients can submit leaderboard records independently; the Cloud
    /// Function's transaction makes duplicate submissions silent no-ops.
    var gameSessionId: String = ""

    // MARK: Local web dashboard (host only)
    var localServerURL: String = ""
    private var localServer: LocalGameServer?

    // MARK: Current trick winner
    var currentTrickWinnerIndex: Int? {
        guard !currentTrick.isEmpty else { return nil }
        return trickWinnerIndex(trick: currentTrick)
    }

    // MARK: Session state (lobby)
    var sessionState: BTSessionState = .idle
    var foundSessions: [(peerID: MCPeerID, info: [String: String])] = []
    var connectedPlayerSlots: [BTPlayerSlot] = (0..<6).map { BTPlayerSlot.empty(at: $0) }

    // MARK: MC infrastructure (private)
    private var peerID: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    // host: peer → player index mapping
    private var peerToPlayerIndex: [MCPeerID: Int] = [:]
    private var playerIndexToPeer: [Int: MCPeerID] = [:]

    // Temp storage for peer info received in advertiser callback,
    // consumed in session:didChange:connected to avoid double slot assignment
    private var pendingPeerInfo: [MCPeerID: [String: String]] = [:]

    // MARK: Host-only state
    private var allHands: [[Card]] = Array(repeating: [], count: 6)
    private var hostPartner1: Int = -1
    private var hostPartner2: Int = -1
    private var hostCalledCard1: String = ""
    private var hostCalledCard2: String = ""

    private var hasInitializedCalling = false
    private var lastProcessedActionId: String = ""
    private var lastActionSentAt: Date = .distantPast
    /// Prevents two concurrent AI tasks (from back-to-back MC messages) from both
    /// passing the post-sleep guard and double-playing the same seat. Reset to false
    /// before every recursive re-trigger and before each action so processPlayCard's
    /// internal processAITurnIfNeeded calls can proceed.
    private var isProcessingAI = false

    // MARK: sendToHost retry state (client only)
    var isReconnecting: Bool = false
    private var pendingHostAction: [String: Any]? = nil
    private var reconnectTask: Task<Void, Never>? = nil
    /// Per-turn watchdog: cancellable Task started whenever a human player's turn begins.
    /// Fires after 60s of inactivity to replace the idle player with AI.
    private var turnWatchdogTask: Task<Void, Never>?

    // MARK: - Computed

    var isMyTurn: Bool { myPlayerIndex == currentActionPlayer }

    var humanMinBid: Int { max(130, highBid + 5) }
    var humanMustPass: Bool { humanMinBid > 250 }
    var humanCanPass: Bool { highBid > 0 }

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

    var offensePoints: Int {
        (0..<6).filter { offenseSet.contains($0) }.map { wonPointsPerPlayer[$0] }.reduce(0, +)
    }

    var defensePoints: Int {
        (0..<6).filter { !offenseSet.contains($0) }.map { wonPointsPerPlayer[$0] }.reduce(0, +)
    }

    // MARK: - Player info helpers

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

    func allHandCountFor(_ index: Int) -> Int {
        guard isHost && index >= 0 && index < allHands.count else { return 8 }
        return allHands[index].count
    }

    // MARK: - Lobby: Host

    func startHosting(playerName: String, avatar: String) {
        cleanup()
        peerID = MCPeerID(displayName: playerName)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self

        // Slot 0 = host
        myPlayerIndex = 0
        isHost = true
        gameSessionId = UUID().uuidString
            .filter { $0.isLetter || $0.isNumber }
            .prefix(10)
            .lowercased()
        playerNames[0] = playerName
        playerAvatars[0] = avatar
        connectedPlayerSlots[0] = BTPlayerSlot(slotIndex: 0, name: playerName, avatar: avatar, joined: true)

        let info: [String: String] = ["hostName": playerName, "avatar": avatar, "slots": "1"]
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: info, serviceType: Self.serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        sessionState = .hosting

        // Start the local web dashboard server
        let server = LocalGameServer()
        server.onReady = { [weak self] url in
            Task { @MainActor [weak self] in
                self?.localServerURL = url
            }
        }
        server.start()
        localServer = server
    }

    // MARK: - Lobby: Client

    func startBrowsing(playerName: String, avatar: String) {
        cleanup()
        peerID = MCPeerID(displayName: playerName)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self

        isHost = false
        playerNames[0] = playerName   // temp, will be updated by assignSlot
        playerAvatars[0] = avatar

        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        sessionState = .browsing
    }

    func connectTo(peerID remotePeerID: MCPeerID) {
        guard let browser else { return }
        let context = try? JSONSerialization.data(withJSONObject: [
            "name": playerNames[0],
            "avatar": playerAvatars[0]
        ])
        browser.invitePeer(remotePeerID, to: session, withContext: context, timeout: 30)
    }

    // MARK: - Host: Start Game

    func startGame() async {
        guard isHost else { return }

        // Fill remaining slots with AI.
        // Use peerToPlayerIndex (actual connected peers) to identify human slots so that
        // AI slots from previous rounds aren't mistaken for humans (connectedPlayerSlots.joined
        // stays true once set, causing aiSeats to be empty in round 2+).
        let humanSlots = Set(peerToPlayerIndex.values)
        let aiNamePool = Comic.aiNamePool
        var newAISeats: [Int] = []
        // Pre-compute unique AI avatars, excluding all human avatars already assigned
        let usedAvatars = Set(humanSlots.map { playerAvatars[safe: $0] ?? "" }.filter { !$0.isEmpty })
        var availableAvatars = Comic.randomAIAvatars(count: 6, excluding: usedAvatars)
        for i in 1..<6 {
            if !humanSlots.contains(i) {
                let usedNames = playerNames.filter { !$0.isEmpty }
                let aiName = aiNamePool.first { !usedNames.contains($0) } ?? "Bot\(i)"
                let aiAvatar = availableAvatars.isEmpty ? "🤖" : availableAvatars.removeFirst()
                playerNames[i] = aiName
                playerAvatars[i] = aiAvatar
                connectedPlayerSlots[i] = BTPlayerSlot(slotIndex: i, name: aiName, avatar: aiAvatar, joined: true)
                newAISeats.append(i)
            }
        }
        aiSeats = newAISeats

        // Broadcast updated player list to all peers
        let slotMsg: [String: Any] = [
            "type": "playerList",
            "names": playerNames,
            "avatars": playerAvatars,
            "aiSeats": aiSeats
        ]
        sendToAll(slotMsg)

        sessionState = .playing
        phase = .dealing

        // Send dealing phase to all peers
        broadcastGameState()

        // Wait for dealing animation
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        // Deal cards
        let deck = freshDeck().shuffled()
        allHands = (0..<6).map { i in Array(deck[(i * 8)..<((i + 1) * 8)]) }

        // Reset host tracking
        hostPartner1 = -1; hostPartner2 = -1
        hostCalledCard1 = ""; hostCalledCard2 = ""

        // Send each peer their hand
        for (peerID, playerIndex) in peerToPlayerIndex {
            let hand = allHands[playerIndex]
            let handMsg: [String: Any] = [
                "type": "hand",
                "cards": hand.map { ["rank": $0.rank, "suit": $0.suit] }
            ]
            send(handMsg, to: peerID)
        }
        // Host's own hand
        myHand = allHands[myPlayerIndex]

        let firstBidder = (dealerIndex + 1) % 6
        currentActionPlayer = firstBidder
        currentLeaderIndex = firstBidder
        bids = Array(repeating: -1, count: 6)
        highBid = 0
        highBidderIndex = -1
        playerHasPassed = Array(repeating: false, count: 6)
        bidHistory = []
        trumpSuit = .spades
        calledCard1 = ""; calledCard2 = ""
        partner1Index = -1; partner2Index = -1
        currentTrick = []
        trickNumber = 0
        wonPointsPerPlayer = Array(repeating: 0, count: 6)
        completedTricks = []
        trickWinners = []
        lastCompletedTrick = []
        lastTrickWinnerIndex = -1
        lastTrickPoints = 0
        revealedPartner1Index = -1
        revealedPartner2Index = -1
        phase = .lookingAtCards
        message = "Study your cards, then start bidding."

        broadcastGameState()
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
        bids = Array(repeating: -1, count: 6)
        highBid = 0
        highBidderIndex = -1
        playerHasPassed = Array(repeating: false, count: 6)
        bidHistory = []
        currentActionPlayer = firstBidder
        phase = .bidding
        message = "\(playerName(firstBidder)) starts the bid!"
        broadcastGameState()
        await processAITurnIfNeeded()
    }

    // MARK: - Player Actions

    func placeBid(_ amount: Int) async {
        guard Date().timeIntervalSince(lastActionSentAt) > 0.3 else { return }
        lastActionSentAt = Date()
        if isHost {
            await processBid(playerIndex: myPlayerIndex, amount: amount)
        } else {
            let msg: [String: Any] = [
                "type": "action",
                "action": "bid",
                "amount": amount,
                "actionId": UUID().uuidString
            ]
            sendToHost(msg)
        }
    }

    func pass() async {
        guard Date().timeIntervalSince(lastActionSentAt) > 0.3 else { return }
        lastActionSentAt = Date()
        if isHost {
            await processPass(playerIndex: myPlayerIndex)
        } else {
            let msg: [String: Any] = [
                "type": "action",
                "action": "pass",
                "actionId": UUID().uuidString
            ]
            sendToHost(msg)
        }
    }

    func callTrumpAndCards() async {
        guard Date().timeIntervalSince(lastActionSentAt) > 0.3 else { return }
        lastActionSentAt = Date()
        let c1 = calledCard1Rank + calledCard1Suit
        let c2 = calledCard2Rank + calledCard2Suit
        if isHost {
            await processCallCards(playerIndex: myPlayerIndex, trump: trumpSuitSelection, c1: c1, c2: c2)
        } else {
            let msg: [String: Any] = [
                "type": "action",
                "action": "callTrump",
                "suit": trumpSuitSelection.rawValue,
                "card1": c1,
                "card2": c2,
                "actionId": UUID().uuidString
            ]
            sendToHost(msg)
        }
    }

    func playCard(_ card: Card) async {
        guard Date().timeIntervalSince(lastActionSentAt) > 0.3 else { return }
        lastActionSentAt = Date()
        if isHost {
            await processPlayCard(playerIndex: myPlayerIndex, cardId: card.id)
        } else {
            let msg: [String: Any] = [
                "type": "action",
                "action": "playCard",
                "cardId": card.id,
                "actionId": UUID().uuidString
            ]
            sendToHost(msg)
        }
    }

    func proceedFromBidWinner() {
        bidWinnerInfo = nil
    }

    // MARK: - Cleanup

    func cleanup() {
        turnWatchdogTask?.cancel()
        turnWatchdogTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        pendingHostAction = nil
        isReconnecting = false
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        session?.disconnect()
        session = nil
        peerToPlayerIndex = [:]
        playerIndexToPeer = [:]
        sessionState = .idle
        foundSessions = []
        localServer?.stop()
        localServer = nil
        localServerURL = ""
    }

    /// Broadcasts a "hostEndedGame" message to all connected peers so they can show a
    /// farewell alert before the session disconnects. Call before cleanup() so peers
    /// are still connected to receive it.
    func notifyHostEndedGame() {
        sendToAll(["type": "hostEndedGame"])
    }

    // MARK: - Host Game Logic: Process Actions

    private func processBid(playerIndex: Int, amount: Int) async {
        guard isHost else { return }
        guard playerIndex == currentActionPlayer else { return }
        var newBids = bids
        newBids[playerIndex] = amount
        var newHighBid = highBid
        var newHighBidder = highBidderIndex
        if amount > newHighBid { newHighBid = amount; newHighBidder = playerIndex }
        var newHistory = bidHistory
        newHistory.append((playerIndex: playerIndex, amount: amount))

        let activePlayers = (0..<6).filter { !playerHasPassed[$0] }
        if activePlayers.count <= 1 {
            await concludeBidding(bids: newBids, highBid: newHighBid, highBidder: newHighBidder)
        } else {
            var next = (playerIndex + 1) % 6
            while playerHasPassed[next] { next = (next + 1) % 6 }
            bids = newBids
            highBid = newHighBid
            highBidderIndex = newHighBidder
            bidHistory = latestBidPerPlayer(newHistory)
            currentActionPlayer = next
            message = "\(playerName(playerIndex)) bid \(amount)"
            broadcastGameState()
            await processAITurnIfNeeded()
        }
    }

    private func processPass(playerIndex: Int) async {
        guard isHost else { return }
        guard playerIndex == currentActionPlayer else { return }
        var newBids = bids
        newBids[playerIndex] = 0
        var newPassed = playerHasPassed
        newPassed[playerIndex] = true
        var newHistory = bidHistory
        newHistory.append((playerIndex: playerIndex, amount: 0))

        let activePlayers = (0..<6).filter { !newPassed[$0] }
        if activePlayers.count <= 1 {
            await concludeBidding(bids: newBids, highBid: highBid, highBidder: highBidderIndex)
        } else {
            var next = (playerIndex + 1) % 6
            while newPassed[next] { next = (next + 1) % 6 }
            bids = newBids
            playerHasPassed = newPassed
            bidHistory = latestBidPerPlayer(newHistory)
            currentActionPlayer = next
            message = "\(playerName(playerIndex)) passed"
            broadcastGameState()
            await processAITurnIfNeeded()
        }
    }

    private func concludeBidding(bids newBids: [Int], highBid newHigh: Int, highBidder newBidder: Int) async {
        var finalBids = newBids
        var finalHigh = newHigh
        var finalBidder = newBidder

        if finalBidder == -1 {
            finalBidder = dealerIndex
            finalHigh = 130
            finalBids[dealerIndex] = 130
            message = "\(playerName(finalBidder)) is forced to bid 130"
        } else {
            message = "\(playerName(finalBidder)) won the bid with \(finalHigh)!"
        }

        bids = finalBids
        highBid = finalHigh
        highBidderIndex = finalBidder
        currentActionPlayer = finalBidder
        calledCard1 = ""; calledCard2 = ""
        partner1Index = -1; partner2Index = -1
        currentTrick = []
        trickNumber = 0
        wonPointsPerPlayer = Array(repeating: 0, count: 6)
        phase = .calling
        broadcastGameState()
        await processAITurnIfNeeded()
    }

    private func processCallCards(playerIndex: Int, trump: TrumpSuit, c1: String, c2: String) async {
        guard isHost else { return }
        guard playerIndex == currentActionPlayer else { return }
        let validIds = Set(freshDeck().map(\.id))
        guard validIds.contains(c1), validIds.contains(c2), c1 != c2,
              !allHands[playerIndex].map(\.id).contains(c1),
              !allHands[playerIndex].map(\.id).contains(c2) else { return }
        let (p1, p2) = resolvePartners(c1: c1, c2: c2)
        hostPartner1 = p1; hostPartner2 = p2
        hostCalledCard1 = c1; hostCalledCard2 = c2

        trumpSuit = trump
        calledCard1 = c1
        calledCard2 = c2
        partner1Index = -1
        partner2Index = -1
        currentLeaderIndex = highBidderIndex
        currentActionPlayer = highBidderIndex
        currentTrick = []
        trickNumber = 0
        wonPointsPerPlayer = Array(repeating: 0, count: 6)
        phase = .playing
        message = "\(playerName(highBidderIndex)) called — play begins!"
        broadcastGameState()
        await processAITurnIfNeeded()
    }

    private func processPlayCard(playerIndex: Int, cardId: String) async {
        guard isHost else { return }
        guard playerIndex == currentActionPlayer else { return }
        guard let card = parseCard(cardId),
              allHands[playerIndex].contains(where: { $0.id == cardId }) else {
            // Card is invalid or not in hand (e.g. stale action). Reset the AI lock
            // flag first — a sleeping AI task may hold it, which would cause the
            // re-trigger below to bail silently and leave the game frozen.
            isProcessingAI = false
            if aiSeats.contains(currentActionPlayer) {
                await processAITurnIfNeeded()
            }
            return
        }

        allHands[playerIndex].removeAll { $0.id == cardId }

        // Send updated hand to the player (or keep host's own hand)
        if playerIndex == myPlayerIndex {
            myHand = allHands[myPlayerIndex]
        } else if let peer = playerIndexToPeer[playerIndex] {
            let handMsg: [String: Any] = [
                "type": "hand",
                "cards": allHands[playerIndex].map { ["rank": $0.rank, "suit": $0.suit] }
            ]
            send(handMsg, to: peer)
        }

        var newTrick = currentTrick
        newTrick.append((playerIndex: playerIndex, card: card))

        // Check partner reveal
        var newP1 = partner1Index
        var newP2 = partner2Index
        if cardId == hostCalledCard1 && newP1 == -1 { newP1 = hostPartner1 }
        if cardId == hostCalledCard2 && newP2 == -1 { newP2 = hostPartner2 }

        if newTrick.count == 6 {
            // Show the completed trick first
            currentTrick = newTrick
            partner1Index = newP1
            partner2Index = newP2
            message = "\(playerName(playerIndex)) played \(card.rank)\(card.suit)"
            broadcastGameState()

            // 1 second pause for clients to render
            // Capture mutable state before sleep — a reentrant applyGameState call during
            // the sleep could overwrite these properties on the host.
            let capturedWonPoints = wonPointsPerPlayer
            let capturedTrickNumber = trickNumber
            let capturedRunningScores = runningScores
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            let winner = trickWinnerIndex(trick: newTrick)
            let pts = newTrick.map(\.card.pointValue).reduce(0, +)
            var newWon = capturedWonPoints
            newWon[winner] += pts
            let newTrickNum = capturedTrickNumber + 1

            // Capture trick for history
            lastCompletedTrick = newTrick
            lastTrickWinnerIndex = winner
            lastTrickPoints = pts
            completedTricks.append(newTrick)
            trickWinners.append(winner)

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

                wonPointsPerPlayer = newWon
                runningScores = newRS
                currentTrick = []
                trickNumber = newTrickNum
                currentLeaderIndex = winner
                partner1Index = hostPartner1
                partner2Index = hostPartner2
                message = "\(playerName(winner)) wins! \(bidMade ? "Bid made!" : "SET!")"

                let nextPhase: OnlineGamePhase = (newRS.max() ?? 0) >= Self.winningScore ? .gameOver : .roundComplete
                phase = nextPhase
                broadcastGameState()
            } else {
                wonPointsPerPlayer = newWon
                currentTrick = []
                trickNumber = newTrickNum
                currentLeaderIndex = winner
                currentActionPlayer = winner
                partner1Index = newP1
                partner2Index = newP2
                message = "\(playerName(winner)) wins the hand!"
                broadcastGameState()
                await processAITurnIfNeeded()
            }
        } else {
            // Trick in progress — advance to next player
            let trickOrder = (0..<6).map { (currentLeaderIndex + $0) % 6 }
            let pos = trickOrder.firstIndex(of: playerIndex) ?? 0
            // Fix: use modulo instead of min() so a stale/defaulted pos=0 can't
            // wrap back to trickOrder[5] and re-pick the same player (or skip anyone).
            let nextPlayer = trickOrder[(pos + 1) % 6]

            currentTrick = newTrick
            currentActionPlayer = nextPlayer
            partner1Index = newP1
            partner2Index = newP2
            message = "\(playerName(playerIndex)) played \(card.rank)\(card.suit)"
            broadcastGameState()
            await processAITurnIfNeeded()
        }
    }

    // MARK: - Host: Broadcast Game State

    private func broadcastGameState() {
        guard isHost else { return }
        let gs = buildGameStateDict()
        let msg: [String: Any] = ["type": "gameState", "state": gs]
        sendToAll(msg)
        // Apply state locally for host
        applyGameState(gs)
        // Push to web dashboard
        pushToLocalServer(gs)
    }

    private func pushToLocalServer(_ gs: [String: Any]) {
        guard let server = localServer else { return }
        var augmented = gs
        augmented["currentTrickWinnerIndex"] = currentTrickWinnerIndex ?? -1
        augmented["offensePoints"] = offensePoints
        augmented["defensePoints"] = defensePoints
        guard let data = try? JSONSerialization.data(withJSONObject: augmented),
              let json = String(data: data, encoding: .utf8) else { return }
        server.stateJSON = json
    }

    private func buildGameStateDict() -> [String: Any] {
        [
            "gameSessionId": gameSessionId,
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
            "message": message,
            "playerNames": playerNames,
            "playerAvatars": playerAvatars,
            "aiSeats": aiSeats
        ]
    }

    // MARK: - Apply Game State (non-host)

    func applyGameState(_ gs: [String: Any]) {
        func i(_ key: String) -> Int { (gs[key] as? Int) ?? (gs[key] as? Int64).map(Int.init) ?? 0 }
        func iDef(_ key: String, _ def: Int) -> Int { (gs[key] as? Int) ?? (gs[key] as? Int64).map(Int.init) ?? def }

        let newPhase = OnlineGamePhase(rawValue: gs["phase"] as? String ?? "") ?? .dealing
        let newRoundNumber = i("roundNumber")
        let newCurrentActionPlayer = iDef("currentActionPlayer", -1)
        let newP1 = iDef("partner1Index", -1)
        let newP2 = iDef("partner2Index", -1)

        // Partner reveal detection
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
        if newP1 == -1 { revealedPartner1Index = -1 }
        if newP2 == -1 { revealedPartner2Index = -1 }

        // Bid winner announcement
        if newPhase == .calling && phase == .bidding {
            let winnerIdx = iDef("highBidderIndex", -1)
            let winnerBid = i("highBid")
            if winnerIdx >= 0 {
                bidWinnerInfo = BidWinnerInfo(name: playerName(winnerIdx), avatar: "", bid: winnerBid)
                if winnerIdx != myPlayerIndex {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                        self?.bidWinnerInfo = nil
                    }
                }
            }
        }
        // If the calling phase ended before the 2.5s auto-dismiss fired, the banner
        // would remain on-screen during play, absorbing all card taps. Clear it now.
        if newPhase == .playing || newPhase == .roundComplete || newPhase == .gameOver {
            bidWinnerInfo = nil
        }

        // Update names/avatars if host sends them
        if let names = gs["playerNames"] as? [String], names.count == 6 {
            playerNames = names
        }
        if let avatars = gs["playerAvatars"] as? [String], avatars.count == 6 {
            playerAvatars = avatars
        }
        if let aiSeatsAny = gs["aiSeats"] as? [Any] {
            aiSeats = aiSeatsAny.compactMap { ($0 as? Int) ?? ($0 as? Int64).map(Int.init) }
        }
        if let sid = gs["gameSessionId"] as? String, !sid.isEmpty {
            gameSessionId = sid
        }

        phase = newPhase

        // Signal clients to transition out of the lobby when any active game phase arrives.
        // Using sessionState (which IS read in BTClientLobbyView.body) ensures @Observable
        // triggers a re-render and the onChange fires reliably.
        if !isHost && sessionState == .connected {
            let activePhases: [OnlineGamePhase] = [.lookingAtCards, .bidding, .calling, .playing, .roundComplete, .gameOver]
            if activePhases.contains(newPhase) {
                sessionState = .playing
            }
        }

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
                      let amt = (entry["amt"] as? Int) ?? (entry["amt"] as? Int64).map(Int.init),
                      pi >= 0 && pi < 6
                else { return nil }
                return (playerIndex: pi, amount: amt)
            }
            bidHistory = latestBidPerPlayer(parsed)
        }
        highBid = i("highBid")
        highBidderIndex = iDef("highBidderIndex", -1)

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
        let newTrickNumber = i("trickNumber")
        currentLeaderIndex = i("currentLeaderIndex")
        trickNumber = newTrickNumber

        // Trick just completed
        if newTrickNumber > prevTrickNumber && !currentTrick.isEmpty {
            lastCompletedTrick = currentTrick
            lastTrickWinnerIndex = currentLeaderIndex
            lastTrickPoints = currentTrick.map { $0.card.pointValue }.reduce(0, +)
            completedTricks.append(currentTrick)
            trickWinners.append(currentLeaderIndex)
        }
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

        if let trickArr = gs["currentTrick"] as? [[String: Any]] {
            currentTrick = trickArr.compactMap { entry in
                guard let pi = (entry["pi"] as? Int) ?? (entry["pi"] as? Int64).map(Int.init),
                      pi >= 0 && pi < 6,
                      let cardId = entry["card"] as? String,
                      let card = parseCard(cardId) else { return nil }
                return (playerIndex: pi, card: card)
            }
        }

        // Calling defaults
        if newPhase == .calling && newCurrentActionPlayer == myPlayerIndex && !hasInitializedCalling {
            hasInitializedCalling = true
            setSmartCallingDefaults()
        }
        if newPhase != .calling { hasInitializedCalling = false }

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

        // Per-turn watchdog (host only): start a 60-second timer when a human player's
        // turn begins. broadcastGameState calls applyGameState after every state write,
        // so each turn advance naturally resets the timer for the new seat.
        if isHost {
            let activePhases: [OnlineGamePhase] = [.bidding, .calling, .playing]
            if activePhases.contains(newPhase) && newCurrentActionPlayer >= 0
                && !aiSeats.contains(newCurrentActionPlayer) {
                startTurnWatchdog(seat: newCurrentActionPlayer, capturedPhase: newPhase)
            } else {
                cancelTurnWatchdog()
            }
        }
    }

    // MARK: - MC Send Helpers

    private func sendToAll(_ dict: [String: Any]) {
        guard let session, !session.connectedPeers.isEmpty else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            // MC .reliable errors indicate the session is broken; the didChange/notConnected
            // delegate fires next and handles AI-replacement recovery — no retry needed here.
            aiLog.error("[sendToAll] failed: \(error.localizedDescription)")
        }
    }

    private func send(_ dict: [String: Any], to peer: MCPeerID) {
        guard let session else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        do {
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            aiLog.error("[send] to \(peer.displayName) failed: \(error.localizedDescription)")
        }
    }

    private func sendToHost(_ dict: [String: Any]) {
        if let hostPeer = playerIndexToPeer[0] {
            send(dict, to: hostPeer)
            return
        }
        // Issue #6 fix: host peer not yet mapped (peer reconnect, session teardown race).
        // Queue the action and retry up to 3× at 500ms intervals instead of silently dropping.
        // Only one retry chain runs at a time; a newer action replaces the queued one.
        pendingHostAction = dict
        guard reconnectTask == nil else { return }
        isReconnecting = true
        reconnectTask = Task { @MainActor in
            for attempt in 1...3 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { break }
                if let hostPeer = playerIndexToPeer[0], let action = pendingHostAction {
                    send(action, to: hostPeer)
                    pendingHostAction = nil
                    isReconnecting = false
                    reconnectTask = nil
                    return
                }
                if attempt == 3 {
                    aiLog.error("[sendToHost] host peer still nil after 3 retries — action dropped")
                    errorMessage = "Lost connection to host. Please rejoin the game."
                    pendingHostAction = nil
                    isReconnecting = false
                    reconnectTask = nil
                }
            }
        }
    }

    // MARK: - Handle Incoming Messages

    private func handleMessage(_ dict: [String: Any], from peer: MCPeerID) {
        guard let type = dict["type"] as? String else { return }
        switch type {
        case "gameState":
            guard !isHost,
                  let hostPeer = playerIndexToPeer[0], peer == hostPeer,
                  let state = dict["state"] as? [String: Any] else { return }
            applyGameState(state)

        case "hostEndedGame":
            // Only accept from the host; set flag so view can show a farewell alert
            guard let hostPeer = playerIndexToPeer[0], peer == hostPeer, !isHost else { return }
            hostEndedGame = true

        case "hand":
            // Only accept hand messages from the host
            guard let hostPeer = playerIndexToPeer[0], peer == hostPeer,
                  let cardsAny = dict["cards"] as? [[String: Any]] else { return }
            let cards = cardsAny.compactMap { d -> Card? in
                guard let rank = d["rank"] as? String,
                      let suit = d["suit"] as? String else { return nil }
                return Card(rank: rank, suit: suit)
            }
            myHand = cards

        case "assignSlot":
            // Only accept slot assignments from the host
            guard let hostPeer = playerIndexToPeer[0], peer == hostPeer,
                  let slotIndex = (dict["playerIndex"] as? Int) ?? (dict["playerIndex"] as? Int64).map(Int.init),
                  slotIndex >= 0 && slotIndex < 6,
                  let names = dict["playerNames"] as? [String],
                  let avatars = dict["playerAvatars"] as? [String] else { return }
            myPlayerIndex = slotIndex
            playerNames = names
            playerAvatars = avatars
            if let aiSeatsAny = dict["aiSeats"] as? [Any] {
                aiSeats = aiSeatsAny.compactMap { ($0 as? Int) ?? ($0 as? Int64).map(Int.init) }
            }
            sessionState = .connected

        case "playerList":
            // Only accept from the host
            guard let hostPeer = playerIndexToPeer[0], peer == hostPeer,
                  let names = dict["names"] as? [String],
                  let avatars = dict["avatars"] as? [String] else { return }
            playerNames = names
            playerAvatars = avatars
            if let aiSeatsAny = dict["aiSeats"] as? [Any] {
                aiSeats = aiSeatsAny.compactMap { ($0 as? Int) ?? ($0 as? Int64).map(Int.init) }
            }
            // Update slot cards for lobby display
            for i in 0..<6 {
                let name = names[safe: i] ?? ""
                let avatar = avatars[safe: i] ?? "🃏"
                connectedPlayerSlots[i] = BTPlayerSlot(slotIndex: i, name: name, avatar: avatar, joined: !name.isEmpty)
            }

        case "action":
            guard isHost else { return }
            guard let playerIndex = peerToPlayerIndex[peer] else { return }
            let actionId = dict["actionId"] as? String ?? ""
            guard actionId != lastProcessedActionId, !actionId.isEmpty else { return }
            lastProcessedActionId = actionId

            let action = dict["action"] as? String ?? ""
            Task {
                switch action {
                case "bid":
                    let amount = (dict["amount"] as? Int) ?? (dict["amount"] as? Int64).map(Int.init) ?? 0
                    guard amount >= 130 && amount <= 250 else { return }
                    await self.processBid(playerIndex: playerIndex, amount: amount)
                case "pass":
                    await self.processPass(playerIndex: playerIndex)
                case "callTrump":
                    let suitStr = dict["suit"] as? String ?? TrumpSuit.spades.rawValue
                    let suit = TrumpSuit(rawValue: suitStr) ?? .spades
                    let c1 = dict["card1"] as? String ?? ""
                    let c2 = dict["card2"] as? String ?? ""
                    await self.processCallCards(playerIndex: playerIndex, trump: suit, c1: c1, c2: c2)
                case "playCard":
                    let cardId = dict["cardId"] as? String ?? ""
                    await self.processPlayCard(playerIndex: playerIndex, cardId: cardId)
                default:
                    break
                }
            }

        case "lobbyUpdate":
            // Client receives info about who else joined — only trust the host
            guard let hostPeer = playerIndexToPeer[0], peer == hostPeer else { return }
            if let names = dict["playerNames"] as? [String],
               let avatars = dict["playerAvatars"] as? [String] {
                playerNames = names
                playerAvatars = avatars
                for i in 0..<6 {
                    let n = names[safe: i] ?? ""
                    connectedPlayerSlots[i] = BTPlayerSlot(slotIndex: i, name: n, avatar: avatars[safe: i] ?? "🃏", joined: !n.isEmpty)
                }
            }

        default:
            break
        }
    }

    // MARK: - Per-turn watchdog

    private func cancelTurnWatchdog() {
        turnWatchdogTask?.cancel()
        turnWatchdogTask = nil
    }

    /// Cancels any existing watchdog and starts a fresh 60-second timer for `seat`.
    /// If the player still hasn't acted when the timer fires, the host adds them to
    /// aiSeats, broadcasts updated state, and triggers processAITurnIfNeeded.
    private func startTurnWatchdog(seat: Int, capturedPhase: OnlineGamePhase) {
        guard isHost, seat >= 0 else { return }
        turnWatchdogTask?.cancel()
        turnWatchdogTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
            guard let self else { return }
            guard self.currentActionPlayer == seat,
                  self.phase == capturedPhase,
                  !self.aiSeats.contains(seat) else { return }
            aiLog.warning("[watchdog] seat \(seat) idle 60s in \(capturedPhase.rawValue) — converting to AI")
            let name = self.playerName(seat)
            self.aiSeats.append(seat)
            self.aiSeats.sort()
            self.message = "\(name) is taking too long. AI took over."
            self.broadcastGameState()
            await self.processAITurnIfNeeded()
        }
    }

    // MARK: - Bid History Helper

    /// Returns bid history keeping one entry per player in first-appearance order,
    /// using each player's LATEST bid amount (not their first).
    private func latestBidPerPlayer(
        _ history: [(playerIndex: Int, amount: Int)]
    ) -> [(playerIndex: Int, amount: Int)] {
        var latest: [Int: Int] = [:]
        for e in history { latest[e.playerIndex] = e.amount }
        var seen = Set<Int>()
        return history.compactMap { e in
            guard seen.insert(e.playerIndex).inserted else { return nil }
            return (playerIndex: e.playerIndex, amount: latest[e.playerIndex] ?? e.amount)
        }
    }

    // MARK: - AI Auto-play

    private func processAITurnIfNeeded() async {
        // Fix 2: prevent two concurrent tasks (from back-to-back MC messages) from both
        // passing the post-sleep guard and double-playing. Reset before every re-trigger
        // and before each action so processPlayCard's internal calls can proceed.
        guard !isProcessingAI else {
            aiLog.debug("bail: AI already processing")
            return
        }
        guard isHost else {
            aiLog.debug("bail: not host")
            return
        }
        guard !aiSeats.isEmpty else {
            aiLog.error("bail: aiSeats EMPTY cap=\(self.currentActionPlayer) phase=\(self.phase.rawValue)")
            return
        }
        guard aiSeats.contains(currentActionPlayer) else {
            aiLog.error("bail: player\(self.currentActionPlayer) NOT AI aiSeats=\(self.aiSeats) phase=\(self.phase.rawValue)")
            return
        }
        isProcessingAI = true
        // Capture seat and phase BEFORE sleep — the action player or phase may change
        // during suspension (e.g. a human plays out of turn or a disconnect triggers cleanup).
        let seat = currentActionPlayer
        let capturedPhase = phase
        let delay = UInt64.random(in: 800_000_000...1_200_000_000)
        aiLog.debug("sleeping seat=\(seat) phase=\(capturedPhase.rawValue)")
        try? await Task.sleep(nanoseconds: delay)
        aiLog.debug("woke seat=\(seat) phase=\(capturedPhase.rawValue) aiSeats=\(self.aiSeats)")
        guard aiSeats.contains(seat), phase == capturedPhase, currentActionPlayer == seat else {
            aiLog.error("bail after sleep: seat=\(seat) capturedPhase=\(capturedPhase.rawValue) currentPhase=\(self.phase.rawValue) currentAction=\(self.currentActionPlayer)")
            // RC-B fix: reset flag before any re-trigger or watchdog arm.
            isProcessingAI = false
            let activePhases: [OnlineGamePhase] = [.bidding, .calling, .playing]
            if aiSeats.contains(currentActionPlayer) && activePhases.contains(phase) {
                // Another AI seat is now active — re-trigger.
                await processAITurnIfNeeded()
            } else if activePhases.contains(phase) && !aiSeats.contains(currentActionPlayer) {
                // State advanced to a human player's turn during our sleep.
                // applyGameState normally arms the watchdog when state changes, but if the
                // state update arrived while we held the CPU (no suspension point in
                // applyGameState), the watchdog for this new player may have been missed.
                // Re-arm defensively so the human's turn is always protected.
                startTurnWatchdog(seat: currentActionPlayer, capturedPhase: phase)
            }
            return
        }
        // Reset flag before the action — processPlayCard calls broadcastGameState which
        // calls processAITurnIfNeeded internally for the next player; if the flag were
        // still true those calls would bail immediately, breaking the chain.
        isProcessingAI = false
        let activePhase = capturedPhase
        switch activePhase {
        case .bidding:
            let amount = aiComputeBid(seat: seat)
            aiLog.debug("seat=\(seat) bid amount=\(amount)")
            if amount == 0 {
                await processPass(playerIndex: seat)
            } else {
                await processBid(playerIndex: seat, amount: amount)
            }
        case .calling:
            let result = aiComputeCalling(seat: seat)
            aiLog.debug("seat=\(seat) calling")
            await processCallCards(playerIndex: seat, trump: result.trump, c1: result.c1, c2: result.c2)
        case .playing:
            // Fix 1: aiComputeCard returns nil when hand is empty (stale state / sync lag).
            // Retry after 1s rather than injecting a phantom card.
            guard let cardId = aiComputeCard(seat: seat) else {
                aiLog.error("seat=\(seat) aiComputeCard returned nil (empty hand) — retrying in 1s")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                // Fix 2: state may have changed during the 1s sleep — only recurse if
                // this seat is still the current action player in the playing phase.
                // If a different AI now needs to act, the recovery re-triggers for them.
                guard currentActionPlayer == seat, phase == .playing else {
                    if aiSeats.contains(currentActionPlayer) && phase == .playing {
                        await processAITurnIfNeeded()
                    }
                    return
                }
                await processAITurnIfNeeded()
                return
            }
            aiLog.debug("seat=\(seat) playing \(cardId)")
            await processPlayCard(playerIndex: seat, cardId: cardId)
        default:
            aiLog.error("bail: unexpected phase \(activePhase.rawValue) seat=\(seat) aiSeats=\(self.aiSeats)")
            break
        }
    }

    private func aiComputeBid(seat: Int) -> Int {
        let hand = allHands[seat]
        let myPoints = hand.map(\.pointValue).reduce(0, +)
        let myIds = Set(hand.map(\.id))
        let topExternal = freshDeck()
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
        default:   bonusFraction = 0.38
        }
        let remaining = max(0, 250 - myPoints - call1Pts - call2Pts)
        let partnerBonus = Int(Double(remaining) * bonusFraction)

        // Phase 1b — Suit-clustering bonus
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

        // Phase 1c — Shortness penalty
        let thinSuits = TrumpSuit.allCases.filter { suit in
            hand.filter { $0.suit == suit.rawValue }.count <= 1
        }.count
        let shortnessPenalty = max(0, thinSuits - 2) * 8

        let estimated = myPoints + call1Pts + call2Pts + partnerBonus + clusterBonus - shortnessPenalty
        let canPass = highBid > 0
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
        let candidates = freshDeck()
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

    // Fix 1: returns nil when hand is empty so the caller can retry rather than
    // injecting a phantom "A♠" card that corrupts trick resolution.
    private func aiComputeCard(seat: Int) -> String? {
        let hand = allHands[seat]
        guard !hand.isEmpty else {
            aiLog.error("[aiComputeCard] seat=\(seat) has empty hand — returning nil")
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
        // Phase 3: only trump in if points are at stake or offense is urgent
        let trickPoints = currentTrick.map(\.card.pointValue).reduce(0, +)
        let trumpCards  = hand.filter { $0.suit == trumpRaw }
        if !trumpCards.isEmpty && (trickPoints > 0 || isUrgent) {
            return (trumpCards.min(by: { rankScore($0) < rankScore($1) }) ?? trumpCards[0]).id
        }
        let nonTrump = hand.filter { $0.suit != trumpRaw }
        if let discard = nonTrump.min(by: { valueScore($0) < valueScore($1) }) { return discard.id }
        return (trumpCards.min(by: { rankScore($0) < rankScore($1) }) ?? hand[0]).id
    }

    private var hostOffenseSet: Set<Int> {
        Set([highBidderIndex, hostPartner1, hostPartner2].filter { $0 >= 0 })
    }

    // MARK: - Card & Game Helpers

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

    private func parseCard(_ id: String) -> Card? {
        guard !id.isEmpty, let lastChar = id.last else { return nil }
        let rank = String(id.dropLast())
        guard !rank.isEmpty else { return nil }
        return Card(rank: rank, suit: String(lastChar))
    }

    private func freshDeck() -> [Card] {
        cardRanks.flatMap { rank in cardSuits.map { suit in Card(rank: rank, suit: suit) } }
    }

    private func setSmartCallingDefaults() {
        let hand = myHand
        let suitScores = TrumpSuit.allCases.map { suit -> (TrumpSuit, Int) in
            let pts = hand.filter { $0.suit == suit.rawValue }.map(\.pointValue).reduce(0, +)
            return (suit, pts)
        }
        trumpSuitSelection = suitScores.max(by: { $0.1 < $1.1 })?.0 ?? .spades

        let handIds = Set(hand.map(\.id))
        let candidates = freshDeck()
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
}

// MARK: - MCSessionDelegate

extension BluetoothGameViewModel: MCSessionDelegate {

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                if self.isHost {
                    // Assign a slot to the new peer
                    let nextSlot = (1..<6).first { !self.connectedPlayerSlots[$0].joined } ?? -1
                    guard nextSlot >= 0 else { return }

                    self.peerToPlayerIndex[peerID] = nextSlot
                    self.playerIndexToPeer[nextSlot] = peerID

                    // Use name/avatar from invitation context if available, else fall back to peerID displayName
                    let info = self.pendingPeerInfo.removeValue(forKey: peerID)
                    let name = info?["name"] ?? peerID.displayName
                    let avatar = info?["avatar"] ?? "🃏"
                    self.playerNames[nextSlot] = name
                    self.playerAvatars[nextSlot] = avatar
                    self.connectedPlayerSlots[nextSlot] = BTPlayerSlot(slotIndex: nextSlot, name: name, avatar: avatar, joined: true)

                    // Send slot assignment
                    let assignMsg: [String: Any] = [
                        "type": "assignSlot",
                        "playerIndex": nextSlot,
                        "playerNames": self.playerNames,
                        "playerAvatars": self.playerAvatars,
                        "aiSeats": self.aiSeats
                    ]
                    self.send(assignMsg, to: peerID)

                    // Broadcast updated lobby to all
                    let lobbyMsg: [String: Any] = [
                        "type": "lobbyUpdate",
                        "playerNames": self.playerNames,
                        "playerAvatars": self.playerAvatars
                    ]
                    self.sendToAll(lobbyMsg)
                } else {
                    // Find if peer is at index 0 (host)
                    self.playerIndexToPeer[0] = peerID
                    self.peerToPlayerIndex[peerID] = 0
                    self.sessionState = .connected
                }

            case .notConnected:
                self.pendingPeerInfo.removeValue(forKey: peerID)
                if let playerIdx = self.peerToPlayerIndex[peerID] {
                    if (self.sessionState == .playing || self.phase != .dealing)
                        && !self.hostEndedGame {
                        self.errorMessage = "\(self.playerName(playerIdx)) disconnected."
                    }
                    if self.isHost {
                        self.peerToPlayerIndex.removeValue(forKey: peerID)
                        self.playerIndexToPeer.removeValue(forKey: playerIdx)

                        // If a human disconnects mid-game, replace them with an AI bot so
                        // the game can continue rather than freeze waiting for their turn.
                        if self.phase == .playing || self.phase == .bidding ||
                           self.phase == .calling || self.phase == .lookingAtCards {
                            if !self.aiSeats.contains(playerIdx) {
                                self.aiSeats.append(playerIdx)
                                self.aiSeats.sort()
                                self.broadcastGameState()
                                // Fix 4: always re-trigger — don't gate on currentActionPlayer == playerIdx.
                                // The disconnect can race with an in-flight AI sleep: currentActionPlayer
                                // may have already advanced before this handler fires, making the old
                                // conditional check false even when the replaced seat is now active.
                                // processAITurnIfNeeded() bails immediately if no AI turn is needed.
                                Task { await self.processAITurnIfNeeded() }
                            }
                        }
                    }
                }

            default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        Task { @MainActor in
            self.handleMessage(dict, from: peerID)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension BluetoothGameViewModel: MCNearbyServiceAdvertiserDelegate {

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            // Auto-accept if there's an open slot
            let hasSlot = (1..<6).contains { !self.connectedPlayerSlots[$0].joined }
            guard hasSlot else {
                invitationHandler(false, nil)
                return
            }
            // Store peer's name/avatar for use in session:didChange:connected
            // Do NOT touch slots here — session:didChange:connected is the single
            // place that assigns slots, preventing the double-join bug.
            if let context,
               let info = try? JSONSerialization.jsonObject(with: context) as? [String: String] {
                self.pendingPeerInfo[peerID] = info
            }
            invitationHandler(true, self.session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            self.errorMessage = "Could not start hosting: \(error.localizedDescription)"
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension BluetoothGameViewModel: MCNearbyServiceBrowserDelegate {

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            let info = info ?? [:]
            // Avoid duplicates
            if !self.foundSessions.contains(where: { $0.peerID == peerID }) {
                self.foundSessions.append((peerID: peerID, info: info))
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.foundSessions.removeAll { $0.peerID == peerID }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            self.errorMessage = "Could not browse for games: \(error.localizedDescription)"
        }
    }
}

// MARK: - BTPlayerSlot

struct BTPlayerSlot {
    var slotIndex: Int
    var name: String
    var avatar: String
    var joined: Bool

    static func empty(at index: Int) -> BTPlayerSlot {
        BTPlayerSlot(slotIndex: index, name: "", avatar: "", joined: false)
    }
}

