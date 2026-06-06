# AI Advanced Improvements: 5 Enhancements

**Date:** 2026-06-06
**Scope:** `AIEngine.swift` only — additive changes, no structural modifications
**Applies to:** All game modes (Solo, Online, Bluetooth)

---

## Overview

Five independent improvements, all score-level or path-level changes to `AIEngine`.
None interact with each other. Implemented in one pass.

---

## 1. Safety Plays When Bid Is Secure

**Problem:** Offense bots keep burning trump and taking risks after they've already
made their bid (`offensePoints >= highBid`). No "protect the lead" mode exists.

**New field in `Urgency`:**
```swift
let bidSecure: Bool   // offensePoints >= highBid
```
Computed in `urgencyState`: `let bidSecure = offensePoints >= highBid`
Added to the `Urgency(...)` initialiser alongside existing fields.

**Change A — `bestLeadCard` trump block:**
When bid is secure, avoid burning high trump on risky leads:
```swift
if isKnownOffense && urgency.bidSecure && higherTrumpRemaining >= 2 { score -= 12 }
```

**Change B — can't-follow ruffing decision:**
Raise effective trump threshold so offense only ruffs very high-value tricks:
```swift
if isKnownOffense && urgency.bidSecure { effectiveTrumpThreshold += 20 }
```
Applied before the existing `shouldTrump` guard, after the `threeSpadeStillOut` adjustment.

---

## 2. Finessing

**Problem:** `bestLeadCard` penalises leads where higher cards remain, but treats all
remaining cards as equally dangerous regardless of which seat holds them. A higher card
held by the player immediately after the bot is far more dangerous than one held 4 seats
away.

**Location:** `bestLeadCard`, non-trump scoring block, after the existing
`higherRemaining` penalty line.

```swift
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

**Logic:** finds the nearest opponent sitting 1–3 seats after the bot. If that player
probably holds a beating card (prob > 0.5): anti-finesse penalty −8. If they almost
certainly don't (prob < 0.15): the lead is safer than raw `higherRemaining` suggests,
bonus +5.

**Gate:** `handModel` is optional with default `nil` in `bestLeadCard`; the block is
skipped when no model is available (e.g. future unit tests without a trick context).

---

## 3. Discard Signaling

**Problem:** in the can't-follow path when `teammateWinning && !canFeedPoints`, bots
pick `lowestValueCard(nonTrump)` — lowest points then lowest rank — ignoring whether the
discarded suit is one the bot can still win or one it should abandon.

**New private helper:**
```swift
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

**Location:** can't-follow path, replacing the existing `nonTrump.min(by: valueScore)`
discard when `teammateWinning && !canFeedPoints`:

```swift
if let discard = nonTrump.max(by: {
    discardPreference($0, hand: hand, remainingCards: remainingCards)
        < discardPreference($1, hand: hand, remainingCards: remainingCards)
}) {
    return discard.id
}
```

**Effect:** bots discard from suits they can't establish (implicit "don't lead this
back" signal) while keeping suits where they hold winners. Point cards remain protected
by the −20 guard. Rank breaks ties within the chosen suit.

---

## 4. Endgame Extension to 3 Tricks

**Problem:** `computeEndgameLead` is gated by `hand.count <= 2`, so bots use heuristic
scoring in trick 6 (3 cards remaining) when near-exact calculation is available.

**Change:** relax the guard to `hand.count <= 3` and add 3-card projection logic:

```swift
guard hand.count <= 3 else { return nil }  // was: <= 2

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

The 2-card path is unchanged. `likelyWinsAsLead` is the existing binary check (no
higher card remains, or trump is exhausted for non-trump suits). The 3-card projection
assumes remaining cards play out independently — a reasonable approximation for
endgame planning.

---

## 5. Bidder-Partner Coordination Post-Reveal

**Problem:** once the bidder's called partners reveal themselves, the existing
called-suit probe (`revealedPartnerCount < 2`) fires less. No replacement strategy
directs the bidder toward their partner's actual probable holdings.

**Signature change:** `bestLeadCard` gains one new parameter:
```swift
revealedPartnerIndices: Set<Int> = []
```
The call site in `computeCard` passes `revealedPartnerIndices: revealedPartnerIndices`.
`revealedPartnerCount` remains for the existing probe logic (unchanged).

**Location:** `bestLeadCard`, non-trump scoring block, after the existing
bidder called-suit probe block.

```swift
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

**Logic:** for each non-trump card, computes the highest `threatProb` (prob of holding
any card in that suit) across all revealed partners. Adds up to +16 when partner almost
certainly holds cards in the suit. Bidder leads toward partner's known strength so the
partner can win tricks and collect points.

**Weight rationale:** +16 max keeps this below trump-pull (+30) and denial (+20) —
coordination is a preference, not an override. The existing called-suit probe
(`+24 − card.pointValue`) still fires for unrevealed partners and scores higher.

---

## What Does Not Change

- `computeCard` public signature — no new parameters
- All ViewModels — no changes
- HandModel, establishment, trump pull, partner reveal, 3♠ logic — unchanged
- `bidderCloseToWin`, `defenseUrgent`, `offenseUrgent` — unchanged

---

## Testing

New XCTest cases in `AIEngineTests.swift`:

1. **Safety plays:** offense bot at `offensePoints >= highBid` avoids leading risky
   trump (higher trump remaining) — leads non-trump winner instead.

2. **Finessing:** bot avoids leading into nearest opponent who probably holds the
   beating card; prefers lead where nearest opponent has low probability.

3. **Discard signaling:** bot discards from unestablishable suit over established suit
   when forced to discard (teammate winning, can't follow, can't feed).

4. **Endgame 3-trick:** bot with 3 cards correctly plans lead order (leads confirmed
   winner first) rather than defaulting to heuristic scoring.

5. **Post-reveal coordination:** bidder with revealed partner boosts lead in suit where
   partner probably holds cards.

Build + simulator install + launch after implementation per standard pattern.
