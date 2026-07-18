# AI Advanced Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 5 independent AI improvements to `AIEngine.swift`: safety plays when bid is secure, finessing, discard signaling, endgame extension to 3 tricks, and bidder-partner coordination post-reveal.

**Architecture:** All changes are confined to `AIEngine.swift` — additive score adjustments and one new private helper. The `Urgency` struct gains one new field (`bidSecure`), `bestLeadCard` gains one new parameter (`revealedPartnerIndices`). No ViewModels or public signatures change beyond the internal `bestLeadCard` call site in `computeCard`.

**Tech Stack:** Swift, XCTest. Build: `xcodebuild`. Test: `xcodebuild test`.

---

## Background: Key Locations in AIEngine.swift

| Symbol | Line |
|---|---|
| `Urgency` struct | ~98 |
| `computeCard` — leading path | ~551 |
| `computeCard` — endgame gate | ~574 |
| `computeCard` — bestLeadCard call | ~585 |
| `computeCard` — can't-follow path | ~671 |
| `computeCard` — effectiveTrumpThreshold` | ~704 |
| `urgencyState` | ~1031 |
| `bestLeadCard` | ~1079 |
| `bestLeadCard` — trump scoring block | ~1142 |
| `bestLeadCard` — non-trump scoring block | ~1159 |
| `bestLeadCard` — bidder called-suit probe | ~1181 |
| `computeEndgameLead` | ~1321 |

---

## Task 1: Safety Plays When Bid Is Secure

Offense bots burn trump and take risks even after making their bid. This adds a `bidSecure` flag to `Urgency` and applies two penalties when secure: (A) penalise risky trump leads, (B) raise the ruffing threshold.

**Files:**
- Modify: `MyApp/AIEngine.swift`
- Test: `MyAppTests/AIEngineTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `AIEngineTests.swift` inside the class, after the existing `test_trumpPull_doesNotFireWithFewerThanTwoEstablishedWinners` test:

```swift
// MARK: - Safety Plays (Bid Secure)

// Scenario: offense bot (seat=0, bidder) has already made the bid (offensePoints=155, highBid=150).
// Hand: A♠ (high trump), 4♠ (risky trump — higherTrumpRemaining>=2), K♥ (non-trump winner).
// With bidSecure=true and higherTrumpRemaining>=2: 4♠ gets -12 penalty.
// Without the penalty 4♠ would outscore K♥; with it K♥ should win.
func test_safetyPlay_avoidsRiskyTrumpLeadWhenBidSecure() {
    // offensePoints: seat0(bidder)+seat2+seat4 = wonPoints[0]+wonPoints[2]+wonPoints[4]
    // Set wonPoints so offensePoints=155 >= highBid=150.
    // K♥ remaining higher: A♥,Q♥ (2 cards) → higherRemaining=2.
    // 4♠ remaining higher trump: A♠,K♠,Q♠,J♠,10♠ (many) → higherTrumpRemaining>=2.
    let hand = [c("A","♠"), c("4","♠"), c("K","♥")]

    let result = lead(
        seat: 0,
        hand: hand,
        highBidderIndex: 0,
        actualPartners: [2, 4],
        revealedPartners: [2, 4],
        trumpSuit: .spades,
        wonPoints: [155, 0, 0, 0, 0, 0],  // offensePoints=155 >= highBid=150 → bidSecure
        highBid: 150,
        trickNumber: 3
    )

    // A♠ is fine (higherTrumpRemaining==0 for A♠ → no penalty).
    // 4♠ gets -12 (risky trump, bidSecure). K♥ (higherRemaining=2, penaltyFactor=1 → -2).
    // A♠ should win but could also be the result; what we assert is 4♠ is NOT chosen.
    XCTAssertNotEqual(result, "4♠",
        "Offense bot with secure bid should not lead risky 4♠ trump; got \(result ?? "nil")")
}

// Scenario: offense bot can't follow — holds trump. Bid is secure.
// With bidSecure: effectiveTrumpThreshold += 20.
// Trick value = 10 (one 10-point card). Normal threshold=5 (aggressive).
// After bidSecure: threshold=25. trickPoints(10) < 25 → should NOT trump.
func test_safetyPlay_raisesRuffThresholdWhenBidSecure() {
    // Offense bot (seat=0, bidder). Can't follow (hand has no hearts). Holds trump.
    // Current trick: player1 leads 10♥ (10 pts), player5 plays 5♥ → trickPoints=15.
    // bidSecure → threshold becomes 5+20=25. trickPoints(15) < 25 → discard instead of ruff.
    let hand = [c("J","♠"), c("3","♦"), c("4","♦")]  // no hearts → can't follow
    let currentTrick: [(playerIndex: Int, card: Card)] = [
        (playerIndex: 1, card: c("10","♥")),
        (playerIndex: 5, card: c("5","♥")),
    ]

    let result = AIEngine.computeCard(
        seat: 0,
        hand: hand,
        actualPartnerIndices: [2, 4],
        revealedPartnerIndices: [2, 4],
        calledCardIds: [],
        highBidderIndex: 0,
        trumpSuit: .spades,
        currentTrick: currentTrick,
        completedTricks: [],
        wonPointsPerPlayer: [155, 0, 0, 0, 0, 0],  // bidSecure
        highBid: 150,
        trickNumber: 3,
        personality: .aggressive  // aggressive threshold=10, after bidSecure=30 > trickPoints(15)
    )

    // Should discard (3♦ or 4♦), not ruff with J♠.
    XCTAssertNotEqual(result, "J♠",
        "Offense bot with secure bid should not ruff a 15-point trick (threshold raised to 30); got \(result ?? "nil")")
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp && xcodebuild test \
  -project MyApp.xcodeproj -scheme MyApp \
  -destination "platform=iOS Simulator,id=DA97985A-F7CC-44F6-8281-9DD24C22B978" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:MyAppTests/AIEngineTests/test_safetyPlay_avoidsRiskyTrumpLeadWhenBidSecure \
  -only-testing:MyAppTests/AIEngineTests/test_safetyPlay_raisesRuffThresholdWhenBidSecure \
  2>&1 | grep -E "FAILED|PASSED|error:|Build succeeded|Build FAILED"
```

