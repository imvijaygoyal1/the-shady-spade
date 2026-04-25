import Foundation
import FirebaseAuth
import FirebaseFirestore
import Network
import SwiftUI
import OSLog

private let lbLog = Logger(subsystem: "com.vijaygoyal.theshadyspade", category: "Leaderboard")

// MARK: - Score Save Status

enum ScoreSaveStatus: Equatable {
    case idle
    case saving
    case saved
    case pending        // queued locally, will sync when online
    case failed(String)
}

// MARK: - Pending Record (persisted offline)

struct PendingGameRecord: Codable {
    var id: UUID = UUID()
    var gameMode: String
    var playerNames: [String]
    var finalScores: [Int]
    var winnerIndex: Int
    var aiSeats: [Int]
    var bid: Int
    var bidMade: Bool
    var bidderIndex: Int
    var partner1Index: Int
    var partner2Index: Int
    var defensePointsCaught: Int
    var roundCount: Int
    var recordedAt: Date = Date()

    // Used by enqueue() to skip exact duplicate submissions (e.g. onChange retry
    // race). Not stored in JSON — computed from stable game-identifying fields.
    var deduplicationKey: String {
        "\(gameMode)|\(playerNames.joined(separator: ","))|\(roundCount)|\(bid)|\(winnerIndex)"
    }
}

// MARK: - Other models

struct GameLogEntry: Identifiable {
    var id: String
    var date: Date
    var gameMode: String
    var bid: Int
    var bidMade: Bool
    var bidderName: String
    var bidderScore: Int
    var partner1Name: String
    var partner1Score: Int
    var partner2Name: String
    var partner2Score: Int
    var defenseNames: [String]
    var defensePointsCaught: Int
}

struct PlayerStat: Identifiable {
    var id: String { name }
    var name: String
    var wins: Int
    var gamesPlayed: Int
    var totalPoints: Int
    var totalBids: Int
    var bidsMade: Int
    var lastPlayed: Date
    var lastGameMode: String

    var avgPoints: Int {
        gamesPlayed > 0 ? totalPoints / gamesPlayed : 0
    }
    var bidSuccessRate: Double {
        totalBids > 0
            ? Double(bidsMade) / Double(totalBids) * 100
            : 0
    }
    var bidSuccessRateString: String {
        totalBids > 0
            ? String(format: "%.0f%%", bidSuccessRate)
            : "—"
    }
    var bidRateColor: Color {
        if totalBids == 0 { return .secondary }
        if bidSuccessRate >= 70 { return Color(red: 0.29, green: 0.87, blue: 0.50) }
        if bidSuccessRate >= 50 { return .masterGold }
        return .defenseRose
    }
}

// MARK: - Send Result

private enum SendResult {
    case success
    /// Server rejected the payload (4xx). Retrying will not help — discard the record.
    case serverRejected(String)
    /// Network error or 5xx. Safe to enqueue and retry later.
    case networkFailure
}

// MARK: - LeaderboardService

@MainActor
@Observable
final class LeaderboardService {
    static let shared = LeaderboardService()

    var playerStats: [PlayerStat] = []
    var gameLog: [GameLogEntry] = []
    var isLoading = false
    var errorMessage: String? = nil
    var scoreSaveStatus: ScoreSaveStatus = .idle
    var hasPendingScore: Bool { !loadPendingRecords().isEmpty }

    private let db = Firestore.firestore()
    private var statsListener: ListenerRegistration?
    private var logListener: ListenerRegistration?
    private var networkMonitor: NWPathMonitor?

    private let pendingKey = "leaderboard_pending_records_v1"
    private let cloudRunURL = URL(string: "https://us-central1-shadyspade-d6b84.cloudfunctions.net/recordGame")!

    private init() {}

    // MARK: - Listeners

    func startListening() {
        // LB6 fix: do NOT gate on statsListener != nil. If a prior listener silently
        // died (Firestore can drop a listener without calling remove()), this guard
        // would prevent re-subscription. Instead, tear down any stale registration
        // before attaching fresh listeners.
        stopListening()
        isLoading = true
        attachFirestoreListeners()
        startNetworkMonitor()
    }

