import SwiftUI
import FirebaseFirestore
import Observation

// MARK: - Supporting Types

struct SessionPlayer: Identifiable {
    var id: String { uid.isEmpty ? "slot-\(slotIndex)" : uid }
    var slotIndex: Int
    var uid: String
    var name: String
    var avatar: String
    var joined: Bool

    static func empty(at index: Int) -> SessionPlayer {
        SessionPlayer(slotIndex: index, uid: "", name: "", avatar: "", joined: false)
    }
}

struct OnlineRound {
    var roundNumber: Int
    var dealerIndex: Int
    var bidderIndex: Int
    var bidAmount: Int
    var trumpSuit: String
    var callCard1: String
    var callCard2: String
    var partner1Index: Int
    var partner2Index: Int
    var offensePointsCaught: Int
    var defensePointsCaught: Int

    var firestoreData: [String: Any] {
        [
            "roundNumber": roundNumber,
            "dealerIndex": dealerIndex,
            "bidderIndex": bidderIndex,
            "bidAmount": bidAmount,
            "trumpSuit": trumpSuit,
            "callCard1": callCard1,
            "callCard2": callCard2,
            "partner1Index": partner1Index,
            "partner2Index": partner2Index,
            "offensePointsCaught": offensePointsCaught,
            "defensePointsCaught": defensePointsCaught
        ]
    }

    init?(from data: [String: Any]) {
        // Firestore returns numbers as Int64 on iOS; fall back gracefully
        func int(_ key: String) -> Int? {
            (data[key] as? Int) ?? (data[key] as? Int64).map(Int.init)
        }
        guard
            let roundNumber          = int("roundNumber"),
            let dealerIndex          = int("dealerIndex"),
            let bidderIndex          = int("bidderIndex"),
            let bidAmount            = int("bidAmount"),
            let trumpSuit            = data["trumpSuit"] as? String,
            let callCard1            = data["callCard1"] as? String,
            let callCard2            = data["callCard2"] as? String,
            let partner1Index        = int("partner1Index"),
            let partner2Index        = int("partner2Index"),
            let offensePointsCaught  = int("offensePointsCaught"),
            let defensePointsCaught  = int("defensePointsCaught")
        else { return nil }

        self.roundNumber = roundNumber
        self.dealerIndex = dealerIndex
        self.bidderIndex = bidderIndex
        self.bidAmount = bidAmount
        self.trumpSuit = trumpSuit
        self.callCard1 = callCard1
        self.callCard2 = callCard2
        self.partner1Index = partner1Index
        self.partner2Index = partner2Index
        self.offensePointsCaught = offensePointsCaught
        self.defensePointsCaught = defensePointsCaught
    }

    init(from round: Round) {
        roundNumber = round.roundNumber
        dealerIndex = round.dealerIndex
        bidderIndex = round.bidderIndex
        bidAmount = round.bidAmount
        trumpSuit = round.trumpSuitRaw
        callCard1 = round.callCard1
        callCard2 = round.callCard2
        partner1Index = round.partner1Index
        partner2Index = round.partner2Index
        offensePointsCaught = round.offensePointsCaught
        defensePointsCaught = round.defensePointsCaught
    }
}

enum SessionStatus: String {
    case idle, waiting, playing, finished
}

// MARK: - ViewModel

@MainActor
@Observable final class OnlineSessionViewModel {
    var sessionCode: String? = nil
    /// True once writeSessionToFirebase() has confirmed a unique room code in Firestore.
    /// Show the QR code / share UI only when this is true — avoids displaying a code that
    /// Firestore may reassign via findUniqueRoomCode().
    var isSessionCodeConfirmed: Bool = false
    var playerSlots: [SessionPlayer] = (0..<6).map { SessionPlayer.empty(at: $0) }
    var status: SessionStatus = .idle
    var isHost: Bool = false
    var rounds: [OnlineRound] = []
    var errorMessage: String? = nil
    var aiSeats: [Int] = []
    var sessionType: String = "online"
    /// True while the Firebase document write is in-flight (after prepareLocalSession)
    var isConnecting: Bool = false
    /// Slot index this non-host player joined (set in joinSession; -1 for host).
    private var myJoinedSlotIndex: Int = -1

    /// Called by GameViewModel to propagate round updates
    var onSessionUpdated: (() -> Void)? = nil

    private var listener: ListenerRegistration? = nil
    private let db = Firestore.firestore()
    // Pending values stored by prepareLocalSession for later Firebase write
    private var pendingUID: String = ""
    private var pendingName: String = ""
    private var pendingAvatar: String = ""

    deinit { listener?.remove() }

    var allSlotsJoined: Bool { playerSlots.allSatisfy(\.joined) }

