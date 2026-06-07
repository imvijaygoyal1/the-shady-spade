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
    case notSaved(String)
    case handledByHost(String)
    case failed(String)
}

// MARK: - Pending Record (persisted offline)

struct PendingGameRecord: Codable {
    var id: UUID = UUID()
    var sessionCode: String?       // Round-scoped dedupe key when available.
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
        if let code = sessionCode, !code.isEmpty { return code }
        return "\(gameMode)|\(playerNames.joined(separator: ","))|\(roundCount)|\(bid)|\(winnerIndex)"
    }
}

extension PendingGameRecord {
    static func roundScopedSessionCode(_ rawCode: String, roundNumber: Int) -> String {
        let cleaned = rawCode.filter { $0.isLetter || $0.isNumber }
        guard !cleaned.isEmpty else { return "" }
        let suffix = "R\(max(1, roundNumber))"
        let prefixLength = max(1, 10 - suffix.count)
        return String(cleaned.prefix(prefixLength)) + suffix
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
    var roundCount: Int
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
        if bidSuccessRate >= 70 { return ThemeManager.shared.colours.successColor }
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
    private var pendingRecordsFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("leaderboard_pending_v1.json")
    }
    private let cloudRunURL = URL(string: "https://us-central1-shadyspade-d6b84.cloudfunctions.net/recordGame")!
    private var isFlushing = false
    private var listenerAttachTask: Task<Void, Never>?
    private var reattachTask: Task<Void, Never>?
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var inFlightRecordIDs = Set<UUID>()
    private var inFlightDeduplicationKeys = Set<String>()

    private init() {}

    func resetScoreSaveStatus() {
        scoreSaveStatus = .idle
        errorMessage = nil
    }

    func markScoreNotSaved(_ message: String) {
        scoreSaveStatus = .notSaved(message)
        errorMessage = nil
    }

    // MARK: - Listeners

    func startListening() {
        // LB6 fix: do NOT gate on statsListener != nil. If a prior listener silently
        // died (Firestore can drop a listener without calling remove()), this guard
        // would prevent re-subscription. Instead, tear down any stale registration
        // before attaching fresh listeners.
        stopListening()
        isLoading = true
        startNetworkMonitor()
        startAuthStateListener()
        scheduleAuthenticatedListenerAttach()
    }

