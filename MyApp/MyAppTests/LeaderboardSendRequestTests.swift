import XCTest
@testable import MyApp

final class LeaderboardSendRequestTests: XCTestCase {
    func test_payloadIncludesCloudFunctionFields() throws {
        let record = PendingGameRecord(
            sessionCode: "ABC123R4",
            gameMode: "Bluetooth",
            playerNames: ["A", "B", "C", "D", "E", "F"],
            finalScores: [10, 20, 30, 40, 50, 60],
            winnerIndex: 5,
            aiSeats: [3, 4],
            bid: 165,
            bidMade: false,
            bidderIndex: 1,
            partner1Index: 2,
            partner2Index: 5,
            defensePointsCaught: 120,
            roundCount: 4,
            recordedAt: Date(timeIntervalSince1970: 0)
        )

        let payload = LeaderboardSendRequest.payload(for: record)

        XCTAssertEqual(payload["sessionCode"] as? String, "ABC123R4")
        XCTAssertEqual(payload["gameMode"] as? String, "Bluetooth")
        XCTAssertEqual(payload["playerNames"] as? [String], ["A", "B", "C", "D", "E", "F"])
        XCTAssertEqual(payload["finalScores"] as? [Int], [10, 20, 30, 40, 50, 60])
        XCTAssertEqual(payload["aiSeats"] as? [Int], [3, 4])
        XCTAssertEqual(payload["winnerIndex"] as? Int, 5)
        XCTAssertEqual(payload["bid"] as? Int, 165)
        XCTAssertEqual(payload["bidMade"] as? Bool, false)
        XCTAssertEqual(payload["bidderIndex"] as? Int, 1)
        XCTAssertEqual(payload["partner1Index"] as? Int, 2)
        XCTAssertEqual(payload["partner2Index"] as? Int, 5)
        XCTAssertEqual(payload["defensePointsCaught"] as? Int, 120)
        XCTAssertEqual(payload["roundCount"] as? Int, 4)

        let wrapped = try XCTUnwrap(LeaderboardSendRequest.wrappedPayload(for: record)["data"] as? [String: Any])
        XCTAssertEqual(wrapped["sessionCode"] as? String, "ABC123R4")
    }

    func test_payloadUsesEmptyStringForMissingSessionCode() {
        let payload = LeaderboardSendRequest.payload(for: makeRecord(sessionCode: nil))
        XCTAssertEqual(payload["sessionCode"] as? String, "")
    }

    func test_statusClassification() {
        XCTAssertEqual(LeaderboardSendRequest.result(forHTTPStatus: 200), .success)
        XCTAssertEqual(LeaderboardSendRequest.result(forHTTPStatus: 400), .serverRejected("HTTP 400"))
        XCTAssertEqual(LeaderboardSendRequest.result(forHTTPStatus: 401), .serverRejected("HTTP 401"))
        XCTAssertEqual(LeaderboardSendRequest.result(forHTTPStatus: 499), .serverRejected("HTTP 499"))
        XCTAssertEqual(LeaderboardSendRequest.result(forHTTPStatus: 500), .networkFailure)
        XCTAssertEqual(LeaderboardSendRequest.result(forHTTPStatus: 503), .networkFailure)
        XCTAssertEqual(LeaderboardSendRequest.result(forHTTPStatus: 0), .networkFailure)
        XCTAssertEqual(LeaderboardSendRequest.result(forHTTPStatus: 302), .networkFailure)
    }

    private func makeRecord(sessionCode: String?) -> PendingGameRecord {
        PendingGameRecord(
            sessionCode: sessionCode,
            gameMode: "Solo",
            playerNames: ["A", "B", "C", "D", "E", "F"],
            finalScores: [0, 0, 0, 0, 0, 0],
            winnerIndex: 0,
            aiSeats: [],
            bid: 130,
            bidMade: true,
            bidderIndex: 0,
            partner1Index: 1,
            partner2Index: 2,
            defensePointsCaught: 90,
            roundCount: 1,
            recordedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
