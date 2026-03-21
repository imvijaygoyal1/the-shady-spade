import Foundation
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

        let bidAmount   = lastRound.bidAmount
        let bidderIndex = lastRound.bidderIndex
        let p1Index     = lastRound.partner1Index
        let p2Index     = lastRound.partner2Index
        let bidMade     = !lastRound.isSet
        let offenseSet  = Set([bidderIndex, p1Index, p2Index])
        let defenseArr  = (0..<6)
            .filter { !offenseSet.contains($0) }
            .map { i -> [String: Any] in ["name": playerNames[i]] }
        let totalDefense = rounds.reduce(0) {
            $0 + $1.defensePointsCaught
        }

        let batch = db.batch()

        // game_log entry
        let logRef = db.collection("game_log").document()
        let logData: [String: Any] = [
            "date":                FieldValue.serverTimestamp(),
            "gameMode":            gameMode,
            "bid":                 bidAmount,
            "bidMade":             bidMade,
            "bidderName":          playerNames[bidderIndex],
            "bidderScore":         finalScores[bidderIndex],
            "partner1Name":        playerNames[p1Index],
            "partner1Score":       finalScores[p1Index],
            "partner2Name":        playerNames[p2Index],
            "partner2Score":       finalScores[p2Index],
            "defense":             defenseArr,
            "defensePointsCaught": totalDefense
        ]
        batch.setData(logData, forDocument: logRef)

        // player_stats — one doc per player
        for i in 0..<6 {
            let name = playerNames[i]
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let score = max(0, finalScores[i])
            var stats: [String: Any] = [
                "name":         name,
                "wins":         FieldValue.increment(
                    i == winnerIndex ? Int64(1) : Int64(0)),
                "gamesPlayed":  FieldValue.increment(Int64(1)),
                "totalPoints":  FieldValue.increment(Int64(score)),
                "lastPlayed":   FieldValue.serverTimestamp(),
                "lastGameMode": gameMode
            ]
            if i == bidderIndex {
                stats["totalBids"] = FieldValue.increment(Int64(1))
                stats["bidsMade"]  = FieldValue.increment(
                    bidMade ? Int64(1) : Int64(0))
            }
            let statsRef = db.collection("player_stats").document(name)
            batch.setData(stats, forDocument: statsRef, merge: true)
        }

        do {
            try await batch.commit()
            print("LeaderboardService: game recorded")
        } catch {
            print("LeaderboardService: write failed — \(error)")
        }
    }
}