    private func startAuthStateListener() {
        guard authStateHandle == nil else { return }
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                if user == nil {
                    self.stopFirestoreListeners()
                    return
                }
                self.errorMessage = nil
                self.scheduleAuthenticatedListenerAttach()
                await self.flushPendingRecords()
            }
        }
    }

    private func scheduleAuthenticatedListenerAttach(after delay: UInt64 = 0) {
        listenerAttachTask?.cancel()
        listenerAttachTask = Task { @MainActor [weak self] in
            if delay > 0 {
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
            }
            guard let self, !Task.isCancelled else { return }
            guard self.statsListener == nil || self.logListener == nil else {
                self.isLoading = false
                return
            }
            guard await self.ensureAuthenticated() else {
                self.isLoading = false
                self.errorMessage = "Leaderboard sign-in failed. Scores will sync when authentication recovers."
                lbLog.error("startListening: Firebase auth unavailable; leaderboard listeners not attached")
                return
            }
            guard !Task.isCancelled else { return }
            self.errorMessage = nil
            self.stopFirestoreListeners()
            self.attachFirestoreListeners()
            await self.flushPendingRecords()
        }
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
                            d["defensePointsCaught"] as? Int ?? 0,
                        roundCount: d["roundCount"] as? Int ?? 1
                    )
                } ?? []
            }
    }

    /// Tears down existing listeners and re-subscribes after a 3-second delay.
    /// Called automatically when a listener reports an error (e.g. silent death).
    private func reattachListeners() {
        stopFirestoreListeners()
        reattachTask?.cancel()
        reattachTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            guard let self, !Task.isCancelled else { return }
            lbLog.info("reattachListeners: re-subscribing Firestore listeners after auth check")
            self.scheduleAuthenticatedListenerAttach()
        }
    }

    func stopListening() {
        listenerAttachTask?.cancel()
        listenerAttachTask = nil
        reattachTask?.cancel()
        reattachTask = nil
        stopFirestoreListeners()
        networkMonitor?.cancel()
        networkMonitor = nil
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
            self.authStateHandle = nil
        }
    }

    private func stopFirestoreListeners() {
        statsListener?.remove()
        statsListener = nil
        logListener?.remove()
        logListener = nil
    }

    // MARK: - Network Monitor

    private func startNetworkMonitor() {
        networkMonitor?.cancel()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                if self?.statsListener == nil || self?.logListener == nil {
                    self?.scheduleAuthenticatedListenerAttach()
                }
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
        rounds: [HistoryRound],
        sessionCode: String = ""
    ) async {
        lbLog.info("recordGame called mode=\(gameMode) names=\(playerNames.count) rounds=\(rounds.count) winner=\(winnerIndex)")
        guard playerNames.count == 6 else {
            lbLog.error("recordGame aborted — playerNames.count=\(playerNames.count) ≠ 6")
            return
        }
        guard finalScores.count == 6 else {
            lbLog.error("recordGame aborted — finalScores.count=\(finalScores.count) ≠ 6")
            return
        }
        guard rounds.allSatisfy({ $0.runningScores.count == 6 }) else {
            lbLog.error("recordGame aborted — a HistoryRound has runningScores.count ≠ 6")
            return
        }
        guard let lastRound = rounds.last else {
            lbLog.error("recordGame aborted — rounds is empty")
            return
        }
        // HIGH-01: filter out-of-range aiSeats rather than abort — the game record
        // is valid; bad indices are a caller bug and the server already filters them.
        let validAISeats = aiSeats.filter { (0..<6).contains($0) }
        if validAISeats.count != aiSeats.count {
            lbLog.warning("recordGame: dropped \(aiSeats.count - validAISeats.count) invalid aiSeat index(es)")
        }

        let completedRoundNumber = max(1, lastRound.roundNumber)
        let scopedSessionCode = PendingGameRecord.roundScopedSessionCode(
            sessionCode,
            roundNumber: completedRoundNumber
        )

        let sanitizedNames = playerNames.enumerated().map { (i, name) in
            ProfanityFilter.isProfane(name) ? "Guest \(i + 1)" : name
        }

        let pending = PendingGameRecord(
            sessionCode: scopedSessionCode.isEmpty ? nil : scopedSessionCode,
            gameMode: gameMode,
            playerNames: sanitizedNames,
            finalScores: finalScores.map { Int($0) },
            winnerIndex: Int(winnerIndex),
            aiSeats: validAISeats.map { Int($0) },
            bid: Int(lastRound.bidAmount),
            bidMade: !lastRound.isSet,
            bidderIndex: Int(lastRound.bidderIndex),
            partner1Index: Int(lastRound.partner1Index),
            partner2Index: Int(lastRound.partner2Index),
            defensePointsCaught: Int(lastRound.defensePointsCaught),
            roundCount: completedRoundNumber
        )

        scoreSaveStatus = .idle
        // Enqueue before attempting the send so the record survives if the
        // process is killed mid-flight. Removed from the queue on success or
        // permanent server rejection; left in queue on network failure for
        // automatic offline retry.
        enqueue(pending)
        scoreSaveStatus = .saving

        guard claimSend(pending) else {
            scoreSaveStatus = .pending
            errorMessage = nil
            lbLog.info("recordGame: send already in progress; record left in pending queue id=\(pending.id)")
            return
        }
        defer { releaseSend(pending) }

        guard await ensureAuthenticated() else {
            scoreSaveStatus = .pending
            errorMessage = nil
            lbLog.error("recordGame: Firebase auth unavailable; record left in pending queue")
            return
        }

        switch await sendRecord(pending) {
        case .success:
            removeFromQueue(matching: pending)
            scoreSaveStatus = .saved
            errorMessage = nil
        case .serverRejected(let reason):
            // Server will keep rejecting this payload — remove from queue, surface the error.
            removeFromQueue(matching: pending)
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
            "sessionCode":         record.sessionCode ?? "",
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
                do { try await Task.sleep(nanoseconds: delay) } catch { return .networkFailure }
            }
        }
        return .networkFailure
    }

    // MARK: - Pending Queue

    private func enqueue(_ record: PendingGameRecord) {
        var records = loadPendingRecords()
        if let existingIdx = records.firstIndex(where: { $0.deduplicationKey == record.deduplicationKey }) {
            // BT-GAP-14: Replace the existing record with the newer one so the caller's
            // UUID (pending.id) matches what is stored. If we kept the old UUID,
            // removeFromQueue(matching:) after a successful send can clear both the
            // sent record and any same-game replacement created during an in-flight flush.
            lbLog.info("enqueue: replacing existing record id=\(records[existingIdx].id) → \(record.id)")
            records[existingIdx] = record
            savePendingRecords(records)
            return
        }
        records.append(record)
        // #9: cap queue to prevent unbounded UserDefaults growth; evict oldest
        if records.count > 100 { records = Array(records.suffix(100)) }
        savePendingRecords(records)
    }

    /// Persists a game record to the offline queue WITHOUT triggering an HTTP send.
    /// Call from synchronous game-state handlers (e.g. applyGameState at .gameOver) so
    /// the record survives a process suspension before the normal async recordGame() path
    /// runs. When recordGame() is subsequently called, enqueue() replaces this record
    /// (same deduplicationKey) and removeFromQueue(matching:) clears the saved game.
    func preEnqueue(
        sessionCode: String,
        gameMode: String,
        playerNames: [String],
        finalScores: [Int],
        winnerIndex: Int,
        aiSeats: [Int] = [],
        rounds: [HistoryRound]
    ) {
        guard playerNames.count == 6, finalScores.count == 6 else { return }
        guard rounds.allSatisfy({ $0.runningScores.count == 6 }), let lastRound = rounds.last else { return }
        let validAISeats = aiSeats.filter { (0..<6).contains($0) }
        let completedRoundNumber = max(1, lastRound.roundNumber)
        let scopedSessionCode = PendingGameRecord.roundScopedSessionCode(
            sessionCode,
            roundNumber: completedRoundNumber
        )
        let sanitizedNames = playerNames.enumerated().map { (i, name) in
            ProfanityFilter.isProfane(name) ? "Guest \(i + 1)" : name
        }
        let pending = PendingGameRecord(
            sessionCode: scopedSessionCode.isEmpty ? nil : scopedSessionCode,
            gameMode: gameMode,
            playerNames: sanitizedNames,
            finalScores: finalScores.map { Int($0) },
            winnerIndex: Int(winnerIndex),
            aiSeats: validAISeats.map { Int($0) },
            bid: Int(lastRound.bidAmount),
            bidMade: !lastRound.isSet,
            bidderIndex: Int(lastRound.bidderIndex),
            partner1Index: Int(lastRound.partner1Index),
            partner2Index: Int(lastRound.partner2Index),
            defensePointsCaught: Int(lastRound.defensePointsCaught),
            roundCount: completedRoundNumber
        )
        enqueue(pending)
        lbLog.info("preEnqueue: persisted to disk — \(gameMode) sessionCode=\(scopedSessionCode.isEmpty ? "none" : scopedSessionCode) round=\(completedRoundNumber)")
    }

    private func flushPendingRecords() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        let records = loadPendingRecords()
        guard !records.isEmpty else { return }
        let sendableRecords = records.filter { !isSendInFlight($0) }
        guard !sendableRecords.isEmpty else {
            lbLog.debug("flushPendingRecords: pending records already in-flight; waiting for active send")
            return
        }

        guard await ensureAuthenticated() else { return }
        lbLog.info("flushing \(sendableRecords.count) pending record(s)")

        var attemptedAny = false
        var allFlushed = true
        for record in sendableRecords {
            guard claimSend(record) else {
                lbLog.debug("flushPendingRecords: skipping in-flight record id=\(record.id)")
                continue
            }
            attemptedAny = true

            do {
                defer { releaseSend(record) }
                switch await sendRecord(record) {
                case .success:
                    lbLog.info("pending record flushed ✓ id=\(record.id)")
                    removeFromQueue(matching: record)
                case .serverRejected(let reason):
                    // Server will permanently reject this — discard it rather than
                    // retrying forever. Log for diagnostics.
                    lbLog.error("pending record discarded (server rejected): \(reason) id=\(record.id)")
                    removeFromQueue(matching: record)
                case .networkFailure:
                    allFlushed = false
                }
            }
        }

        if attemptedAny, allFlushed, case .pending = scoreSaveStatus {
            scoreSaveStatus = .saved
        }
    }

    private func claimSend(_ record: PendingGameRecord) -> Bool {
        let key = record.deduplicationKey
        guard !isSendInFlight(record) else { return false }
        inFlightRecordIDs.insert(record.id)
        inFlightDeduplicationKeys.insert(key)
        return true
    }

    private func isSendInFlight(_ record: PendingGameRecord) -> Bool {
        inFlightRecordIDs.contains(record.id)
            || inFlightDeduplicationKeys.contains(record.deduplicationKey)
    }

    private func releaseSend(_ record: PendingGameRecord) {
        inFlightRecordIDs.remove(record.id)
        inFlightDeduplicationKeys.remove(record.deduplicationKey)
    }

    /// Removes a sent record from the persistent queue by ID and same-game
    /// deduplication key.
    /// Reads the live queue immediately before writing so that records enqueued
    /// during an in-flight flush are never overwritten (TOCTOU fix).
    private func removeFromQueue(matching record: PendingGameRecord) {
        let deduplicationKey = record.deduplicationKey
        var records = loadPendingRecords()
        records.removeAll {
            $0.id == record.id || $0.deduplicationKey == deduplicationKey
        }
        savePendingRecords(records)
    }

    /// Ensures a Firebase anonymous user exists before attempting an HTTP send.
    /// Called by flushPendingRecords so that records queued during an offline
    /// session are not permanently discarded with a 401 on first flush.
    @discardableResult
    private func ensureAuthenticated() async -> Bool {
        guard Auth.auth().currentUser == nil else { return true }
        do {
            try await Auth.auth().signInAnonymously()
            lbLog.info("ensureAuthenticated: signed in anonymously for pending flush")
            return true
        } catch {
            lbLog.error("ensureAuthenticated: sign-in failed: \(error.localizedDescription)")
            return false
        }
    }

    private func loadPendingRecords() -> [PendingGameRecord] {
        let url = pendingRecordsFileURL
        if let data = try? Data(contentsOf: url),
           let records = try? JSONDecoder().decode([PendingGameRecord].self, from: data) {
            return records
        }
        // Migrate from UserDefaults (legacy storage) on first load.
        if let data = UserDefaults.standard.data(forKey: pendingKey),
           let records = try? JSONDecoder().decode([PendingGameRecord].self, from: data) {
            savePendingRecords(records)
            UserDefaults.standard.removeObject(forKey: pendingKey)
            return records
        }
        return []
    }

    private func savePendingRecords(_ records: [PendingGameRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        let url = pendingRecordsFileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch {
            lbLog.error("LeaderboardService: failed to save pending records: \(error.localizedDescription)")
        }
    }
}
