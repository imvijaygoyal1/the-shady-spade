import XCTest
@testable import MyApp

final class LeaderboardPendingQueueTests: XCTestCase {
    func test_encodeDecodeRoundTripsPendingRecords() throws {
        let records = [
            makeRecord(sessionCode: "ABC123R1", winnerIndex: 1),
            makeRecord(sessionCode: "ABC123R2", winnerIndex: 2, bid: 145)
        ]

        let data = try XCTUnwrap(LeaderboardPendingQueue.encode(records))
        let decoded = try XCTUnwrap(LeaderboardPendingQueue.decode(data))

        XCTAssertEqual(decoded.map(\.id), records.map(\.id))
        XCTAssertEqual(decoded.map(\.sessionCode), ["ABC123R1", "ABC123R2"])
        XCTAssertEqual(decoded.map(\.deduplicationKey), records.map(\.deduplicationKey))
        XCTAssertEqual(decoded[1].bid, 145)
    }

    func test_decodeRejectsCorruptPayload() {
        let corrupt = Data("{\"not\":\"an array\"}".utf8)
        XCTAssertNil(LeaderboardPendingQueue.decode(corrupt))
    }

    func test_loadPrefersFileAndMigratesLegacyDefaultsWhenFileMissing() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("leaderboard_pending_v1.json")
        let suiteName = "LeaderboardPendingQueueTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let legacyRecords = [makeRecord(sessionCode: "LEGACYR1", winnerIndex: 1)]
        defaults.set(try XCTUnwrap(LeaderboardPendingQueue.encode(legacyRecords)), forKey: "legacy")

        let migrated = LeaderboardPendingQueue.load(
            fileURL: fileURL,
            legacyDefaults: defaults,
            legacyKey: "legacy"
        )
        XCTAssertEqual(migrated.map(\.sessionCode), ["LEGACYR1"])
        XCTAssertNil(defaults.data(forKey: "legacy"))
        XCTAssertEqual(LeaderboardPendingQueue.load(from: fileURL)?.map(\.sessionCode), ["LEGACYR1"])

        let fileRecords = [makeRecord(sessionCode: "FILER1", winnerIndex: 2)]
        LeaderboardPendingQueue.save(fileRecords, to: fileURL)
        defaults.set(try XCTUnwrap(LeaderboardPendingQueue.encode(legacyRecords)), forKey: "legacy")

        let loaded = LeaderboardPendingQueue.load(
            fileURL: fileURL,
            legacyDefaults: defaults,
            legacyKey: "legacy"
        )
        XCTAssertEqual(loaded.map(\.sessionCode), ["FILER1"])
        XCTAssertNotNil(defaults.data(forKey: "legacy"))
    }

    func test_enqueueReplacesSameDeduplicationKeyAndCapsQueueToNewestHundred() {
        let original = makeRecord(sessionCode: "ROOMR1", winnerIndex: 1, bid: 130)
        let replacement = makeRecord(sessionCode: "ROOMR1", winnerIndex: 2, bid: 145)

        let replaced = LeaderboardPendingQueue.enqueue(replacement, into: [original])
        XCTAssertEqual(replaced.count, 1)
        XCTAssertEqual(replaced[0].id, replacement.id)
        XCTAssertEqual(replaced[0].winnerIndex, 2)
        XCTAssertEqual(replaced[0].bid, 145)

        let manyRecords = (0..<105).map { index in
            makeRecord(sessionCode: "ROOMR\(index)", winnerIndex: index % 6)
        }
        let capped = manyRecords.reduce(into: [PendingGameRecord]()) { partial, record in
            partial = LeaderboardPendingQueue.enqueue(record, into: partial)
        }
        XCTAssertEqual(capped.count, LeaderboardPendingQueue.maximumRecordCount)
        XCTAssertEqual(capped.first?.sessionCode, "ROOMR5")
        XCTAssertEqual(capped.last?.sessionCode, "ROOMR104")
    }

    func test_removeDropsMatchingIdAndSameGameReplacement() {
        let sent = makeRecord(sessionCode: "SAMER1", winnerIndex: 1)
        let sameGameReplacement = makeRecord(sessionCode: "SAMER1", winnerIndex: 2)
        let other = makeRecord(sessionCode: "OTHERR1", winnerIndex: 3)

        let remaining = LeaderboardPendingQueue.remove(sent, from: [sent, sameGameReplacement, other])

        XCTAssertEqual(remaining.map(\.id), [other.id])
        XCTAssertEqual(remaining.map(\.sessionCode), ["OTHERR1"])
    }

    private func makeRecord(
        sessionCode: String?,
        winnerIndex: Int,
        bid: Int = 130
    ) -> PendingGameRecord {
        PendingGameRecord(
            sessionCode: sessionCode,
            gameMode: "Online",
            playerNames: ["A", "B", "C", "D", "E", "F"],
            finalScores: [0, 10, 20, 30, 40, 50],
            winnerIndex: winnerIndex,
            aiSeats: [4, 5],
            bid: bid,
            bidMade: true,
            bidderIndex: 1,
            partner1Index: 2,
            partner2Index: 3,
            defensePointsCaught: 95,
            roundCount: 1,
            recordedAt: Date(timeIntervalSince1970: TimeInterval(winnerIndex))
        )
    }
}

