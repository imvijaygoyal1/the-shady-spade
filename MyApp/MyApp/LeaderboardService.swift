import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftUI
import OSLog

private let lbLog = Logger(subsystem: "com.vijaygoyal.theshadyspade", category: "Leaderboard")

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

@MainActor
@Observable
final class LeaderboardService {
    static let shared = LeaderboardService()

    var playerStats: [PlayerStat] = []
    var gameLog: [GameLogEntry] = []
    var isLoading = false
    var errorMessage: String? = nil

    private let db = Firestore.firestore()
    private var statsListener: ListenerRegistration?
    private var logListener: ListenerRegistration?

    private init() {}

    func startListening() {
        guard statsListener == nil else { return }
        isLoading = true
        attachFirestoreListeners()
    }

    private func attachFirestoreListeners() {
        statsListener = db.collection("player_stats")
            .order(by: "wins", descending: true)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }
                self.isLoading = false
                if let err {
                    self.errorMessage = err.localizedDescription
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
                    self.errorMessage = err.localizedDescription
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

    func stopListening() {
        statsListener?.remove()
        statsListener = nil
        logListener?.remove()
        logListener = nil
    }

    func recordGame(
        gameMode: String,
        playerNames: [String],
        finalScores: [Int],
        winnerIndex: Int,
        rounds: [HistoryRound]
    ) async {
        lbLog.info("recordGame called mode=\(gameMode) names=\(playerNames.count) rounds=\(rounds.count) winner=\(winnerIndex)")
        guard playerNames.count == 6,
              let lastRound = rounds.last else {
            lbLog.error("recordGame guard failed — names=\(playerNames.count) rounds=\(rounds.count)")
            return
        }

        let totalDefensePts = rounds.reduce(0) {
            $0 + $1.defensePointsCaught
        }

        // Explicitly cast all numeric values to Int to avoid SwiftData
        // model proxy types that JSONSerialization can't handle correctly.
        let payload: [String: Any] = [
            "gameMode":            gameMode,
            "playerNames":         playerNames,
            "winnerIndex":         Int(winnerIndex),
            "bid":                 Int(lastRound.bidAmount),
            "bidMade":             !lastRound.isSet,
            "bidderIndex":         Int(lastRound.bidderIndex),
            "partner1Index":       Int(lastRound.partner1Index),
            "partner2Index":       Int(lastRound.partner2Index),
            "defensePointsCaught": Int(totalDefensePts),
            "roundCount":          Int(rounds.count)
        ]

        lbLog.info("sending HTTP request mode=\(gameMode) rounds=\(rounds.count)")

        // Call Cloud Function via Cloud Run URL (onRequest, not onCall).
        // Sends Authorization: Bearer <Firebase-ID-token> which the
        // function verifies directly via admin.auth().verifyIdToken().
        let cloudRunURL = URL(
            string: "https://us-central1-shadyspade-d6b84.cloudfunctions.net/recordGame")!

        do {
            var request = URLRequest(url: cloudRunURL)
            request.httpMethod = "POST"
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type")

            // Firebase callable format: wrap payload in {"data":...}
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["data": payload])

            // Attach Firebase ID token so Cloud Function can
            // verify request.auth
            if let user = Auth.auth().currentUser {
                do {
                    let token = try await user.getIDToken()
                    request.setValue(
                        "Bearer \(token)",
                        forHTTPHeaderField: "Authorization")
                    lbLog.info("auth token attached uid=\(user.uid)")
                } catch {
                    lbLog.error("getIDToken failed: \(error.localizedDescription)")
                    errorMessage = "Score not saved: auth error."
                    return
                }
            } else {
                lbLog.error("no current user — not signed in")
                errorMessage = "Score not saved: not signed in."
                return
            }

            let (data, response) = try await
                URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse,
               http.statusCode == 200 {
                lbLog.info("game recorded ✓")
                errorMessage = nil
            } else {
                let body = String(data: data,
                    encoding: .utf8) ?? "unknown"
                let status = (response as? HTTPURLResponse)?
                    .statusCode ?? 0
                lbLog.error("HTTP \(status): \(body)")
                errorMessage = "Score not saved (HTTP \(status))."
            }
        } catch {
            lbLog.error("request failed: \(error.localizedDescription)")
            errorMessage = "Score not saved: \(error.localizedDescription)"
        }
    }
}
