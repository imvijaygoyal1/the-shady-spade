import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftUI

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
        guard playerNames.count == 6,
              let lastRound = rounds.last else { return }

        let totalDefensePts = rounds.reduce(0) {
            $0 + $1.defensePointsCaught
        }

        let payload: [String: Any] = [
            "gameMode":            gameMode,
            "playerNames":         playerNames,
            "winnerIndex":         winnerIndex,
            "bid":                 lastRound.bidAmount,
            "bidMade":             !lastRound.isSet,
            "bidderIndex":         lastRound.bidderIndex,
            "partner1Index":       lastRound.partner1Index,
            "partner2Index":       lastRound.partner2Index,
            "defensePointsCaught": totalDefensePts,
            "roundCount":          rounds.count
        ]

        print("LeaderboardService: recording game mode=\(gameMode)" +
              " rounds=\(rounds.count) names=\(playerNames)")

        // Call 2nd gen Cloud Function via explicit Cloud Run URL,
        // bypassing FirebaseFunctions SDK name resolution which
        // fails for 2nd gen callable endpoints.
        let cloudRunURL = URL(
            string: "https://recordgame-ttt4s46pta-uc.a.run.app")!

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
                    print("LeaderboardService: auth token attached")
                } catch {
                    print("LeaderboardService: getIDToken failed — \(error)")
                    errorMessage = "Score not saved: auth error."
                    return
                }
            } else {
                print("LeaderboardService: no current user — skipping")
                errorMessage = "Score not saved: not signed in."
                return
            }

            let (data, response) = try await
                URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse,
               http.statusCode == 200 {
                print("LeaderboardService: game recorded ✓")
                errorMessage = nil
            } else {
                let body = String(data: data,
                    encoding: .utf8) ?? "unknown"
                let status = (response as? HTTPURLResponse)?
                    .statusCode ?? 0
                print("LeaderboardService: HTTP \(status) — \(body)")
                errorMessage = "Score not saved (HTTP \(status))."
            }
        } catch {
            print("LeaderboardService: request failed — \(error)")
            errorMessage = "Score not saved: \(error.localizedDescription)"
        }
    }
}