Expected: tests fail (feature not yet implemented).

- [ ] **Step 3: Add `bidSecure` to the `Urgency` struct**

In `AIEngine.swift`, the `Urgency` struct starts at ~line 98. Add `bidSecure` after `bidderCloseToWin`:

```swift
private struct Urgency {
    let offense: Bool
    let defense: Bool
    let offensePoints: Int
    let defensePoints: Int
    let remainingPoints: Int
    let tricksRemaining: Int
    let bidderCloseToWin: Bool
    let bidSecure: Bool        // ← ADD THIS

    var eitherSide: Bool { offense || defense }
}
```

- [ ] **Step 4: Compute `bidSecure` in `urgencyState`**

In `urgencyState` (~line 1063), find the `bidderCloseToWin` computation and add `bidSecure` right after it, before the `return Urgency(...)`:

```swift
let bidSecure = offensePoints >= highBid

return Urgency(
    offense: offenseUrgent,
    defense: defenseUrgent,
    offensePoints: offensePoints,
    defensePoints: defensePoints,
    remainingPoints: remainingPoints,
    tricksRemaining: tricksRemaining,
    bidderCloseToWin: bidderCloseToWin,
    bidSecure: bidSecure              // ← ADD THIS
)
```

- [ ] **Step 5: Apply Change A — risky trump lead penalty in `bestLeadCard`**

In `bestLeadCard`, the trump scoring block (~line 1142) currently contains:

```swift
if higherTrumpRemaining >= 3 { score -= higherTrumpRemaining * 4 }
```

Add the bidSecure penalty immediately after that line:

```swift
if higherTrumpRemaining >= 3 { score -= higherTrumpRemaining * 4 }
if isKnownOffense && urgency.bidSecure && higherTrumpRemaining >= 2 { score -= 12 }
```

- [ ] **Step 6: Apply Change B — raised ruffing threshold in `computeCard`**

In `computeCard`, find the `effectiveTrumpThreshold` block (~line 704). It currently looks like:

```swift
let effectiveTrumpThreshold: Int
if threeSpadeInTrick {
    effectiveTrumpThreshold = 0
} else if threeSpadeStillOut && !urgency.eitherSide {
    effectiveTrumpThreshold = style.trumpInPointThreshold + 15
} else {
    effectiveTrumpThreshold = style.trumpInPointThreshold
}
```

Change it to a `var` and add the `bidSecure` raise after the existing conditions:

```swift
var effectiveTrumpThreshold: Int
if threeSpadeInTrick {
    effectiveTrumpThreshold = 0
} else if threeSpadeStillOut && !urgency.eitherSide {
    effectiveTrumpThreshold = style.trumpInPointThreshold + 15
} else {
    effectiveTrumpThreshold = style.trumpInPointThreshold
}
if isKnownOffense && urgency.bidSecure { effectiveTrumpThreshold += 20 }
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp && xcodebuild test \
  -project MyApp.xcodeproj -scheme MyApp \
  -destination "platform=iOS Simulator,id=DA97985A-F7CC-44F6-8281-9DD24C22B978" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO \
  2>&1 | grep -E "FAILED|PASSED|executed|Build succeeded|Build FAILED"
```

Expected: all tests pass (including the 2 new ones and all 19 existing ones).

- [ ] **Step 8: Commit**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp && git add MyApp/AIEngine.swift MyAppTests/AIEngineTests.swift && git commit -m "feat(ai): add safety plays when bid is secure

Offense bots now protect their lead after making their bid:
- bidSecure flag fires when offensePoints >= highBid
- Risky trump leads (higherTrumpRemaining >= 2) get -12 penalty
- Ruffing threshold raised by +20 so bots discard instead of burning trump on cheap tricks"
```

---

## Task 2: Finessing

When deciding which non-trump suit to lead, bots currently treat all remaining higher cards as equally dangerous. This adds a positional adjustment: if the nearest opponent (1–3 seats after the bot) probably holds the beating card, penalise the lead; if they probably don't, give a bonus.

**Files:**
- Modify: `MyApp/AIEngine.swift`
- Test: `MyAppTests/AIEngineTests.swift`

- [ ] **Step 1: Write the failing tests**

Add after the safety-play tests:

```swift
// MARK: - Finessing