    var humanSlotsFull: Bool {
        (0..<6).filter { !aiSeats.contains($0) }.allSatisfy { playerSlots[$0].joined }
    }

    // MARK: - Session CRUD

    @discardableResult
    func createSession(uid: String, name: String, avatar: String = "",
                       aiSeats newAISeats: [Int] = [], sessionType newSessionType: String = "online") async -> String {
        let code = await findUniqueRoomCode()
        var slots: [[String: Any]] = (0..<6).map { _ in ["uid": "", "name": "", "avatar": "", "joined": false] }
        slots[0] = ["uid": uid, "name": name, "avatar": avatar, "joined": true]

        // Pre-fill AI slots with unique random avatars (exclude host's avatar)
        let aiNamePool = Comic.aiNamePool
        let shuffledAINames = Array(aiNamePool.shuffled().prefix(newAISeats.count))
        let aiAvatars = Comic.randomAIAvatars(count: newAISeats.count, excluding: [avatar])
        for (n, i) in newAISeats.enumerated() {
            slots[i] = ["uid": "AI-\(i)", "name": shuffledAINames[n], "avatar": aiAvatars[safe: n] ?? "🤖", "joined": true]
        }

        let data: [String: Any] = [
            "hostUid": uid,
            "status": SessionStatus.waiting.rawValue,
            "createdAt": Timestamp(),
            "currentDealerIndex": 0,
            "playerSlots": slots,
            "rounds": [],
            "aiSeats": newAISeats,
            "sessionType": newSessionType
        ]

        do {
            try await db.collection("sessions").document(code).setData(data)
            sessionCode = code
            isHost = true
            self.aiSeats = newAISeats
            self.sessionType = newSessionType
            attachListener(code: code)
        } catch {
            errorMessage = "Failed to create session. Please try again."
        }
        return code
    }

    /// Synchronously sets up local state (session code, host flag, player slots).
    /// Call this first, then `showingLobby = true`, then `writeSessionToFirebase()` in a Task.
    @discardableResult
    func prepareLocalSession(uid: String, name: String, avatar: String = "",
                              aiSeats newAISeats: [Int] = [], sessionType newSessionType: String = "online") -> String {
        let code = generateRoomCode()
        // Note: sessionCode is set to the tentative code here so the lobby view renders
        // immediately. writeSessionToFirebase() may assign a different confirmed code via
        // findUniqueRoomCode() — it updates sessionCode + sets isSessionCodeConfirmed = true.
        // The share/QR buttons are disabled until isConnecting = false (i.e., confirmed).
        sessionCode = code
        isSessionCodeConfirmed = false
        isHost = true
        isConnecting = true
        errorMessage = nil
        self.aiSeats = newAISeats
        self.sessionType = newSessionType
        pendingUID = uid
        pendingName = name
        pendingAvatar = avatar

        let aiNamePool = Comic.aiNamePool
        let shuffledNames = Array(aiNamePool.shuffled().prefix(newAISeats.count))
        let aiAvatars = Comic.randomAIAvatars(count: newAISeats.count, excluding: [avatar])
        var slots = (0..<6).map { SessionPlayer.empty(at: $0) }
        slots[0] = SessionPlayer(slotIndex: 0, uid: uid, name: name, avatar: avatar, joined: true)
        for (n, i) in newAISeats.enumerated() {
            slots[i] = SessionPlayer(slotIndex: i, uid: "AI-\(i)",
                                     name: shuffledNames[n], avatar: aiAvatars[safe: n] ?? "🤖", joined: true)
        }
        playerSlots = slots
        return code
    }

    /// Writes the prepared session to Firestore and attaches the listener.
    /// Call this after `prepareLocalSession` (and after setting `showingLobby = true`).
    func writeSessionToFirebase() async {
        let code = await findUniqueRoomCode()
        sessionCode = code
        let slotsData = playerSlots.map { slot -> [String: Any] in
            ["uid": slot.uid, "name": slot.name, "avatar": slot.avatar, "joined": slot.joined]
        }
        let data: [String: Any] = [
            "hostUid": pendingUID,
            "status": SessionStatus.waiting.rawValue,
            "createdAt": Timestamp(),
            "currentDealerIndex": 0,
            "playerSlots": slotsData,
            "rounds": [],
            "aiSeats": aiSeats,
            "sessionType": sessionType
        ]
        do {
            try await db.collection("sessions").document(code).setData(data)
            isConnecting = false
            isSessionCodeConfirmed = true
            attachListener(code: code)
        } catch {
            errorMessage = "Connection failed. Tap Retry to try again."
            isConnecting = false
        }
    }