    private func attachFirestoreListeners() {
        statsListener = db.collection("player_stats")
            .order(by: "wins", descending: true)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }
                self.isLoading = false
                if let err {
                    lbLog.error("stats listener error — reattaching in 3s: \(err.localizedDescription)")
                    self.reattachListeners()
                    return
                }
                self.playerStats = snap?.documents.compactMap {
                    doc -> PlayerStat? in
                    let d = doc.data()
                    guard let name = d["name"] as? String,
                          !name.isEmpty else { return nil }
                    return PlayerStat(
                        name: name,
                        wins: d["wins"] as? Int ?? 0,
                        gamesPlayed: d["gamesPlayed"] as? Int ?? 0,
                        totalPoints: d["totalPoints"] as? Int ?? 0,
                        totalBids: d["totalBids"] as? Int ?? 0,
                        bidsMade: d["bidsMade"] as? Int ?? 0,
                        lastPlayed: (d["lastPlayed"] as? Timestamp)?
                            .dateValue() ?? Date(),
                        lastGameMode: d["lastGameMode"] as? String
                            ?? "Solo"
                    )
                } ?? []
            }

        logListener = db.collection("game_log")
            .order(by: "date", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }
                if let err {
                    lbLog.error("log listener error — reattaching in 3s: \(err.localizedDescription)")
                    self.reattachListeners()
                    return
                }
                self.gameLog = snap?.documents.compactMap {
                    doc -> GameLogEntry? in
                    let d = doc.data()
                    let defenseRaw = d["defense"]
                        as? [[String: Any]] ?? []
                    let defenseNames = defenseRaw.compactMap {
                        $0["name"] as? String
                    }.filter { !$0.isEmpty }
                    return GameLogEntry(
                        id: doc.documentID,
                        date: (d["date"] as? Timestamp)?
                            .dateValue() ?? Date(),
                        gameMode: d["gameMode"] as? String
                            ?? "Solo",
                        bid: d["bid"] as? Int ?? 0,
                        bidMade: d["bidMade"] as? Bool ?? false,
                        bidderName: d["bidderName"] as? String
                            ?? "",
                        bidderScore: d["bidderScore"] as? Int ?? 0,
                        partner1Name: d["partner1Name"] as? String
                            ?? "",
                        partner1Score: d["partner1Score"] as? Int
                            ?? 0,
                        partner2Name: d["partner2Name"] as? String
                            ?? "",
                        partner2Score: d["partner2Score"] as? Int
                            ?? 0,
                        defenseNames: defenseNames,
                        defensePointsCaught:
                            d["defensePointsCaught"] as? Int ?? 0
                    )
                } ?? []
            }
    }

    /// Tears down existing listeners and re-subscribes after a 3-second delay.
    /// Called automatically when a listener reports an error (e.g. silent death).
    private func reattachListeners() {
        stopListening()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self else { return }
            lbLog.info("reattachListeners: re-subscribing Firestore listeners")
            self.attachFirestoreListeners()
        }
    }

    func stopListening() {
        statsListener?.remove()
        statsListener = nil
        logListener?.remove()
        logListener = nil
    }

    // MARK: - Network Monitor

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                await self?.flushPendingRecords()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.vijaygoyal.theshadyspade.network"))
        networkMonitor = monitor
        // Flush any queued records that survived from a previous session
        Task { await flushPendingRecords() }
    }

    // MARK: - Record Game

    func recordGame(
        gameMode: String,
        playerNames: [String],
        finalScores: [Int],
        winnerIndex: Int,
        aiSeats: [Int] = [],
        rounds: [HistoryRound]
    ) async {
        lbLog.info("recordGame called mode=\(gameMode) names=\(playerNames.count) rounds=\(rounds.count) winner=\(winnerIndex)")
        guard playerNames.count == 6,
              let lastRound = rounds.last else {
            lbLog.error("recordGame guard failed — names=\(playerNames.count) rounds=\(rounds.count)")
            return
        }

        let totalDefensePts = rounds.reduce(0) { $0 + $1.defensePointsCaught }

        let pending = PendingGameRecord(
            gameMode: gameMode,
            playerNames: playerNames,
            finalScores: finalScores.map { Int($0) },
            winnerIndex: Int(winnerIndex),
            aiSeats: aiSeats.map { Int($0) },
            bid: Int(lastRound.bidAmount),
            bidMade: !lastRound.isSet,
            bidderIndex: Int(lastRound.bidderIndex),
            partner1Index: Int(lastRound.partner1Index),
            partner2Index: Int(lastRound.partner2Index),
            defensePointsCaught: Int(totalDefensePts),
            roundCount: Int(rounds.count)
        )

        // Enqueue before attempting the send so the record survives if the
        // process is killed mid-flight. Removed from the queue on success or
        // permanent server rejection; left in queue on network failure for
        // automatic offline retry.
        enqueue(pending)
        scoreSaveStatus = .saving

        switch await sendRecord(pending) {
        case .success:
            removeFromQueue(id: pending.id)
            scoreSaveStatus = .saved
            errorMessage = nil
        case .serverRejected(let reason):
            // Server will keep rejecting this payload — remove from queue, surface the error.
            removeFromQueue(id: pending.id)
            scoreSaveStatus = .failed("Score not saved: \(reason)")
            errorMessage = "Score not saved: \(reason)"
            lbLog.error("record permanently rejected by server: \(reason)")
        case .networkFailure:
            // Already in queue — will sync automatically when connectivity returns.
            scoreSaveStatus = .pending
            errorMessage = nil  // not an error — it will sync
            lbLog.info("record enqueued for offline retry — \(pending.id)")
        }
    }

    // MARK: - HTTP send (shared by live + flush paths)

    private func sendRecord(_ record: PendingGameRecord) async -> SendResult {
        let payload: [String: Any] = [
            "gameMode":            record.gameMode,
            "playerNames":         record.playerNames,
            "finalScores":         record.finalScores,
            "aiSeats":             record.aiSeats,
            "winnerIndex":         record.winnerIndex,
            "bid":                 record.bid,
            "bidMade":             record.bidMade,
            "bidderIndex":         record.bidderIndex,
            "partner1Index":       record.partner1Index,
            "partner2Index":       record.partner2Index,
            "defensePointsCaught": record.defensePointsCaught,
            "roundCount":          record.roundCount
        ]

        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            do {
                var request = URLRequest(url: cloudRunURL)
                request.httpMethod = "POST"
                request.timeoutInterval = 10
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["data": payload])

                guard let user = Auth.auth().currentUser else {
                    lbLog.error("no current user (attempt \(attempt))")
                    if attempt < maxAttempts {
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                        continue
                    }
                    return .networkFailure
                }

                let token = try await user.getIDToken()
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let body   = String(data: data, encoding: .utf8) ?? "unknown"

                if status == 200 {
                    lbLog.info("record sent ✓ attempt=\(attempt)")
                    return .success
                }

                lbLog.error("HTTP \(status) attempt=\(attempt): \(body)")

                if status >= 400 && status < 500 {
                    // Server explicitly rejected the payload — retrying will not help.
                    // Surface the error to the caller instead of masking it.
                    let reason = "HTTP \(status)"
                    lbLog.error("server rejected record (terminal): \(body)")
                    return .serverRejected(reason)
                }
                // 5xx or unexpected — fall through to retry
            } catch {
                lbLog.error("request failed attempt=\(attempt): \(error.localizedDescription)")
            }

            if attempt < maxAttempts {
                let delay = UInt64(attempt) * 2_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        return .networkFailure
    }

    // MARK: - Pending Queue

    private func enqueue(_ record: PendingGameRecord) {
        var records = loadPendingRecords()
        // #10: skip exact duplicates (e.g. onChange retry race before gameHistorySaved is set)
        guard !records.contains(where: { $0.deduplicationKey == record.deduplicationKey }) else {
            lbLog.warning("enqueue: duplicate skipped id=\(record.id)")
            return
        }
        records.append(record)
        // #9: cap queue to prevent unbounded UserDefaults growth; evict oldest
        if records.count > 100 { records = Array(records.suffix(100)) }
        savePendingRecords(records)
    }

    private func flushPendingRecords() async {
        // Ensure we have a valid Firebase user before sending. If auth failed at
        // launch (fire-and-forget with no retry), records would receive 401 here and
        // be permanently discarded from the queue — so sign in first.
        await ensureAuthenticated()

        let records = loadPendingRecords()
        guard !records.isEmpty else { return }
        lbLog.info("flushing \(records.count) pending record(s)")

        var allFlushed = true
        for record in records {
            switch await sendRecord(record) {
            case .success:
                lbLog.info("pending record flushed ✓ id=\(record.id)")
                removeFromQueue(id: record.id)
            case .serverRejected(let reason):
                // Server will permanently reject this — discard it rather than
                // retrying forever. Log for diagnostics.
                lbLog.error("pending record discarded (server rejected): \(reason) id=\(record.id)")
                removeFromQueue(id: record.id)
            case .networkFailure:
                allFlushed = false
            }
        }

        if allFlushed, case .pending = scoreSaveStatus {
            scoreSaveStatus = .saved
        }
    }

    /// Removes a single record from the persistent queue by ID.
    /// Reads the live queue immediately before writing so that records enqueued
    /// during an in-flight flush are never overwritten (TOCTOU fix).
    private func removeFromQueue(id: UUID) {
        var records = loadPendingRecords()
        records.removeAll { $0.id == id }
        savePendingRecords(records)
    }

    /// Ensures a Firebase anonymous user exists before attempting an HTTP send.
    /// Called by flushPendingRecords so that records queued during an offline
    /// session are not permanently discarded with a 401 on first flush.
    private func ensureAuthenticated() async {
        guard Auth.auth().currentUser == nil else { return }
        do {
            try await Auth.auth().signInAnonymously()
            lbLog.info("ensureAuthenticated: signed in anonymously for pending flush")
        } catch {
            lbLog.error("ensureAuthenticated: sign-in failed: \(error.localizedDescription)")
        }
    }

    private func loadPendingRecords() -> [PendingGameRecord] {
        guard let data = UserDefaults.standard.data(forKey: pendingKey),
              let records = try? JSONDecoder().decode([PendingGameRecord].self, from: data)
        else { return [] }
        return records
    }

    private func savePendingRecords(_ records: [PendingGameRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: pendingKey)
        }
    }
}