// Scenario: bot (seat=0) choosing between Q♥ and J♣.
// For Q♥: only player 1 (nearest opponent, 1 seat after) is eligible.
//   Player 1 led ♥ in a completed trick → leadBoost → high prob of holding A♥/K♥.
//   Q♥ has higherRemaining=2 (A♥,K♥) → higherPenalty = -2 (offense bot, factor=1).
//   Finesse: threatProb(player:1, suit:♥, beatingRank:rankOf(Q♥)) is HIGH → -8.
// For J♣: no completed ♣ tricks → equal distribution, no lead boost.
//   threatProb for nearest opponent holding A♣/K♣/Q♣ is LOW → +5.
// Expected: bot leads J♣ (avoids finessing into player 1 who holds ♥ blockers).
func test_finessing_avoidsLeadIntoNearestOpponentWhoLikelyHoldsBeatingCard() {
    // Setup: seat=0 is bidder (offense). Player 1 is 1 seat after.
    // Completed trick: player1 led Q♥ → lead boost applies to ♥ for player1.
    let completedTricks: [[(playerIndex: Int, card: Card)]] = [[
        (playerIndex: 1, card: c("Q","♥")),
        (playerIndex: 2, card: c("3","♦")),
        (playerIndex: 3, card: c("4","♦")),
        (playerIndex: 4, card: c("5","♦")),
        (playerIndex: 5, card: c("6","♦")),
        (playerIndex: 0, card: c("7","♦")),
    ]]
    // Remaining ♥: A♥, K♥ (both still out — only Q♥ was played).
    // Remaining ♣: A♣, K♣, Q♣ (top 3 clubs still out, evenly distributed).
    let hand = [c("J","♥"), c("J","♣")]  // both Jacks, same rank, same points

    let result = lead(
        seat: 0,
        hand: hand,
        highBidderIndex: 0,
        actualPartners: [2, 4],
        revealedPartners: [2, 4],
        trumpSuit: .spades,
        completedTricks: completedTricks,
        trickNumber: 1
    )

    XCTAssertEqual(result, "J♣",
        "Bot should avoid finessing J♥ into player1 who likely holds ♥ blockers; got \(result ?? "nil")")
}

