import XCTest
@testable import MyApp

final class SyncedGameStateMapperTests: XCTestCase {
    func test_sixValueParsingAcceptsIntAndInt64AndRejectsWrongCount() {
        XCTAssertEqual(
            SyncedGameStateMapper.sixInts(from: [1, Int64(2), "bad", 4, 5, 6], default: -1),
            [1, 2, -1, 4, 5, 6]
        )
        XCTAssertNil(SyncedGameStateMapper.sixInts(from: [1, 2, 3], default: 0))

        XCTAssertEqual(
            SyncedGameStateMapper.sixBools(from: [true, false, "bad", true, 1, false]),
            [true, false, false, true, false, false]
        )
        XCTAssertNil(SyncedGameStateMapper.sixBools(from: [true]))
    }

    func test_aiSeatsFiltersMalformedAndOutOfBoundsSeats() {
        XCTAssertEqual(
            SyncedGameStateMapper.aiSeats(from: [0, Int64(2), -1, 6, "3", 5]),
            [0, 2, 5]
        )
    }

    func test_bidHistoryKeepsLatestAmountInFirstAppearanceOrder() {
        let raw: [[String: Any]] = [
            ["pi": 0, "amt": 130],
            ["pi": Int64(1), "amt": Int64(135)],
            ["pi": 0, "amt": 150],
            ["pi": 9, "amt": 200],
            ["pi": "bad", "amt": 160]
        ]

        let onlineStyle = SyncedGameStateMapper.bidHistory(from: raw, boundsChecked: false)
        XCTAssertEqual(onlineStyle.map(\.playerIndex), [0, 1, 9])
        XCTAssertEqual(onlineStyle.map(\.amount), [150, 135, 200])

        let bluetoothStyle = SyncedGameStateMapper.bidHistory(from: raw, boundsChecked: true)
        XCTAssertEqual(bluetoothStyle.map(\.playerIndex), [0, 1])
        XCTAssertEqual(bluetoothStyle.map(\.amount), [150, 135])
    }

    func test_currentTrickParsesValidCardsAndBoundsChecksPlayers() {
        let trick = SyncedGameStateMapper.currentTrick(
            from: [
                ["pi": 0, "card": "A♠"],
                ["pi": Int64(5), "card": "10♦"],
                ["pi": 6, "card": "K♣"],
                ["pi": 2, "card": "2♠"],
                ["pi": 3, "card": ""],
                ["pi": "bad", "card": "Q♥"]
            ]
        )

        XCTAssertEqual(trick.map(\.playerIndex), [0, 5])
        XCTAssertEqual(trick.map(\.card.id), ["A♠", "10♦"])
        XCTAssertEqual(SyncedGameStateMapper.encodedCurrentTrick(trick).count, 2)
    }

    func test_completedRoundsDecodeEncodeAndDeduplicate() {
        let raw: [[String: Any]] = [
            [
                "roundNumber": 1,
                "dealerIndex": 0,
                "bidderIndex": 2,
                "bidAmount": 155,
                "trumpSuit": "♥",
                "callCard1": "A♣",
                "callCard2": "K♦",
                "partner1Index": 3,
                "partner2Index": 4,
                "offensePointsCaught": 160,
                "defensePointsCaught": 90,
                "runningScores": [10, 20, 30, 40, 50, 60]
            ],
            [
                "roundNumber": 1,
                "partner1Index": 1,
                "partner2Index": 2
            ],
            [
                "roundNumber": 2,
                "partner1Index": -1,
                "partner2Index": 2
            ],
            [
                "roundNumber": 3,
                "partner1Index": 1,
                "partner2Index": 2,
                "runningScores": [1, 2]
            ]
        ]

        let rounds = SyncedGameStateMapper.completedRounds(
            from: raw,
            excludingRoundNumbers: []
        )

        XCTAssertEqual(rounds.map(\.roundNumber), [1, 3])
        XCTAssertEqual(rounds[0].trumpSuit, .hearts)
        XCTAssertEqual(rounds[0].runningScores, [10, 20, 30, 40, 50, 60])
        XCTAssertEqual(rounds[1].runningScores, [0, 0, 0, 0, 0, 0])

        let encoded = SyncedGameStateMapper.encodedCompletedRounds(rounds)
        XCTAssertEqual(encoded.count, 2)
        XCTAssertEqual(encoded[0]["roundNumber"] as? Int, 1)
        XCTAssertEqual(encoded[0]["trumpSuit"] as? String, "♥")
    }

    func test_completedRoundBuilderPreservesOnlineFallbackAndBluetoothPartnerRequirement() {
        let onlineRound = SyncedGameStateMapper.completedRound(
            roundNumber: 4,
            dealerIndex: 1,
            highBidderIndex: -1,
            highBid: 130,
            trumpSuit: .spades,
            calledCard1: "A♥",
            calledCard2: "K♦",
            partner1Index: -1,
            partner2Index: -1,
            offensePoints: 80,
            defensePoints: 170,
            runningScores: [1, 2],
            requiresResolvedPartners: false
        )

        XCTAssertEqual(onlineRound?.bidderIndex, 0)
        XCTAssertEqual(onlineRound?.partner1Index, 0)
        XCTAssertEqual(onlineRound?.partner2Index, 0)
        XCTAssertEqual(onlineRound?.runningScores, [0, 0, 0, 0, 0, 0])

        let bluetoothRound = SyncedGameStateMapper.completedRound(
            roundNumber: 4,
            dealerIndex: 1,
            highBidderIndex: 2,
            highBid: 130,
            trumpSuit: .spades,
            calledCard1: "A♥",
            calledCard2: "K♦",
            partner1Index: -1,
            partner2Index: 3,
            offensePoints: 80,
            defensePoints: 170,
            runningScores: [0, 0, 0, 0, 0, 0],
            requiresResolvedPartners: true
        )

        XCTAssertNil(bluetoothRound)
    }
}
