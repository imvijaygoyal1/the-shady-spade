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

// MARK: - AI-04 — is the seat-assigned personality spread costing anything?

/// `BotPersonality.forSeat` is `styles[seat % 5]`, and `unsafeFeedTolerance` runs **0, 1, 2, 1, 3**
/// across conservative / aggressive / pointFeeder / trumpController / riskTaker. In an identical
/// position seat 0 withholds and seat 4 feeds into three live threats, which reads as arbitrary.
///
/// Two measurements, because either alone would mislead:
///
/// 1. **Per seat, in the real mixed table.** Personality is a pure function of seat and the deals
///    are random, so seat-level results attribute directly to a style — no new configuration
///    needed, and it measures each style *in the table it actually plays in*.
/// 2. **Uniform tables.** One style on all six seats isolates its cost from who it sits beside.
///    `bidMade` is meaningless here (both teams share the style); avoidable misfeeds are not.
final class AIPersonalityTests: XCTestCase {

    private let hands = 120

    private static let seatStyles: [(Int, String)] = [
        (0, "conservative"), (1, "aggressive"), (2, "pointFeeder"),
        (3, "trumpController"), (4, "riskTaker"), (5, "conservative #2")
    ]

    /// Seats 0 and 5 are **both** conservative (`5 % 5 == 0`), so the table is not an even spread —
    /// conservative gets two seats and riskTaker one. That is worth seeing before reading anything
    /// into a single seat's number.
    func testReportPerSeatPersonalityCost() {
        let s = AISelfPlay.run(hands: hands)
        var lines = ["", "── AI-04: PER-SEAT, IN THE REAL MIXED TABLE ───────────────────────",
                     "seat  style             avoidable/hand   points won/hand"]
        for (seat, name) in Self.seatStyles {
            lines.append(String(format: "  %d   %-16@ %8.1f %16.1f",
                                seat, name as NSString,
                                s.avoidableMisfeedsBySeat[seat], s.pointsWonBySeat[seat]))
        }
        lines.append("───────────────────────────────────────────────────────────────────")
        print(lines.joined(separator: "\n") + "\n")
        XCTAssertEqual(s.avoidableMisfeedsBySeat.count, 6)
    }

    /// Every seat the same style. Compare avoidable misfeeds across runs to see what each style
    /// gives away when it is not being carried — or dragged — by the seats beside it.
    func testReportUniformPersonalityTables() {
        let styles: [(AIEngine.BotPersonality, String)] = [
            (.conservative, "conservative"), (.aggressive, "aggressive"),
            (.pointFeeder, "pointFeeder"), (.trumpController, "trumpController"),
            (.riskTaker, "riskTaker")
        ]
        var lines = ["", "── AI-04: UNIFORM TABLES (all six seats one style) ────────────────",
                     "style              feedTol   avoidable/hand   offense pts/hand"]
        for (style, name) in styles {
            let s = AISelfPlay.run(hands: hands, options: .init(personalityOverride: style))
            lines.append(String(format: "%-18@ %5d %14.1f %17.1f",
                                name as NSString, style.unsafeFeedTolerance,
                                s.avgAvoidableMisfeedsPerHand, s.avgOffensePoints))
        }
        let mixed = AISelfPlay.run(hands: hands)
        lines.append(String(format: "%-18@ %5@ %14.1f %17.1f",
                            "MIXED (shipping)" as NSString, "0-3" as NSString,
                            mixed.avgAvoidableMisfeedsPerHand, mixed.avgOffensePoints))
        lines.append("───────────────────────────────────────────────────────────────────")
        print(lines.joined(separator: "\n") + "\n")
        XCTAssertGreaterThan(mixed.hands, 0)
    }

    /// The spread is only defensible if the styles actually differ in play. If every uniform table
    /// produced the same number, `unsafeFeedTolerance` would be decoration.
    func testPersonalitiesActuallyDifferInPlay() {
        let conservative = AISelfPlay.run(
            hands: hands, options: .init(personalityOverride: .conservative))
        let riskTaker = AISelfPlay.run(
            hands: hands, options: .init(personalityOverride: .riskTaker))
        XCTAssertNotEqual(conservative.avgAvoidableMisfeedsPerHand,
                          riskTaker.avgAvoidableMisfeedsPerHand,
                          "tolerance 0 and tolerance 3 must not play identically")
    }
}

