import SwiftUI
import Observation
import FirebaseFirestore

// MARK: - Phase

enum OnlineGamePhase: String {
    case dealing, bidding, calling, playing, roundComplete, gameOver
}

// MARK: - ViewModel

@Observable @MainActor
final class OnlineGameViewModel {

    // MARK: Identity
    let myPlayerIndex: Int
    let isHost: Bool
    let sessionCode: String
    var playerNames: [String]

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
    var wonPointsPerPlayer: [Int] = Array(repeating: 0, count: 6)
    var runningScores: [Int] = Array(repeating: 0, count: 6)
    var message: String = ""
    var myHand: [Card] = []

    // MARK: UI state (local only — not synced from Firestore)
    var trumpSuitSelection: TrumpSuit = .spades
    var calledCard1Rank: String = "A"
    var calledCard1Suit: String = "♥"
    var calledCard2Rank: String = "K"
    var calledCard2Suit: String = "♦"
    var humanBidAmount: Double = 130
    var partnerRevealMessage: String? = nil
    var errorMessage: String? = nil

    // MARK: Host-only private state
    private var allHands: [[Card]] = Array(repeating: [], count: 6)
    private var hostPartner1: Int = -1
    private var hostPartner2: Int = -1
    private var hostCalledCard1: String = ""
    private var hostCalledCard2: String = ""
    private var listener: ListenerRegistration?
    private var lastProcessedNonce: String = ""

    // MARK: Partner reveal tracking (all devices)
    private var hasRevealedPartner1 = false
    private var hasRevealedPartner2 = false
    private var hasInitializedCalling = false

    // MARK: - Init

    init(
        myPlayerIndex: Int,
        isHost: Bool,
        sessionCode: String,
        playerNames: [String],
        dealerIndex: Int,
        roundNumber: Int
    ) {
        self.myPlayerIndex = myPlayerIndex
        self.isHost = isHost
        self.sessionCode = sessionCode
        self.playerNames = playerNames
        self.dealerIndex = dealerIndex
        self.roundNumber = roundNumber
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

    var bidHistoryOrdered: [(playerIndex: Int, amount: Int)] {
        (1...6).map { (dealerIndex + $0) % 6 }
            .filter { bids[$0] >= 0 }
            .map { (playerIndex: $0, amount: bids[$0]) }
    }

    var offensePoints: Int {
        (0..<6).filter { offenseSet.contains($0) }.map { wonPointsPerPlayer[$0] }.reduce(0, +)
    }

    var defensePoints: Int {
        (0..<6).filter { !offenseSet.contains($0) }.map { wonPointsPerPlayer[$0] }.reduce(0, +)
    }

    func playerName(_ index: Int) -> String {
        guard index >= 0 && index < playerNames.count else { return "Player \(index + 1)" }
        let n = playerNames[index]
        return n.isEmpty ? "Player \(index + 1)" : n
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
            "phase": OnlineGamePhase.bidding.rawValue,
            "roundNumber": roundNumber,
            "dealerIndex": dealerIndex,
            "currentActionPlayer": firstBidder,
            "bids": Array(repeating: -1, count: 6),
            "highBid": 0,
            "highBidderIndex": -1,
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
            "message": "Bidding has started!"
        ]
        try? await ref.updateData([
            "gameState": gs,
            "hands": handsDict,
            "pendingAction": [:] as [String: Any]
        ])
    }

    func startNextRound() async {
        dealerIndex = (dealerIndex + 1) % 6
        roundNumber += 1
        await startGame()
    }

    // MARK: - Listener

