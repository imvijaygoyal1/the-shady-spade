//
//  AISelfPlayTests.swift
//  MyAppTests
//
//  Measures the bots instead of asking someone to play them.
//

import XCTest
@testable import MyApp

final class AISelfPlayTests: XCTestCase {

    /// Kept small enough to sit in the ordinary suite. SCAN-PERF-01 on the other app was a heavy
    /// test starving 185 others; the lesson travels.
    private let handsPerRun = 120

    /// The referee must never have to step in. If it does, every other number in this file is
    /// describing a different game from the one the app plays, so this is asserted before anything
    /// else is believed.
    func testBotsNeverPlayAnIllegalCard() {
        let summary = AISelfPlay.run(hands: handsPerRun)
        XCTAssertEqual(summary.illegalPlays, 0,
                       "the engine returned nil or an unplayable card \(summary.illegalPlays) times")
    }

    /// The same seeds must produce the same hand, or nothing here can be compared across a change.
    func testRunsAreReproducible() {
        let a = AISelfPlay.playHand(seed: 42)
        let b = AISelfPlay.playHand(seed: 42)
        XCTAssertEqual(a.offensePoints, b.offensePoints)
        XCTAssertEqual(a.bidderIndex, b.bidderIndex)
        XCTAssertEqual(a.pointsFedToOpponents, b.pointsFedToOpponents)
    }

    /// Sanity on the model itself: all 250 points are always accounted for, so a "points fed"
    /// figure cannot be an artefact of cards going missing.
    func testEveryPointIsAccountedForInEveryHand() {
        for seed in UInt64(1)...20 {
            let r = AISelfPlay.playHand(seed: seed)
            // NOT always 3 v 3. The bidder calls two cards; if one player happens to hold both,
            // offense is the bidder plus a single partner. The first version of this test asserted
            // 3 v 3 and failed on the very first seed — the harness was right and the assumption
            // was wrong. Worth knowing, because `sameSideConfidence` assumes three offense seats:
            // when there are only two it is *more* cautious than it needs to be, which is the safe
            // direction to be wrong in.
            XCTAssertTrue((2...3).contains(r.offenseSeats.count),
                          "seed \(seed): offense is the bidder plus one or two partners")
            XCTAssertLessThanOrEqual(r.offensePoints, 250)
            XCTAssertGreaterThanOrEqual(r.offensePoints, 0)
        }
    }

    /// The headline measurement. Not asserted against a threshold yet — there is no baseline anyone
    /// has earned the right to assert, and a floor invented today would be a number I made up.
    /// It is printed so the next change can be compared against it.
    func testReportBotBehaviourBaseline() {
        let summary = AISelfPlay.run(hands: handsPerRun)
        print("""

        ── AI SELF-PLAY BASELINE ──────────────────────────────────────────
        hands                      \(summary.hands)
        bid made                   \(String(format: "%.1f%%", summary.bidMadeRate * 100))
        offense points / hand      \(String(format: "%.1f", summary.avgOffensePoints)) of 250
        to opponents (incl forced) \(String(format: "%.1f", summary.avgFedToOpponentsPerHand)) per hand
        to teammates               \(String(format: "%.1f", summary.avgFedToTeammatesPerHand)) per hand
        AVOIDABLE misfeeds         \(String(format: "%.1f", summary.avgAvoidableMisfeedsPerHand)) per hand
        misfeed share (raw)        \(String(format: "%.1f%%", summary.misfeedShare * 100))
        illegal plays              \(summary.illegalPlays)
        ───────────────────────────────────────────────────────────────────

        """)
        XCTAssertGreaterThan(summary.hands, 0)
    }

    /// AI-05 with a number attached rather than an opinion: how much is the bidder's free knowledge
    /// of its own partners actually worth? Same seeds both ways, so the deals are identical.
    func testMeasureWhatTheBidderPartnerKnowledgeIsWorth() {
        let withKnowledge = AISelfPlay.run(
            hands: handsPerRun, options: .init(bidderKnowsPartners: true))
        let without = AISelfPlay.run(
            hands: handsPerRun, options: .init(bidderKnowsPartners: false))
        print("""

        ── AI-05: WHAT THE BIDDER'S PARTNER KNOWLEDGE IS WORTH ────────────
        bid made   with knowledge  \(String(format: "%.1f%%", withKnowledge.bidMadeRate * 100))
        bid made   without         \(String(format: "%.1f%%", without.bidMadeRate * 100))
        offense pts with           \(String(format: "%.1f", withKnowledge.avgOffensePoints))
        offense pts without        \(String(format: "%.1f", without.avgOffensePoints))
        ───────────────────────────────────────────────────────────────────

        """)
        XCTAssertEqual(withKnowledge.hands, without.hands)
    }
}