    func joinSession(code: String, uid: String, name: String, avatar: String = "") async throws {
        let ref = db.collection("sessions").document(code)

        // CRIT-03: Wrap slot claim in a Firestore transaction to prevent two simultaneous
        // joins from both reading the same empty slot and overwriting each other.
        var resolvedJoinIndex: Int = -1

        try await db.runTransaction { [weak self] transaction, errorPointer in
            guard let self else { return nil }
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }

            guard snapshot.exists,
                  let data = snapshot.data(),
                  let slotsData = data["playerSlots"] as? [[String: Any]] else {
                errorPointer?.pointee = NSError(
                    domain: "JoinSession", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Session not found"])
                return nil
            }

            let sessionStatus = data["status"] as? String ?? "waiting"
            guard sessionStatus == "waiting" else {
                errorPointer?.pointee = NSError(
                    domain: "JoinSession", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Session already started"])
                return nil
            }

            let rawAISeats = (data["aiSeats"] as? [Any] ?? [])
                .compactMap { ($0 as? Int) ?? ($0 as? Int64).map(Int.init) }
                .sorted()

            let joinIndex: Int
            if let firstAI = rawAISeats.first, firstAI >= 0 && firstAI < slotsData.count {
                joinIndex = firstAI
            } else {
                guard let idx = slotsData.firstIndex(where: { !($0["joined"] as? Bool ?? false) }) else {
                    errorPointer?.pointee = NSError(
                        domain: "JoinSession", code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "No slots available"])
                    return nil
                }
                joinIndex = idx
            }

            var updated = slotsData
            updated[joinIndex] = ["uid": uid, "name": name, "avatar": avatar, "joined": true]
            let newAISeats = rawAISeats.filter { $0 != joinIndex }
            transaction.updateData(["playerSlots": updated, "aiSeats": newAISeats], forDocument: ref)
            resolvedJoinIndex = joinIndex
            return nil
        }

        guard resolvedJoinIndex >= 0 else {
            throw URLError(.resourceUnavailable)
        }

        sessionCode = code
        isHost = false
        myJoinedSlotIndex = resolvedJoinIndex
        attachListener(code: code)
    }

    func removePlayer(atSlot slotIndex: Int) async {
        guard let code = sessionCode,
              isHost,
              slotIndex != 0 else { return }

        let ref = db.collection("sessions").document(code)
        let snapshot = try? await ref.getDocument()
        guard let data = snapshot?.data(),
              var slotsData = data["playerSlots"] as? [[String: Any]],
              slotIndex < slotsData.count
        else { return }

        var currentAISeats = (data["aiSeats"] as? [Any] ?? []).compactMap {
            ($0 as? Int) ?? ($0 as? Int64).map(Int.init)
        }

        let isAISlot = currentAISeats.contains(slotIndex)

        if isAISlot {
            // Removing an AI bot — free the slot so a human can join
            slotsData[slotIndex] = ["uid": "", "name": "", "avatar": "", "joined": false]
            currentAISeats.removeAll { $0 == slotIndex }
            try? await ref.updateData([
                "playerSlots": slotsData,
                "aiSeats": currentAISeats
            ])
        } else {
            // Removing a human player — replace with AI bot
            let aiNamePool = Comic.aiNamePool
            let usedNames = slotsData.compactMap { $0["name"] as? String }
            let aiName = aiNamePool.filter { !usedNames.contains($0) }.first ?? "Bot"
            let usedAvatars = Set(slotsData.compactMap { $0["avatar"] as? String }.filter { !$0.isEmpty })
            let aiAvatar = Comic.randomAIAvatars(count: 1, excluding: usedAvatars).first ?? "🤖"

            slotsData[slotIndex] = [
                "uid": "AI-\(slotIndex)",
                "name": aiName,
                "avatar": aiAvatar,
                "joined": true
            ]
            currentAISeats.append(slotIndex)
            currentAISeats.sort()
            try? await ref.updateData([
                "playerSlots": slotsData,
                "aiSeats": currentAISeats,
                "removedSlot": slotIndex
            ])
        }
    }