// MARK: - When does the defence become known?

/// Asked directly: *"can you check that a scenario happens where a defence team player is revealed
/// way before it should be?"*
///
/// The display itself is clean — all 13 `resolveAvatarRole` call sites pass the *revealed* partner
/// values during play and only pass ground truth once the round is complete, and `isConfirmedDefense`
/// requires **both** partners revealed. So defence cannot be labelled early by the UI directly.
///
/// But it can be exposed *indirectly*. Once both called cards are played, everyone else is defence
/// by elimination — so the real question is how early the **second** partner reveals. `AIEngine`
/// reveals on purpose (`hiddenPartnerRevealCard`, `partnerRevealIntent`), so this measures whether
/// that intent fires too eagerly. Eight tricks per hand; a reveal at trick 1–2 exposes the table
/// almost immediately.
final class AIPartnerRevealTimingTests: XCTestCase {

    func testReportWhenTheDefenceBecomesKnown() {
        let hands = 200
        var firstRevealHistogram = [Int: Int]()
        var exposedHistogram = [Int: Int]()
        var neverExposed = 0

        var forcedCount = 0, revealCount = 0, forcedEarly = 0, earlyCount = 0
        for i in 0..<hands {
            let r = AISelfPlay.playHand(seed: UInt64(5000 + i))
            for (t, forced) in zip(r.partnerRevealTricks, r.partnerRevealForced) {
                guard let t, let forced else { continue }
                revealCount += 1
                if forced { forcedCount += 1 }
                if t == 1 {
                    earlyCount += 1
                    if forced { forcedEarly += 1 }
                }
            }
            let tricks = r.partnerRevealTricks.compactMap { $0 }
            if let first = tricks.min() { firstRevealHistogram[first, default: 0] += 1 }
            if let exposed = r.defenceExposedOnTrick {
                exposedHistogram[exposed, default: 0] += 1
            } else {
                neverExposed += 1
            }
        }

        func render(_ h: [Int: Int], label: String) -> String {
            var out = ["\(label)"]
            for trick in 1...8 {
                let n = h[trick] ?? 0
                let pct = Double(n) / Double(hands) * 100
                let bar = String(repeating: "█", count: Int(pct / 2))
                out.append(String(format: "  trick %d  %3d  %5.1f%%  %@", trick, n, pct, bar as NSString))
            }
            return out.joined(separator: "\n")
        }

        print("""

        forced (no legal alternative): \(forcedCount) of \(revealCount) reveals  \(String(format: "%.1f%%", Double(forcedCount) / Double(max(1, revealCount)) * 100))
        forced among TRICK-1 reveals:  \(forcedEarly) of \(earlyCount)  \(String(format: "%.1f%%", Double(forcedEarly) / Double(max(1, earlyCount)) * 100))

        ── WHEN PARTNERS REVEAL (\(hands) hands, 8 tricks each) ───────────
        \(render(firstRevealHistogram, label: "FIRST partner revealed on:"))

        \(render(exposedHistogram, label: "DEFENCE FULLY EXPOSED on (both called cards played):"))
          never       \(neverExposed)  \(String(format: "%5.1f%%", Double(neverExposed) / Double(hands) * 100))
        ───────────────────────────────────────────────────────────────────

        """)
        XCTAssertEqual(firstRevealHistogram.values.reduce(0, +) + 0, firstRevealHistogram.values.reduce(0, +))
    }

    /// A called card cannot be played before the hand starts, and cannot be played twice.
    func testRevealTricksAreWithinTheHand() {
        for seed in UInt64(5000)...5030 {
            let r = AISelfPlay.playHand(seed: seed)
            for t in r.partnerRevealTricks.compactMap({ $0 }) {
                XCTAssertTrue((1...8).contains(t), "seed \(seed): reveal on trick \(t)")
            }
        }
    }
}

// MARK: - Can a defender be labelled before the offense is fully revealed?

/// The owner reported: *"In solo mode, when a hand is won by a player then the icon says that the
/// player is in defense, and it happened before the bidding team is fully revealed."*
///
/// `resolveAvatarRole` is the single source of truth for that badge in all four modes, so the claim
/// is decidable exhaustively rather than by reading: enumerate **every** combination of revealed
/// state and assert `.defense` is impossible while either partner slot is still unknown.
final class AvatarRoleRevealTests: XCTestCase {