// Scenario: bot leads J♥ when nearest opponent almost certainly does NOT hold ♥ blockers.
// Player 1 is confirmed void in ♥ (knownVoids). No other opponent holds ♥ (voidProb≈1.0).
// Finesse bonus +5 should make J♥ preferred over J♣.
func test_finessing_prefersLeadWhenNearestOpponentCannotBeat() {
    // Player 1 is void in ♥ (played off-suit in a ♥-led trick).
    let completedTricks: [[(playerIndex: Int, card: Card)]] = [[
        (playerIndex: 0, card: c("Q","♥")),  // seat0 led hearts
        (playerIndex: 1, card: c("3","♦")),  // player1 played off-suit → void in ♥
        (playerIndex: 2, card: c("4","♦")),
        (playerIndex: 3, card: c("5","♦")),
        (playerIndex: 4, card: c("6","♦")),
        (playerIndex: 5, card: c("7","♦")),
    ]]
    // Only A♥ and K♥ remain in ♥. Player 1 is void → only players 2,3,4,5 eligible.
    // Nearest opponent is player 1 (1 seat after seat 0) — void in ♥ → threatProb ≈ 0 < 0.15 → +5.
    let hand = [c("J","♥"), c("J","♣")]

    let result = lead(
        seat: 0,
        hand: hand,
        highBidderIndex: 0,
        actualPartners: [2, 4],
        revealedPartners: [2, 4],
        trumpSuit: .spades,
        completedTricks: completedTricks,
        trickNumber: 1
    )

    XCTAssertEqual(result, "J♥",
        "Bot should prefer J♥ finesse when nearest opponent is void in ♥; got \(result ?? "nil")")
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp && xcodebuild test \
  -project MyApp.xcodeproj -scheme MyApp \
  -destination "platform=iOS Simulator,id=DA97985A-F7CC-44F6-8281-9DD24C22B978" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:MyAppTests/AIEngineTests/test_finessing_avoidsLeadIntoNearestOpponentWhoLikelyHoldsBeatingCard \
  -only-testing:MyAppTests/AIEngineTests/test_finessing_prefersLeadWhenNearestOpponentCannotBeat \
  2>&1 | grep -E "FAILED|PASSED|error:|Build succeeded|Build FAILED"
```

Expected: tests fail.

- [ ] **Step 3: Add finessing block in `bestLeadCard`**

In `bestLeadCard`, inside the `scored = hand.map` closure, in the non-trump (`else`) branch, locate the long-suit establishment block:

```swift
let suitLength = hand.filter { $0.suit == card.suit }.count
if higherRemaining > 0 {
    let establishmentPotential = suitLength - higherRemaining
    if establishmentPotential > 0 && urgency.tricksRemaining >= higherRemaining + 1 {
        score += establishmentPotential * 6
    }
}
```

Add the finessing block **immediately after** the `higherRemaining` penalty line (before the establishment block):

```swift
// Finessing: if the nearest opponent (1–3 seats after us) probably holds a
// beating card, leading into them is risky; if they almost certainly don't,
// the lead is safer than raw higherRemaining suggests.
if higherRemaining > 0, let model = handModel {
    let nextOpponent = (0..<6).first { p in
        let offset = (p - seat + 6) % 6
        return offset >= 1 && offset <= 3
            && strategicOffenseSet.contains(p) != isKnownOffense
    }
    if let opp = nextOpponent {
        let p = model.threatProb(player: opp, suit: card.suit,
                                 beatingRankScore: rankScore(card))
        if p > 0.5 { score -= 8 }
        else if p < 0.15 { score += 5 }
    }
}
```

The full non-trump block sequence after the edit:

```swift
let higherPenaltyFactor = isKnownOffense ? 1 : 3
score += higherRemaining == 0 ? 18 : -(higherRemaining * higherPenaltyFactor)
// Finessing block (NEW):
if higherRemaining > 0, let model = handModel {
    let nextOpponent = (0..<6).first { p in
        let offset = (p - seat + 6) % 6
        return offset >= 1 && offset <= 3
            && strategicOffenseSet.contains(p) != isKnownOffense
    }
    if let opp = nextOpponent {
        let p = model.threatProb(player: opp, suit: card.suit,
                                 beatingRankScore: rankScore(card))
        if p > 0.5 { score -= 8 }
        else if p < 0.15 { score += 5 }
    }
}
// Long suit establishment (existing):
let suitLength = hand.filter { $0.suit == card.suit }.count
if higherRemaining > 0 { ... }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp && xcodebuild test \
  -project MyApp.xcodeproj -scheme MyApp \
  -destination "platform=iOS Simulator,id=DA97985A-F7CC-44F6-8281-9DD24C22B978" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO \
  2>&1 | grep -E "FAILED|PASSED|executed|Build succeeded|Build FAILED"
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp && git add MyApp/AIEngine.swift MyAppTests/AIEngineTests.swift && git commit -m "feat(ai): add finessing — adjust lead scores based on nearest opponent position

When the nearest opponent (1-3 seats after the bot) probably holds a
beating card (prob>0.5), penalise the lead by -8. When they almost
certainly don't (prob<0.15), give a +5 bonus for the safer lead.
Skipped when handModel is nil (unit tests without trick context)."
```

---

## Task 3: Discard Signaling

When a teammate is winning and the bot can't feed points, the current code picks the lowest-value non-trump card by raw point value. This replaces that pick with a smarter helper that prefers discarding from suits the bot can't establish (implicit signal: "don't lead this back"), while protecting point cards.

**Files:**
- Modify: `MyApp/AIEngine.swift`
- Test: `MyAppTests/AIEngineTests.swift`

- [ ] **Step 1: Write the failing test**

Add after the finessing tests:

```swift
// MARK: - Discard Signaling

// Scenario: defense bot (seat=1) can't follow. Teammate (seat=5) is winning.
// Can't feed points (bidderCloseToWin=true → canFeedPoints override=false).
// Hand non-trump: 4♣ (last club in hand — unestablishable since A♣/K♣/Q♣ all out)
//                K♥ (10pts — point card, protected by -20 guard)
//                 7♦ (0pts, has 2 diamonds in hand → could establish)
// discardPreference: 4♣ = +10 (can't establish) − 0 (0pts) − rankScore(4♣)
//                    K♥ = 0 − 20 (point card) − 10 − rankScore(K♥) → very negative
//                     7♦ = 0 (can establish, suitCards=2 > higherOut=2? check) − 0 − rankScore(7♦)
// Expected: 4♣ discarded (unestablishable, 0pts), not K♥ (point card).
func test_discardSignaling_prefersUnestablishableSuitOverPointCard() {
    // bidderCloseToWin condition: offensePoints=120, highBid=150
    // offensePoints(120) >= 150*0.75=112.5 ✓, shortfall(30) <= remaining(80)/2=40 ✓
    // A♣,K♣,Q♣,J♣ are all played → 4♣ has higherOut=0, suitCards=1 → canEstablish=false
    let completedTricks: [[(playerIndex: Int, card: Card)]] = [[
        (playerIndex: 0, card: c("A","♣")),
        (playerIndex: 2, card: c("K","♣")),
        (playerIndex: 3, card: c("Q","♣")),
        (playerIndex: 4, card: c("J","♣")),
        (playerIndex: 5, card: c("10","♣")),
        (playerIndex: 1, card: c("9","♣")),
    ]]
    // Player 1's hand: no spades (can't follow spades). Trump=spades.
    // Winning trump is opponent's → teammate is player5 winning with K♥.
    // Actually, make teammate winning with a non-trump won by ally.
    // Easier: current trick led by player5 with K♥ (non-trump). Seat=1 can't follow hearts.
    let currentTrick: [(playerIndex: Int, card: Card)] = [
        (playerIndex: 5, card: c("K","♥")),  // teammate leading, winning (no higher hearts played/in hand)
    ]
    // Hand: 4♣ (last club), K♥... wait, K♥ is in the current trick.
    // Adjust: teammate leads A♥, hand has 4♣, Q♦, 7♦ (no hearts to follow).
    let currentTrick2: [(playerIndex: Int, card: Card)] = [
        (playerIndex: 5, card: c("A","♥")),  // teammate winning
    ]
    let hand = [c("4","♣"), c("K","♦"), c("7","♦")]  // no hearts → can't follow

    let result = AIEngine.computeCard(
        seat: 1,
        hand: hand,
        actualPartnerIndices: [],
        revealedPartnerIndices: [],
        calledCardIds: [],
        highBidderIndex: 0,
        trumpSuit: .spades,
        currentTrick: currentTrick2,
        completedTricks: completedTricks,
        wonPointsPerPlayer: [120, 0, 0, 0, 0, 0],  // bidderCloseToWin → canFeedPoints=false
        highBid: 150,
        trickNumber: 1
    )

    // K♦ = 10pts → discardPreference very negative (−20 guard + −10 pts + −rankScore).
    // 4♣ = unestablishable (+10) + 0pts → positive score → preferred.
    // 7♦ = can establish? hand has K♦,7♦ (suitCards=2). A♦,Q♦,J♦,10♦,9♦,8♦ still remaining
    //      → higherOut > suitCards → canEstablish=false → 7♦ also +10, but 4♣ has lower rankScore penalty.
    XCTAssertNotEqual(result, "K♦",
        "Bot should not discard K♦ (10pt card) when 0-point unestablishable discard available; got \(result ?? "nil")")
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp && xcodebuild test \
  -project MyApp.xcodeproj -scheme MyApp \
  -destination "platform=iOS Simulator,id=DA97985A-F7CC-44F6-8281-9DD24C22B978" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:MyAppTests/AIEngineTests/test_discardSignaling_prefersUnestablishableSuitOverPointCard \
  2>&1 | grep -E "FAILED|PASSED|error:|Build succeeded|Build FAILED"
```

Expected: test fails.

- [ ] **Step 3: Add `discardPreference` private helper**

In `AIEngine.swift`, add this private static method just before `rankScore` (~line 1305):

```swift
/// Signal-aware discard scoring: prefers discarding from suits the bot can't establish
/// (implicit "don't lead this back" signal), while strongly protecting point cards.
/// Higher score = better discard candidate.
private static func discardPreference(
    _ card: Card, hand: [Card], remainingCards: [Card]
) -> Int {
    let suitCards = hand.filter { $0.suit == card.suit }
    let higherOut = remainingCards.filter {
        $0.suit == card.suit && rankScore($0) > rankScore(card)
    }.count
    let canEstablish = higherOut < suitCards.count
    var score = 0
    if !canEstablish { score += 10 }   // can't win this suit — safe to abandon
    if card.pointValue > 0 { score -= 20 }  // never discard point card if avoidable
    score -= card.pointValue
    score -= rankScore(card)
    return score
}
```

- [ ] **Step 4: Replace the non-feeding discard in `computeCard`**

In `computeCard`, in the `teammateWinning` path (~line 688), find the non-feeding discard:

```swift
if let discard = nonTrump.min(by: { valueScore($0, personality: style) < valueScore($1, personality: style) }) {
    return discard.id
}
```

Replace it with:

```swift
if let discard = nonTrump.max(by: {
    discardPreference($0, hand: hand, remainingCards: remainingCards)
        < discardPreference($1, hand: hand, remainingCards: remainingCards)
}) {
    return discard.id
}
```

- [ ] **Step 5: Run all tests to verify they pass**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp && xcodebuild test \
  -project MyApp.xcodeproj -scheme MyApp \
  -destination "platform=iOS Simulator,id=DA97985A-F7CC-44F6-8281-9DD24C22B978" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO \
  2>&1 | grep -E "FAILED|PASSED|executed|Build succeeded|Build FAILED"
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp && git add MyApp/AIEngine.swift MyAppTests/AIEngineTests.swift && git commit -m "feat(ai): add discard signaling — prefer unestablishable suit discards

When forced to discard (teammate winning, can't follow, can't feed points),
bots now use discardPreference() to signal suit abandonment: prefer suits
where they cannot establish winners. Point cards protected by -20 guard."
```

---

## Task 4: Endgame Extension to 3 Tricks

`computeEndgameLead` is limited to the final 2 tricks. With 3 cards remaining (trick 6), near-exact calculation is still viable. This extends the guard and adds 3-card projection logic.

**Files:**
- Modify: `MyApp/AIEngine.swift`
- Test: `MyAppTests/AIEngineTests.swift`

- [ ] **Step 1: Write the failing test**

Add after the discard-signaling tests:

```swift
// MARK: - Endgame Extension (3 Tricks)

// Scenario: bot (seat=0, bidder) holds 3 cards, trickNumber=5 (tricksRemaining=3).
// Hand: A♠ (trump winner, pointValue=0), A♥ (non-trump winner, 0pts — safe if trump exhausted),
//       10♥ (10pts, wins if no higher ♥ remain and no trump).
// Remaining: K♥ still out, no trump remaining (trumpExhausted=true for non-trump check).
// Wait — for likelyWinsAsLead non-trump: no trump remaining AND no higher card in suit.
// A♥ is the highest heart → wins. 10♥ has K♥ still out → does NOT win.
// A♠ is highest trump... if trump=spades: no higher ♠ remaining → wins.
// Endgame scoring: A♠(wins, 0pts) score = 0*10+50=50. A♥(wins, 0pts) score=50.
// 3-card projection for A♠: remaining2=[A♥,10♥]. A♥ wins (+0*8+20=20). 10♥ loses (-10*5=-50).
//   → score += 20 → total=70.
// 3-card projection for A♥: remaining2=[A♠,10♥]. A♠ wins (highest trump) → +20. 10♥ loses.
//   → score += 20 → total=70. (tie → both valid)
// 10♥: does not win → score= -10*5 + rankScore(10♥)/2 → negative.
// Key assertion: bot does NOT lead 10♥ (the loser). It leads either winner.
func test_endgameExtension_botLeadsWinnerNotLoserWith3Cards() {
    // Trump = spades. A♠ in hand. No remaining spades → A♠ is top trump → wins.
    // Hearts: A♥ in hand. K♥ still remaining → A♥ is NOT highest (K... wait A > K).
    // A♥ is highest heart (A=rank 12, K=rank 11). No remaining higher hearts → A♥ wins.
    // 10♥ in hand. K♥ remaining (rank 11 > rank 8 of 10). So 10♥ does NOT win.
    let hand = [c("A","♠"), c("A","♥"), c("10","♥")]
    // Remaining: K♥ (higher than 10♥, lower than A♥). No remaining spades.
    // To set up: play all spades except A♠ in completed tricks.
    let completedTricks: [[(playerIndex: Int, card: Card)]] = [
        [(0,c("K","♠")),(1,c("Q","♠")),(2,c("J","♠")),(3,c("10","♠")),(4,c("9","♠")),(5,c("8","♠"))],
        [(0,c("7","♠")),(1,c("6","♠")),(2,c("5","♠")),(3,c("4","♠")),(4,c("3","♠")),(5,c("2","♠"))],
        [(0,c("A","♦")),(1,c("K","♦")),(2,c("Q","♦")),(3,c("J","♦")),(4,c("10","♦")),(5,c("9","♦"))],
        [(0,c("8","♦")),(1,c("7","♦")),(2,c("6","♦")),(3,c("5","♦")),(4,c("4","♦")),(5,c("3","♦"))],
        [(0,c("A","♣")),(1,c("K","♣")),(2,c("Q","♣")),(3,c("J","♣")),(4,c("10","♣")),(5,c("9","♣"))],
    ]
    // After these 5 tricks: remaining = K♥ + cards in other players' hands.
    // Simplify: just verify the bot does not choose 10♥.

    let result = lead(
        seat: 0,
        hand: hand,
        highBidderIndex: 0,
        actualPartners: [2, 4],
        revealedPartners: [2, 4],
        trumpSuit: .spades,
        completedTricks: completedTricks,
        wonPoints: [0, 0, 0, 0, 0, 0],
        highBid: 150,
        trickNumber: 5  // tricksRemaining=3 → endgame fires (new guard: hand.count<=3)
    )

    XCTAssertNotEqual(result, "10♥",
        "Bot with 3 cards should lead a winner (A♠ or A♥), not the loser 10♥; got \(result ?? "nil")")
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp && xcodebuild test \
  -project MyApp.xcodeproj -scheme MyApp \
  -destination "platform=iOS Simulator,id=DA97985A-F7CC-44F6-8281-9DD24C22B978" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:MyAppTests/AIEngineTests/test_endgameExtension_botLeadsWinnerNotLoserWith3Cards \
  2>&1 | grep -E "FAILED|PASSED|error:|Build succeeded|Build FAILED"
```

Expected: test fails (endgame fires only for `tricksRemaining <= 2`, not 3).

- [ ] **Step 3: Update the endgame gate in `computeCard`**

In `computeCard`, find the endgame call (~line 574):

```swift
if urgency.tricksRemaining <= 2,
   let endgameLead = computeEndgameLead(
```

Change `<= 2` to `<= 3`:

```swift
if urgency.tricksRemaining <= 3,
   let endgameLead = computeEndgameLead(
```

- [ ] **Step 4: Extend `computeEndgameLead` with 3-card projection**

In `computeEndgameLead` (~line 1328), make these two changes:

**4a.** Change the guard:
```swift
guard hand.count <= 2 else { return nil }
```
→
```swift
guard hand.count <= 3 else { return nil }
```

**4b.** Replace the `scored` block. The current block is:

```swift
let scored = hand.map { card -> (Card, Int) in
    var score = 0
    if likelyWinsAsLead(card) {
        score += card.pointValue * 10 + 50   // strong bonus: winning this trick
        // Two-trick sweep: if both cards in hand are winners, capture both
        if hand.count == 2, let other = hand.first(where: { $0.id != card.id }),
           likelyWinsAsLead(other) {
            score += other.pointValue * 8 + 25
        }
    } else {
        // Leading a loser cedes the trick; prefer the one that costs least
        score -= card.pointValue * 5
        // Higher-rank losers force opponents to spend high cards to beat them
        score += rankScore(card) / 2
    }
    return (card, score)
}
```

Replace with:

```swift
let scored = hand.map { card -> (Card, Int) in
    var score = 0
    if likelyWinsAsLead(card) {
        score += card.pointValue * 10 + 50
        if hand.count == 2 {
            // existing 2-card sweep bonus (unchanged)
            if let other = hand.first(where: { $0.id != card.id }),
               likelyWinsAsLead(other) {
                score += other.pointValue * 8 + 25
            }
        } else {
            // 3-card: project value of the remaining 2-card hand
            let remaining2 = hand.filter { $0.id != card.id }
            let wins = remaining2.filter { likelyWinsAsLead($0) }
            score += wins.map { $0.pointValue * 8 + 20 }.reduce(0, +)
        }
    } else {
        score -= card.pointValue * 5
        score += rankScore(card) / 2
    }
    return (card, score)
}
```

- [ ] **Step 5: Run all tests to verify they pass**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp && xcodebuild test \
  -project MyApp.xcodeproj -scheme MyApp \
  -destination "platform=iOS Simulator,id=DA97985A-F7CC-44F6-8281-9DD24C22B978" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO \
  2>&1 | grep -E "FAILED|PASSED|executed|Build succeeded|Build FAILED"
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp && git add MyApp/AIEngine.swift MyAppTests/AIEngineTests.swift && git commit -m "feat(ai): extend endgame exact calculation from 2 to 3 remaining tricks

computeEndgameLead now fires when hand.count<=3 (was <=2).
3-card path projects the value of the remaining 2-card hand after
leading each candidate, rewarding leads that set up future winners."
```

---

## Task 5: Bidder-Partner Coordination Post-Reveal

After the bidder's called partners reveal themselves, no logic directs the bidder toward their partners' actual probable holdings. This adds a `revealedPartnerIndices` parameter to `bestLeadCard` and scores non-trump leads by the partners' holding probability.

**Files:**
- Modify: `MyApp/AIEngine.swift`
- Test: `MyAppTests/AIEngineTests.swift`

- [ ] **Step 1: Write the failing test**

Add after the endgame test:

```swift
// MARK: - Bidder-Partner Coordination Post-Reveal

// Scenario: bidder (seat=0) with both partners revealed (seats 2 and 4).
// Choosing between Q♣ and Q♦. Partner (seat=2) led ♣ in a completed trick
// (lead boost → high prob of holding clubs). No ♦ leads by partners.
// Post-reveal coordination: Q♣ gets boost = Int(partnerStrength * 16) where
//   partnerStrength = max(threatProb(2,♣,-1), threatProb(4,♣,-1)) ≈ high for seat2.
// Q♦: partnerStrength for ♦ ≈ low (no ♦ lead history for partners).
// Expected: bot leads Q♣ (toward partner's known strength).
func test_postRevealCoordination_bidderLeadsTowardRevealedPartnerStrength() {
    // Seat=2 led clubs in a completed trick → high prob of holding remaining clubs.
    let completedTricks: [[(playerIndex: Int, card: Card)]] = [[
        (playerIndex: 2, card: c("K","♣")),  // partner led clubs (lead boost for ♣)
        (playerIndex: 3, card: c("3","♦")),
        (playerIndex: 4, card: c("4","♦")),
        (playerIndex: 5, card: c("5","♦")),
        (playerIndex: 0, card: c("6","♦")),
        (playerIndex: 1, card: c("7","♦")),
    ]]
    // Remaining clubs: A♣,J♣,10♣ (K♣ played). Remaining diamonds: many.
    // Hand: Q♣ and Q♦ — same rank, same point value.
    let hand = [c("Q","♣"), c("Q","♦")]

    let result = lead(
        seat: 0,
        hand: hand,
        highBidderIndex: 0,
        actualPartners: [2, 4],
        revealedPartners: [2, 4],   // both partners revealed
        trumpSuit: .spades,
        completedTricks: completedTricks,
        trickNumber: 1
    )

    XCTAssertEqual(result, "Q♣",
        "Bidder should lead toward partner(seat=2)'s known club strength; got \(result ?? "nil")")
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp && xcodebuild test \
  -project MyApp.xcodeproj -scheme MyApp \
  -destination "platform=iOS Simulator,id=DA97985A-F7CC-44F6-8281-9DD24C22B978" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO \
  -only-testing:MyAppTests/AIEngineTests/test_postRevealCoordination_bidderLeadsTowardRevealedPartnerStrength \
  2>&1 | grep -E "FAILED|PASSED|error:|Build succeeded|Build FAILED"
```

Expected: test fails.

- [ ] **Step 3: Add `revealedPartnerIndices` parameter to `bestLeadCard`**

Find the `bestLeadCard` function signature (~line 1079):

```swift
private static func bestLeadCard(
    hand: [Card],
    seat: Int,
    isKnownOffense: Bool,
    strategicOffenseSet: Set<Int>,
    highBidderIndex: Int,
    trumpRaw: String,
    unrevealedCalledCardIds: Set<String>,
    revealedPartnerCount: Int,
    remainingCards: [Card],
    knownVoids: [Int: Set<String>],
    urgency: Urgency,
    personality: BotPersonality,
    playerBidStrengths: [Int: Int] = [:],
    handModel: HandModel? = nil
) -> Card {
```

Add the new parameter with a default value:

```swift
private static func bestLeadCard(
    hand: [Card],
    seat: Int,
    isKnownOffense: Bool,
    strategicOffenseSet: Set<Int>,
    highBidderIndex: Int,
    trumpRaw: String,
    unrevealedCalledCardIds: Set<String>,
    revealedPartnerCount: Int,
    remainingCards: [Card],
    knownVoids: [Int: Set<String>],
    urgency: Urgency,
    personality: BotPersonality,
    playerBidStrengths: [Int: Int] = [:],
    handModel: HandModel? = nil,
    revealedPartnerIndices: Set<Int> = []   // ← ADD THIS
) -> Card {
```

- [ ] **Step 4: Pass `revealedPartnerIndices` from `computeCard`**

Find the `bestLeadCard(...)` call in `computeCard` (~line 585):

```swift
return bestLeadCard(
    hand: hand,
    seat: seat,
    isKnownOffense: isKnownOffense,
    strategicOffenseSet: strategicOffense,
    highBidderIndex: highBidderIndex,
    trumpRaw: trumpRaw,
    unrevealedCalledCardIds: unrevealedCalledCardIds,
    revealedPartnerCount: revealedPartnerIndices.count,
    remainingCards: remainingCards,
    knownVoids: knownVoids,
    urgency: urgency,
    personality: style,
    playerBidStrengths: playerBidStrengths,
    handModel: handModel
).id
```

Add `revealedPartnerIndices: revealedPartnerIndices`:

```swift
return bestLeadCard(
    hand: hand,
    seat: seat,
    isKnownOffense: isKnownOffense,
    strategicOffenseSet: strategicOffense,
    highBidderIndex: highBidderIndex,
    trumpRaw: trumpRaw,
    unrevealedCalledCardIds: unrevealedCalledCardIds,
    revealedPartnerCount: revealedPartnerIndices.count,
    remainingCards: remainingCards,
    knownVoids: knownVoids,
    urgency: urgency,
    personality: style,
    playerBidStrengths: playerBidStrengths,
    handModel: handModel,
    revealedPartnerIndices: revealedPartnerIndices   // ← ADD THIS
).id
```

- [ ] **Step 5: Add post-reveal coordination scoring block in `bestLeadCard`**

In `bestLeadCard`, in the non-trump scoring block, after the existing bidder called-suit probe:

```swift
if seat == highBidderIndex,
   revealedPartnerCount < 2,
   unrevealedCalledSuits.contains(card.suit) {
    score += 24 - card.pointValue
    if urgency.offense { score += 12 }
}
```

Add the post-reveal coordination block immediately after:

```swift
// Post-reveal coordination: bidder leads toward suit where revealed partners
// probably hold cards. Up to +16 (below trump-pull +30 and denial +20) so
// it's a preference, not an override.
if seat == highBidderIndex,
   !revealedPartnerIndices.isEmpty,
   let model = handModel,
   !isTrump {
    let partnerStrength = revealedPartnerIndices.reduce(0.0) { best, p in
        max(best, model.threatProb(player: p, suit: card.suit,
                                   beatingRankScore: -1))
    }
    score += Int(partnerStrength * 16)
}
```

- [ ] **Step 6: Run all tests to verify they pass**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp && xcodebuild test \
  -project MyApp.xcodeproj -scheme MyApp \
  -destination "platform=iOS Simulator,id=DA97985A-F7CC-44F6-8281-9DD24C22B978" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO \
  2>&1 | grep -E "FAILED|PASSED|executed|Build succeeded|Build FAILED"
```

Expected: all 26 tests pass (21 existing + 5 new).

- [ ] **Step 7: Commit**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp && git add MyApp/AIEngine.swift MyAppTests/AIEngineTests.swift && git commit -m "feat(ai): add bidder-partner coordination post-reveal

After called partners reveal, bidder gets up to +16 score boost for
leading suits where revealed partners probably hold cards. Uses HandModel
threatProb across all revealed partners, taking the strongest signal.
Scored below trump-pull and denial so it's a preference, not an override."
```

---

## Task 6: Build, Install, Smoke Test

- [ ] **Step 1: Full build**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp && xcodebuild \
  -quiet -project MyApp.xcodeproj -scheme MyApp -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO build \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Install and launch**

```bash
xcrun simctl install DA97985A-F7CC-44F6-8281-9DD24C22B978 \
  /Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Build/Products/Debug-iphonesimulator/MyApp.app && \
xcrun simctl launch DA97985A-F7CC-44F6-8281-9DD24C22B978 com.vijaygoyal.theshadyspade
```

Expected: PID printed, app launches.

- [ ] **Step 3: Update CLAUDE.md changelog**

Add a changelog entry under `## v2.0 Changelog` in `/Users/vijaygoyal/MyiOSApp/MyApp/CLAUDE.md`:

```
- [2026-06-06] Add 5 advanced AI improvements to AIEngine.swift — (1) **Safety plays:** `bidSecure: Bool` added to `Urgency` (fires when `offensePoints >= highBid`); risky trump leads get −12 when bid is secure and `higherTrumpRemaining >= 2`; `effectiveTrumpThreshold += 20` prevents burning trump on cheap tricks after bid is made. (2) **Finessing:** in `bestLeadCard` non-trump block, find nearest opponent 1–3 seats after the bot and use `HandModel.threatProb` to apply −8 when they probably hold a beating card (p>0.5) or +5 when they almost certainly don't (p<0.15). (3) **Discard signaling:** new `discardPreference(_:hand:remainingCards:)` private helper; when teammate is winning and bot can't feed points, replaces `lowestValueCard` discard with smart suit abandonment (prefers unestablishable suits, −20 guard on point cards). (4) **Endgame extension:** `computeEndgameLead` guard relaxed from `hand.count <= 2` to `<= 3`; 3-card path projects remaining 2-card hand value to reward leads that set up future winners. (5) **Post-reveal coordination:** `bestLeadCard` gains `revealedPartnerIndices: Set<Int> = []`; bidder scores non-trump leads by max `threatProb` across all revealed partners (up to +16). Reusable pattern: all improvements are isolated score adjustments inside `AIEngine`; no ViewModels changed. Verification: 26/26 XCTests pass (21 existing + 5 new); installed on simulator DA97985A; launched PID [update after run]. (`AIEngine.swift`, `AIEngineTests.swift`, `CLAUDE.md`)
```

- [ ] **Step 4: Update memory plan**

Mark this plan complete in the project memory file at:
`/Users/vijaygoyal/.claude/projects/-Users-vijaygoyal/memory/project_shadyspade_defect_report_v5.md` (or create a new memory entry summarising completion).

---

## Self-Review Checklist

**Spec coverage:**
- ✅ Safety plays: `bidSecure` field, Change A (trump lead penalty), Change B (ruff threshold)
- ✅ Finessing: nearest opponent 1–3 seats, `threatProb` gates, −8 / +5 adjustments
- ✅ Discard signaling: `discardPreference` helper, replaces `nonTrump.min` in teammateWinning+!canFeed
- ✅ Endgame extension: guard `<= 3`, 3-card projection with `likelyWinsAsLead`
- ✅ Post-reveal coordination: new param with default `[]`, call-site passthrough, up to +16

**No placeholders:** All steps contain complete code snippets.

**Type consistency:**
- `urgency.bidSecure` used in Task 1 matches the `Urgency` field added in Step 3.
- `discardPreference(_:hand:remainingCards:)` matches call site in Task 3 Step 4.
- `revealedPartnerIndices: Set<Int>` matches parameter name at call site.
- `handModel` is already `HandModel?` — the nil-gate `if let model = handModel` is consistent with Tasks 2 and 5.