    func startGame() async {
        guard let code = sessionCode, isHost else { return }
        let ref = db.collection("sessions").document(code)

        // Auto-fill any remaining empty slots with AI bots before starting
        if let data = try? await ref.getDocument().data(),
           var slotsData = data["playerSlots"] as? [[String: Any]] {
            var currentAISeats = (data["aiSeats"] as? [Any] ?? []).compactMap {
                ($0 as? Int) ?? ($0 as? Int64).map(Int.init)
            }
            let aiNamePool = Comic.aiNamePool
            var changed = false
            // Pre-compute available avatars once; remove as we assign to keep each AI unique
            var usedAvatars = Set(slotsData.compactMap { $0["avatar"] as? String }.filter { !$0.isEmpty })
            var availableAvatars = Comic.randomAIAvatars(count: 6, excluding: usedAvatars)
            for i in 1..<6 {
                let joined = slotsData[i]["joined"] as? Bool ?? false
                if !joined {
                    let usedNames = slotsData.compactMap { $0["name"] as? String }
                    let aiName = aiNamePool.filter { !usedNames.contains($0) }.first ?? "Bot\(i)"
                    let aiAvatar = availableAvatars.isEmpty ? "🤖" : availableAvatars.removeFirst()
                    usedAvatars.insert(aiAvatar)
                    slotsData[i] = ["uid": "AI-\(i)", "name": aiName, "avatar": aiAvatar, "joined": true]
                    if !currentAISeats.contains(i) { currentAISeats.append(i) }
                    changed = true
                }
            }
            if changed {
                currentAISeats.sort()
                try? await ref.updateData(["playerSlots": slotsData, "aiSeats": currentAISeats])
            }
        }

        do {
            try await ref.updateData(["status": SessionStatus.playing.rawValue])
        } catch {
            errorMessage = "Failed to start game. Please try again."
        }
    }

    func addRound(_ data: OnlineRound) async {
        guard let code = sessionCode else { return }
        do {
            try await db.collection("sessions").document(code)
                .updateData(["rounds": FieldValue.arrayUnion([data.firestoreData])])
        } catch {
            errorMessage = "Failed to save round. Please try again."
        }
    }

    func leaveSession() async {
        // LOW-02: clear this player's Firestore slot so the lobby updates for remaining
        // players and the slot becomes available for a new human to join.
        let slotToClear = myJoinedSlotIndex
        if let code = sessionCode, !isHost, slotToClear >= 0 {
            let ref = db.collection("sessions").document(code)
            if let data = (try? await ref.getDocument())?.data(),
               var slotsData = data["playerSlots"] as? [[String: Any]],
               slotToClear < slotsData.count {
                var currentAISeats = (data["aiSeats"] as? [Any] ?? []).compactMap {
                    ($0 as? Int) ?? ($0 as? Int64).map(Int.init)
                }
                slotsData[slotToClear] = ["uid": "", "name": "", "avatar": "", "joined": false]
                if !currentAISeats.contains(slotToClear) { currentAISeats.append(slotToClear) }
                currentAISeats.sort()
                try? await ref.updateData([
                    "playerSlots": slotsData,
                    "aiSeats": currentAISeats
                ])
            }
        }
        listener?.remove()
        listener = nil
        sessionCode = nil
        isHost = false
        myJoinedSlotIndex = -1
        status = .idle
        playerSlots = (0..<6).map { SessionPlayer.empty(at: $0) }
        rounds = []
        onSessionUpdated = nil
    }

    // MARK: - Real-time Listener

    private func attachListener(code: String) {
        listener?.remove()
        listener = db.collection("sessions").document(code)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let data = snapshot?.data() else { return }
                // Firebase SDK may deliver on a background thread; @Observable is not
                // thread-safe, so dispatch all mutations to the main actor.
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    if let slotsData = data["playerSlots"] as? [[String: Any]] {
                        var slots = slotsData.enumerated().map { i, slot in
                            SessionPlayer(slotIndex: i,
                                          uid: slot["uid"] as? String ?? "",
                                          name: slot["name"] as? String ?? "",
                                          avatar: slot["avatar"] as? String ?? "",
                                          joined: slot["joined"] as? Bool ?? false)
                        }
                        while slots.count < 6 { slots.append(SessionPlayer.empty(at: slots.count)) }
                        self.playerSlots = slots
                    }

                    if let rawStatus = data["status"] as? String {
                        self.status = SessionStatus(rawValue: rawStatus) ?? .waiting
                    }

                    if let roundsData = data["rounds"] as? [[String: Any]] {
                        self.rounds = roundsData.compactMap { OnlineRound(from: $0) }
                    }

                    if let aiSeatsData = data["aiSeats"] as? [Any] {
                        self.aiSeats = aiSeatsData.compactMap { ($0 as? Int) ?? ($0 as? Int64).map(Int.init) }
                    }
                    if let type = data["sessionType"] as? String {
                        self.sessionType = type
                    }

                    self.onSessionUpdated?()
                }
            }
    }

    // MARK: - Helpers

    private func generateRoomCode() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<6).compactMap { _ in chars.randomElement() })
    }

    /// Returns a room code that does not already exist in Firestore.
    /// Retries up to 5 times — with 36^6 ≈ 2.2B combinations the probability of
    /// needing even one retry is negligible.
    private func findUniqueRoomCode() async -> String {
        let ref = db.collection("sessions")
        for _ in 0..<5 {
            let code = generateRoomCode()
            let snap = try? await ref.document(code).getDocument()
            if snap?.exists != true { return code }
        }
        return generateRoomCode()
    }
}