    func attachListener() {
        let db = Firestore.firestore()
        listener = db.collection("sessions").document(sessionCode)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let data = snapshot?.data() else { return }
                Task { @MainActor [weak self] in
                    await self?.handleSnapshot(data)
                }
            }
    }

    private func handleSnapshot(_ data: [String: Any]) async {
        // Parse game state
        if let gs = data["gameState"] as? [String: Any] {
            parseGameState(gs)
        }

        // Parse my hand
        if let handsData = data["hands"] as? [String: Any],
           let myCards = handsData["\(myPlayerIndex)"] as? [String] {
            myHand = myCards.compactMap { parseCard($0) }
        }

        // Host: process pending action
        if isHost, let actionData = data["pendingAction"] as? [String: Any],
           let nonce = actionData["nonce"] as? String,
           !nonce.isEmpty, nonce != lastProcessedNonce {
            await processPendingAction(actionData)
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

        // Partner reveal detection (before updating)
        if newPhase == .playing || newPhase == .roundComplete || newPhase == .gameOver {
            if !hasRevealedPartner1 && newP1 >= 0 {
                hasRevealedPartner1 = true
                let name = playerName(newP1)
                let isSelf = newP1 == myPlayerIndex
                partnerRevealMessage = isSelf ? "You are a partner!" : "\(name) is a partner!"
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    self.partnerRevealMessage = nil
                }
            }
            if !hasRevealedPartner2 && newP2 >= 0 {
                hasRevealedPartner2 = true
                let name = playerName(newP2)
                let isSelf = newP2 == myPlayerIndex
                let msg = isSelf ? "You are a partner!" : "\(name) is a partner!"
                // Only show if different from current message
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

        // Reset reveal flags on new round
        if newP1 == -1 { hasRevealedPartner1 = false }
        if newP2 == -1 { hasRevealedPartner2 = false }

        // Update published props
        phase = newPhase
        roundNumber = newRoundNumber
        dealerIndex = i("dealerIndex")
        currentActionPlayer = newCurrentActionPlayer
        if let bidsAny = gs["bids"] as? [Any] {
            bids = bidsAny.map { ($0 as? Int) ?? ($0 as? Int64).map(Int.init) ?? -1 }
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
        currentLeaderIndex = i("currentLeaderIndex")
        trickNumber = i("trickNumber")
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
    }

    private func parseCard(_ id: String) -> Card? {
        guard !id.isEmpty, let lastChar = id.last else { return nil }
        let rank = String(id.dropLast())
        guard !rank.isEmpty else { return nil }
        return Card(rank: rank, suit: String(lastChar))
    }

    // MARK: - Player Actions

    func placeBid(_ amount: Int) async {
        let db = Firestore.firestore()
        let ref = db.collection("sessions").document(sessionCode)
        let action: [String: Any] = [
            "nonce": UUID().uuidString,
            "playerIndex": myPlayerIndex,
            "type": "bid",
            "bidAmount": amount
        ]
        try? await ref.updateData(["pendingAction": action])
    }

    func pass() async {
        let db = Firestore.firestore()
        let ref = db.collection("sessions").document(sessionCode)
        let action: [String: Any] = [
            "nonce": UUID().uuidString,
            "playerIndex": myPlayerIndex,
            "type": "pass"
        ]
        try? await ref.updateData(["pendingAction": action])
    }

    func confirmCalling() async {
        let c1 = calledCard1Rank + calledCard1Suit
        let c2 = calledCard2Rank + calledCard2Suit
        let db = Firestore.firestore()
        let ref = db.collection("sessions").document(sessionCode)
        let action: [String: Any] = [
            "nonce": UUID().uuidString,
            "playerIndex": myPlayerIndex,
            "type": "callCards",
            "trump": trumpSuitSelection.rawValue,
            "calledCard1": c1,
            "calledCard2": c2
        ]
        try? await ref.updateData(["pendingAction": action])
    }

    func playCard(_ card: Card) async {
        let db = Firestore.firestore()
        let ref = db.collection("sessions").document(sessionCode)
        let action: [String: Any] = [
            "nonce": UUID().uuidString,
            "playerIndex": myPlayerIndex,
            "type": "playCard",
            "cardId": card.id
        ]
        try? await ref.updateData(["pendingAction": action])
    }

    // MARK: - Host: Process Pending Action

    private func processPendingAction(_ actionData: [String: Any]) async {
        guard let nonce = actionData["nonce"] as? String,
              let type = actionData["type"] as? String,
              let playerIndex = (actionData["playerIndex"] as? Int) ??
                  (actionData["playerIndex"] as? Int64).map(Int.init)
        else { return }

        lastProcessedNonce = nonce

        let db = Firestore.firestore()
        let ref = db.collection("sessions").document(sessionCode)

        switch type {
        case "bid":
            let amount = (actionData["bidAmount"] as? Int) ??
                (actionData["bidAmount"] as? Int64).map(Int.init) ?? 0
            var newBids = bids
            newBids[playerIndex] = amount
            var newHighBid = highBid
            var newHighBidder = highBidderIndex
            if amount > newHighBid { newHighBid = amount; newHighBidder = playerIndex }

            let order = (1...6).map { (dealerIndex + $0) % 6 }
            let nextBidder = order.first(where: { newBids[$0] == -1 })

            if let next = nextBidder {
                let gs = buildGS(phase: .bidding, currentActionPlayer: next,
                    bids: newBids, highBid: newHighBid, highBidderIndex: newHighBidder,
                    message: "\(playerName(playerIndex)) bid \(amount)")
                try? await ref.updateData(["gameState": gs, "pendingAction": [:] as [String: Any]])
            } else {
                await concludeBidding(ref: ref, bids: newBids, highBid: newHighBid, highBidder: newHighBidder)
            }

        case "pass":
            var newBids = bids
            newBids[playerIndex] = 0
            let order = (1...6).map { (dealerIndex + $0) % 6 }
            let nextBidder = order.first(where: { newBids[$0] == -1 })

            if let next = nextBidder {
                let gs = buildGS(phase: .bidding, currentActionPlayer: next,
                    bids: newBids, highBid: highBid, highBidderIndex: highBidderIndex,
                    message: "\(playerName(playerIndex)) passed")
                try? await ref.updateData(["gameState": gs, "pendingAction": [:] as [String: Any]])
            } else {
                await concludeBidding(ref: ref, bids: newBids, highBid: highBid, highBidder: highBidderIndex)
            }

        case "callCards":
            let trumpStr = actionData["trump"] as? String ?? TrumpSuit.spades.rawValue
            let c1 = actionData["calledCard1"] as? String ?? ""
            let c2 = actionData["calledCard2"] as? String ?? ""
            let (p1, p2) = resolvePartners(c1: c1, c2: c2)
            hostPartner1 = p1; hostPartner2 = p2
            hostCalledCard1 = c1; hostCalledCard2 = c2

            let leader = (dealerIndex + 1) % 6
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
            try? await ref.updateData(["gameState": gs, "pendingAction": [:] as [String: Any]])

        case "playCard":
            let cardId = actionData["cardId"] as? String ?? ""
            guard let card = parseCard(cardId),
                  allHands[playerIndex].contains(where: { $0.id == cardId }) else { return }

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
                let winner = trickWinnerIndex(trick: newTrick)
                let pts = newTrick.map(\.card.pointValue).reduce(0, +)
                var newWon = wonPointsPerPlayer
                newWon[winner] += pts
                let newTrickNum = trickNumber + 1

                if newTrickNum == 8 {
                    let offSet = Set([highBidderIndex, hostPartner1, hostPartner2].filter { $0 >= 0 })
                    let offPts = (0..<6).filter { offSet.contains($0) }.map { newWon[$0] }.reduce(0, +)
                    let defPts = (0..<6).filter { !offSet.contains($0) }.map { newWon[$0] }.reduce(0, +)
                    let bidMade = offPts >= highBid

                    var newRS = runningScores
                    for i in 0..<6 {
                        if i == highBidderIndex {
                            newRS[i] += bidMade ? offPts : -highBid
                        } else if offSet.contains(i) {
                            newRS[i] += bidMade ? offPts : 0
                        } else {
                            newRS[i] += defPts
                        }
                    }

                    let nextPhase: OnlineGamePhase = (newRS.max() ?? 0) >= 500 ? .gameOver : .roundComplete
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
                    try? await ref.updateData(["gameState": gs, "hands": handsDict, "pendingAction": [:] as [String: Any]])
                } else {
                    var gs = buildGS(phase: .playing, currentActionPlayer: winner,
                        bids: bids, highBid: highBid, highBidderIndex: highBidderIndex,
                        message: "\(playerName(winner)) wins the trick!")
                    gs["currentTrick"] = [] as [[String: Any]]
                    gs["trickNumber"] = newTrickNum
                    gs["wonPointsPerPlayer"] = newWon
                    gs["currentLeaderIndex"] = winner
                    gs["partner1Index"] = newP1
                    gs["partner2Index"] = newP2
                    try? await ref.updateData(["gameState": gs, "hands": handsDict, "pendingAction": [:] as [String: Any]])
                }
            } else {
                // Trick in progress — advance to next in order
                let trickOrder = (0..<6).map { (currentLeaderIndex + $0) % 6 }
                let pos = trickOrder.firstIndex(of: playerIndex) ?? 0
                let nextPlayer = trickOrder[min(pos + 1, 5)]

                var gs = buildGS(phase: .playing, currentActionPlayer: nextPlayer,
                    bids: bids, highBid: highBid, highBidderIndex: highBidderIndex,
                    message: "\(playerName(playerIndex)) played \(card.rank)\(card.suit)")
                gs["currentTrick"] = trickData
                gs["partner1Index"] = newP1
                gs["partner2Index"] = newP2
                try? await ref.updateData(["gameState": gs, "hands": handsDict, "pendingAction": [:] as [String: Any]])
            }

        default:
            break
        }
    }

    // MARK: - Host Helpers

    private func concludeBidding(ref: DocumentReference, bids: [Int], highBid: Int, highBidder: Int) async {
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
        try? await ref.updateData(["gameState": gs, "pendingAction": [:] as [String: Any]])
    }

    private func buildGS(
        phase: OnlineGamePhase,
        currentActionPlayer: Int,
        bids: [Int],
        highBid: Int,
        highBidderIndex: Int,
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