// MARK: - InFlightSendTracker

/// The rule that stops a completed game being written to the leaderboard twice.
///
/// It lived as two private `Set`s inside `LeaderboardService` at 0% coverage, so the one guard
/// against duplicate leaderboard entries could not be asserted at all. Duplicates are visible to
/// the user and cannot be removed, and the leaderboard has prior form here — a earlier audit
/// found 19 findings in this area.
final class InFlightSendTrackerTests: XCTestCase {

    func test_claimSucceedsOnceThenRefusesTheSameRecord() {
        var tracker = InFlightSendTracker()
        let id = UUID()

        XCTAssertTrue(tracker.claim(id: id, deduplicationKey: "game-a"))
        XCTAssertFalse(tracker.claim(id: id, deduplicationKey: "game-a"),
                       "A second claim for the same send must be refused.")
    }

    /// The case that actually produces a duplicate leaderboard row: two *different* record
    /// objects describing the same completed game. Matching on id alone would let both through.
    func test_claimRefusesADifferentRecordWithTheSameDeduplicationKey() {
        var tracker = InFlightSendTracker()

        XCTAssertTrue(tracker.claim(id: UUID(), deduplicationKey: "same-game"))
        XCTAssertFalse(tracker.claim(id: UUID(), deduplicationKey: "same-game"),
                       "A different record for the same game must not send concurrently.")
    }

    /// The mirror case: matching on key alone would wrongly block a legitimate retry that
    /// carries a fresh key, so the id dimension has to be checked too.
    func test_claimRefusesTheSameIDEvenWithADifferentKey() {
        var tracker = InFlightSendTracker()
        let id = UUID()

        XCTAssertTrue(tracker.claim(id: id, deduplicationKey: "key-1"))
        XCTAssertFalse(tracker.claim(id: id, deduplicationKey: "key-2"))
    }

    func test_releaseAllowsTheSendToBeClaimedAgain() {
        var tracker = InFlightSendTracker()
        let id = UUID()

        XCTAssertTrue(tracker.claim(id: id, deduplicationKey: "game-a"))
        tracker.release(id: id, deduplicationKey: "game-a")
        XCTAssertTrue(tracker.claim(id: id, deduplicationKey: "game-a"),
                      "After a send completes, a retry must be allowed — otherwise a failed "
                      + "send could never be retried and the score would be lost.")
    }

    /// Independent games must not block each other, or a busy flush would drop scores. Asserting
    /// only the refusals would pass against a tracker that refused everything.
    func test_independentGamesCanBeInFlightTogether() {
        var tracker = InFlightSendTracker()

        XCTAssertTrue(tracker.claim(id: UUID(), deduplicationKey: "game-a"))
        XCTAssertTrue(tracker.claim(id: UUID(), deduplicationKey: "game-b"))
        XCTAssertTrue(tracker.claim(id: UUID(), deduplicationKey: "game-c"))
    }

    func test_releasingOneSendDoesNotReleaseAnother() {
        var tracker = InFlightSendTracker()
        let a = UUID(), b = UUID()
        XCTAssertTrue(tracker.claim(id: a, deduplicationKey: "game-a"))
        XCTAssertTrue(tracker.claim(id: b, deduplicationKey: "game-b"))

        tracker.release(id: a, deduplicationKey: "game-a")

        XCTAssertFalse(tracker.isInFlight(id: a, deduplicationKey: "game-a"))
        XCTAssertTrue(tracker.isInFlight(id: b, deduplicationKey: "game-b"),
                      "Releasing one send must not clear another.")
    }

    func test_releasingAnUnclaimedSendIsHarmless() {
        var tracker = InFlightSendTracker()
        tracker.release(id: UUID(), deduplicationKey: "never-claimed")
        XCTAssertTrue(tracker.claim(id: UUID(), deduplicationKey: "never-claimed"))
    }
}