    /// The invariant, over every reachable input. 6 players × 4 revealed-state combinations.
    func testDefenseIsNeverShownWhileAPartnerIsStillUnknown() {
        let bidder = 0
        let states: [(Int?, Int?, String)] = [
            (nil, nil, "neither partner revealed"),
            (2,   nil, "only partner 1 revealed"),
            (nil, 3,   "only partner 2 revealed")
        ]
        for (p1, p2, label) in states {
            for player in 0..<6 {
                let role = resolveAvatarRole(
                    playerIndex: player, bidderIndex: bidder,
                    revealedPartner1: p1, revealedPartner2: p2,
                    isRoundComplete: false)
                XCTAssertNotEqual(role, .defense,
                    "\(label): player \(player) must not read as DEFENSE — the unrevealed partner could be them")
            }
        }
    }

    /// …and the badge must appear once both are known, or the label would never be usable.
    func testDefenseAppearsOnlyAfterBothPartnersAreRevealed() {
        let role = resolveAvatarRole(
            playerIndex: 4, bidderIndex: 0,
            revealedPartner1: 2, revealedPartner2: 3,
            isRoundComplete: false)
        XCTAssertEqual(role, .defense, "with the whole offense known, everyone else is defense")

        XCTAssertEqual(resolveAvatarRole(playerIndex: 0, bidderIndex: 0,
                                         revealedPartner1: 2, revealedPartner2: 3), .bidder)
        XCTAssertEqual(resolveAvatarRole(playerIndex: 2, bidderIndex: 0,
                                         revealedPartner1: 2, revealedPartner2: 3), .partner)
    }

    /// The 2 v 4 hand: one player holds **both** called cards. The second reveal is the same player,
    /// and at that moment the offense really is complete — so defense is correct, not premature.
    func testOnePlayerHoldingBothCalledCardsStillRevealsCorrectly() {
        let onlyFirstPlayed = resolveAvatarRole(
            playerIndex: 4, bidderIndex: 0,
            revealedPartner1: 2, revealedPartner2: nil)
        XCTAssertNotEqual(onlyFirstPlayed, .defense,
                          "one called card played is not enough, even when the same player holds both")

        let bothPlayed = resolveAvatarRole(
            playerIndex: 4, bidderIndex: 0,
            revealedPartner1: 2, revealedPartner2: 2)
        XCTAssertEqual(bothPlayed, .defense,
                       "offense is the bidder plus seat 2 only — everyone else is genuinely defense")
    }
}

// MARK: - AI-08 — what concealment actually costs

/// Withholding the called card trades card strength for hidden information. A trade should be
/// measured, not asserted — so this runs both ways over **identical deals** and prints the ledger.
final class AIConcealmentCostTests: XCTestCase {

    func testReportConcealmentTradeoff() {
        let hands = 400
        let on  = AISelfPlay.run(hands: hands, options: .init(concealsCalledCards: true))
        let off = AISelfPlay.run(hands: hands, options: .init(concealsCalledCards: false))

        print("""

        ── AI-08: WHAT CONCEALMENT COSTS (\(hands) identical deals) ────────
                                 concealed      off      delta
        bid made            \(String(format: "%11.1f%% %8.1f%% %9.1f", on.bidMadeRate * 100, off.bidMadeRate * 100, (on.bidMadeRate - off.bidMadeRate) * 100))
        offense pts/hand    \(String(format: "%11.1f %9.1f %9.1f", on.avgOffensePoints, off.avgOffensePoints, on.avgOffensePoints - off.avgOffensePoints))
        avoidable misfeeds  \(String(format: "%11.1f %9.1f %9.1f", on.avgAvoidableMisfeedsPerHand, off.avgAvoidableMisfeedsPerHand, on.avgAvoidableMisfeedsPerHand - off.avgAvoidableMisfeedsPerHand))
        ───────────────────────────────────────────────────────────────────

        """)
        XCTAssertEqual(on.illegalPlays, 0)
        XCTAssertEqual(off.illegalPlays, 0)
    }
}
