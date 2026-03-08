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

    /// Called by GameViewModel to propagate round updates
    var onSessionUpdated: (() -> Void)? = nil

    private var listener: ListenerRegistration? = nil
    private let db = Firestore.firestore()

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
        let aiNamePool = ["Alex", "Jordan", "Sam", "Riley", "Morgan", "Casey"]
        for (n, i) in newAISeats.enumerated() {
            slots[i] = ["uid": "AI-\(i)", "name": aiNamePool[n % aiNamePool.count], "avatar": "🤖", "joined": true]
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

    func joinSession(code: String, uid: String, name: String, avatar: String = "") async throws {
        let ref = db.collection("sessions").document(code)
        let snapshot = try await ref.getDocument()

        guard snapshot.exists,
              let slotsData = snapshot.data()?["playerSlots"] as? [[String: Any]] else {
            throw URLError(.badServerResponse)
        }
        guard let emptyIndex = slotsData.firstIndex(where: { !($0["joined"] as? Bool ?? false) }) else {
            throw URLError(.resourceUnavailable)
        }

        var updated = slotsData
        updated[emptyIndex] = ["uid": uid, "name": name, "avatar": avatar, "joined": true]
        try await ref.updateData(["playerSlots": updated])

        sessionCode = code
        isHost = false
        attachListener(code: code)
    }

    func startGame() async {
        guard let code = sessionCode, isHost else { return }
        do {
            try await db.collection("sessions").document(code)
                .updateData(["status": SessionStatus.playing.rawValue])
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
