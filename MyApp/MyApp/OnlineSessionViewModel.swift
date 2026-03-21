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

@Observable final class OnlineSessionViewModel {
    var sessionCode: String? = nil
    var playerSlots: [SessionPlayer] = (0..<6).map { SessionPlayer.empty(at: $0) }
    var status: SessionStatus = .idle
    var isHost: Bool = false
    var rounds: [OnlineRound] = []
    var errorMessage: String? = nil
    var aiSeats: [Int] = []
    var sessionType: String = "online"
    /// True while the Firebase document write is in-flight (after prepareLocalSession)
    var isConnecting: Bool = false

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
        let code = generateRoomCode()
        var slots: [[String: Any]] = (0..<6).map { _ in ["uid": "", "name": "", "avatar": "", "joined": false] }
        slots[0] = ["uid": uid, "name": name, "avatar": avatar, "joined": true]

        // Pre-fill AI slots
        let aiNamePool = ["Drew", "Jamie", "Casey", "Morgan", "Riley", "Jordan", "Alex", "Sam", "Taylor", "Avery"]
        let shuffledAINames = Array(aiNamePool.shuffled().prefix(newAISeats.count))
        for (n, i) in newAISeats.enumerated() {
            slots[i] = ["uid": "AI-\(i)", "name": shuffledAINames[n], "avatar": "🤖", "joined": true]
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
        sessionCode = code
        isHost = true
        isConnecting = true
        errorMessage = nil
        self.aiSeats = newAISeats
        self.sessionType = newSessionType
        pendingUID = uid
        pendingName = name
        pendingAvatar = avatar

        let aiNamePool = ["Drew", "Jamie", "Casey", "Morgan", "Riley", "Jordan", "Alex", "Sam", "Taylor", "Avery"]
        let shuffledNames = Array(aiNamePool.shuffled().prefix(newAISeats.count))
        var slots = (0..<6).map { SessionPlayer.empty(at: $0) }
        slots[0] = SessionPlayer(slotIndex: 0, uid: uid, name: name, avatar: avatar, joined: true)
        for (n, i) in newAISeats.enumerated() {
            slots[i] = SessionPlayer(slotIndex: i, uid: "AI-\(i)",
                                     name: shuffledNames[n], avatar: "🤖", joined: true)
        }
        playerSlots = slots
        return code
    }

    /// Writes the prepared session to Firestore and attaches the listener.
    /// Call this after `prepareLocalSession` (and after setting `showingLobby = true`).
    func writeSessionToFirebase() async {
        guard let code = sessionCode else { return }
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
            attachListener(code: code)
        } catch {
            errorMessage = "Connection failed. Tap Retry to try again."
            isConnecting = false
        }
    }

    func joinSession(code: String, uid: String, name: String, avatar: String = "") async throws {
        let ref = db.collection("sessions").document(code)

        let snapshot: DocumentSnapshot
        do {
            snapshot = try await ref.getDocument()
        } catch {
            print("joinSession: getDocument failed — \(error)")
            throw error
        }

        guard snapshot.exists else {
            print("joinSession: document does not exist for code \(code)")
            throw URLError(.badServerResponse)
        }

        guard let data = snapshot.data(),
              let slotsData = data["playerSlots"] as? [[String: Any]] else {
            print("joinSession: bad data shape")
            throw URLError(.badServerResponse)
        }

        let rawAISeats = (data["aiSeats"] as? [Any] ?? [])
            .compactMap { ($0 as? Int) ?? ($0 as? Int64).map(Int.init) }
            .sorted()

        let joinIndex: Int
        if let firstAI = rawAISeats.first {
            // Multiplayer: replace the lowest-numbered AI slot
            joinIndex = firstAI
        } else {
            // Classic online: find first empty slot
            guard let idx = slotsData.firstIndex(where: { !($0["joined"] as? Bool ?? false) }) else {
                throw URLError(.resourceUnavailable)
            }
            joinIndex = idx
        }

        var updated = slotsData
        updated[joinIndex] = ["uid": uid, "name": name, "avatar": avatar, "joined": true]
        let newAISeats = rawAISeats.filter { $0 != joinIndex }
        try await ref.updateData(["playerSlots": updated, "aiSeats": newAISeats])

        sessionCode = code
        isHost = false
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
            let aiNamePool = ["Drew", "Jamie", "Casey", "Morgan",
                              "Riley", "Jordan", "Alex", "Sam", "Taylor", "Avery"]
            let usedNames = slotsData.compactMap { $0["name"] as? String }
            let aiName = aiNamePool.filter { !usedNames.contains($0) }.first ?? "Bot"

            slotsData[slotIndex] = [
                "uid": "AI-\(slotIndex)",
                "name": aiName,
                "avatar": "🤖",
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
            let aiNamePool = ["Drew", "Jamie", "Casey", "Morgan",
                              "Riley", "Jordan", "Alex", "Sam", "Taylor", "Avery"]
            var changed = false
            for i in 1..<6 {
                let joined = slotsData[i]["joined"] as? Bool ?? false
                if !joined {
                    let usedNames = slotsData.compactMap { $0["name"] as? String }
                    let aiName = aiNamePool.filter { !usedNames.contains($0) }.first ?? "Bot\(i)"
                    slotsData[i] = ["uid": "AI-\(i)", "name": aiName, "avatar": "🤖", "joined": true]
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
        listener?.remove()
        listener = nil
        sessionCode = nil
        isHost = false
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
                guard let self, let data = snapshot?.data() else { return }

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

    // MARK: - Helpers

    private func generateRoomCode() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<6).compactMap { _ in chars.randomElement() })
    }
}
