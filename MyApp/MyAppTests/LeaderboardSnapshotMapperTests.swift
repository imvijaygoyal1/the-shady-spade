import XCTest
import FirebaseFirestore
@testable import MyApp

final class LeaderboardSnapshotMapperTests: XCTestCase {
    func test_playerStatMapsValidFirestoreData() throws {
        let date = Date(timeIntervalSince1970: 1_234)
        let stat = try XCTUnwrap(
            LeaderboardSnapshotMapper.playerStat(
                from: [
                    "name": "Maya",
                    "wins": 7,
                    "gamesPlayed": 11,
                    "totalPoints": 920,
                    "totalBids": 5,
                    "bidsMade": 4,
                    "lastPlayed": date,
                    "lastGameMode": "Bluetooth"
                ],
                fallbackDate: Date(timeIntervalSince1970: 0)
            )
        )

        XCTAssertEqual(stat.name, "Maya")
        XCTAssertEqual(stat.wins, 7)
        XCTAssertEqual(stat.gamesPlayed, 11)
        XCTAssertEqual(stat.totalPoints, 920)
        XCTAssertEqual(stat.totalBids, 5)
        XCTAssertEqual(stat.bidsMade, 4)
        XCTAssertEqual(stat.lastPlayed, date)
        XCTAssertEqual(stat.lastGameMode, "Bluetooth")
    }

    func test_playerStatRejectsMissingOrEmptyName() {
        XCTAssertNil(LeaderboardSnapshotMapper.playerStat(from: [:]))
        XCTAssertNil(LeaderboardSnapshotMapper.playerStat(from: ["name": ""]))
    }

    func test_playerStatDefaultsMalformedOptionalFields() throws {
        let fallbackDate = Date(timeIntervalSince1970: 44)
        let stat = try XCTUnwrap(
            LeaderboardSnapshotMapper.playerStat(
                from: [
                    "name": "Noor",
                    "wins": "many",
                    "gamesPlayed": false,
                    "totalPoints": "high",
                    "totalBids": "two",
                    "bidsMade": "one",
                    "lastPlayed": "yesterday",
                    "lastGameMode": 42
                ],
                fallbackDate: fallbackDate
            )
        )

        XCTAssertEqual(stat.wins, 0)
        XCTAssertEqual(stat.gamesPlayed, 0)
        XCTAssertEqual(stat.totalPoints, 0)
        XCTAssertEqual(stat.totalBids, 0)
        XCTAssertEqual(stat.bidsMade, 0)
        XCTAssertEqual(stat.lastPlayed, fallbackDate)
        XCTAssertEqual(stat.lastGameMode, "Solo")
    }

    func test_gameLogEntryMapsValidFirestoreData() {
        let date = Timestamp(date: Date(timeIntervalSince1970: 2_468))

        let entry = LeaderboardSnapshotMapper.gameLogEntry(
            documentID: "GAME1",
            data: [
                "date": date,
                "gameMode": "Online",
                "bid": 180,
                "bidMade": true,
                "bidderName": "Asha",
                "bidderScore": 90,
                "partner1Name": "Ben",
                "partner1Score": 70,
                "partner2Name": "Chen",
                "partner2Score": 55,
                "defense": [
                    ["name": "Dia"],
                    ["name": ""],
                    ["name": 12],
                    ["name": "Eli"]
                ],
                "defensePointsCaught": 35,
                "roundCount": 3
            ],
            fallbackDate: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(entry.id, "GAME1")
        XCTAssertEqual(entry.date, date.dateValue())
        XCTAssertEqual(entry.gameMode, "Online")
        XCTAssertEqual(entry.bid, 180)
        XCTAssertTrue(entry.bidMade)
        XCTAssertEqual(entry.bidderName, "Asha")
        XCTAssertEqual(entry.bidderScore, 90)
        XCTAssertEqual(entry.partner1Name, "Ben")
        XCTAssertEqual(entry.partner1Score, 70)
        XCTAssertEqual(entry.partner2Name, "Chen")
        XCTAssertEqual(entry.partner2Score, 55)
        XCTAssertEqual(entry.defenseNames, ["Dia", "Eli"])
        XCTAssertEqual(entry.defensePointsCaught, 35)
        XCTAssertEqual(entry.roundCount, 3)
    }

    func test_gameLogEntryDefaultsMissingAndMalformedFields() {
        let fallbackDate = Date(timeIntervalSince1970: 99)

        let entry = LeaderboardSnapshotMapper.gameLogEntry(
            documentID: "BAD",
            data: [
                "date": "not a date",
                "gameMode": 1,
                "bid": "high",
                "bidMade": "yes",
                "bidderName": 1,
                "bidderScore": "90",
                "partner1Name": false,
                "partner1Score": "70",
                "partner2Name": 2,
                "partner2Score": "55",
                "defense": "bad",
                "defensePointsCaught": "35",
                "roundCount": "3"
            ],
            fallbackDate: fallbackDate
        )

        XCTAssertEqual(entry.id, "BAD")
        XCTAssertEqual(entry.date, fallbackDate)
        XCTAssertEqual(entry.gameMode, "Solo")
        XCTAssertEqual(entry.bid, 0)
        XCTAssertFalse(entry.bidMade)
        XCTAssertEqual(entry.bidderName, "")
        XCTAssertEqual(entry.bidderScore, 0)
        XCTAssertEqual(entry.partner1Name, "")
        XCTAssertEqual(entry.partner1Score, 0)
        XCTAssertEqual(entry.partner2Name, "")
        XCTAssertEqual(entry.partner2Score, 0)
        XCTAssertEqual(entry.defenseNames, [])
        XCTAssertEqual(entry.defensePointsCaught, 0)
        XCTAssertEqual(entry.roundCount, 1)
    }
}
