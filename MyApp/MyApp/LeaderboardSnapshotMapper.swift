import Foundation
import FirebaseFirestore

enum LeaderboardSnapshotMapper {
    static func playerStat(
        from data: [String: Any],
        fallbackDate: Date = Date()
    ) -> PlayerStat? {
        guard let name = data["name"] as? String, !name.isEmpty else {
            return nil
        }

        return PlayerStat(
            name: name,
            wins: data["wins"] as? Int ?? 0,
            gamesPlayed: data["gamesPlayed"] as? Int ?? 0,
            totalPoints: data["totalPoints"] as? Int ?? 0,
            totalBids: data["totalBids"] as? Int ?? 0,
            bidsMade: data["bidsMade"] as? Int ?? 0,
            lastPlayed: dateValue(data["lastPlayed"], fallback: fallbackDate),
            lastGameMode: data["lastGameMode"] as? String ?? "Solo"
        )
    }

    static func gameLogEntry(
        documentID: String,
        data: [String: Any],
        fallbackDate: Date = Date()
    ) -> GameLogEntry {
        let defenseRaw = data["defense"] as? [[String: Any]] ?? []
        let defenseNames = defenseRaw.compactMap {
            $0["name"] as? String
        }.filter { !$0.isEmpty }

        return GameLogEntry(
            id: documentID,
            date: dateValue(data["date"], fallback: fallbackDate),
            gameMode: data["gameMode"] as? String ?? "Solo",
            bid: data["bid"] as? Int ?? 0,
            bidMade: data["bidMade"] as? Bool ?? false,
            bidderName: data["bidderName"] as? String ?? "",
            bidderScore: data["bidderScore"] as? Int ?? 0,
            partner1Name: data["partner1Name"] as? String ?? "",
            partner1Score: data["partner1Score"] as? Int ?? 0,
            partner2Name: data["partner2Name"] as? String ?? "",
            partner2Score: data["partner2Score"] as? Int ?? 0,
            defenseNames: defenseNames,
            defensePointsCaught: data["defensePointsCaught"] as? Int ?? 0,
            roundCount: data["roundCount"] as? Int ?? 1
        )
    }

    private static func dateValue(_ value: Any?, fallback: Date) -> Date {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }
        if let date = value as? Date {
            return date
        }
        return fallback
    }
}
