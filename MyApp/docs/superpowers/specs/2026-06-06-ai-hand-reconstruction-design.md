# AI Improvement: Per-Player Hand Reconstruction

**Date:** 2026-06-06
**Scope:** `AIEngine.swift` only — new private `HandModel` struct + two updated consumers
**Applies to:** All bot personalities, all game modes (Solo, Online, Bluetooth)

---

## Problem

`futureOpponentThreatCount` and `bestLeadCard`'s void-risk scoring both treat remaining
cards as uniformly distributed across all players. A remaining A♠ is treated as an
equal threat from every future opponent — even if bid history, lead patterns, and void
inference strongly suggest it's held by one specific player. This causes bots to:

- Over-fear threats from players who almost certainly don't hold the dangerous card
- Under-weight threats from players who almost certainly do
- Apply binary void risk (confirmed void only) when probabilistic void estimation is
  available from card distribution

---

## Approach

Add a private `HandModel` struct inside `AIEngine`. Built once per `computeCard` call
from existing inputs (remaining cards, known voids, completed tricks, bid strengths).
Queried by two consumers that gain per-player precision without new external parameters.

All changes are internal to `AIEngine`. No signature changes on `computeCard` or any
caller (ViewModels unchanged).

---

## Design

### 1. HandModel Struct

New private struct inside `AIEngine`. Stateless — rebuilt each `computeCard` call.
48 cards × 6 players = 288 entries; build cost is negligible.

```swift
private struct HandModel {
    private let prob: [String: [Int: Double]]
    // prob[cardId][playerIndex] → probability (0–1) that player holds this card

    func threatProb(player: Int, suit: String, beatingRankScore: Int) -> Double
    func voidProb(player: Int, suit: String) -> Double

    static func build(
        seat: Int,
        remainingCards: [Card],
        knownVoids: [Int: Set<String>],
        completedTricks: [[(playerIndex: Int, card: Card)]],
        playerBidStrengths: [Int: Int]
    ) -> HandModel
}
```

**`threatProb(player:suit:beatingRankScore:)`**
Returns the summed probability that `player` holds any card in `suit` with
`rankScore > beatingRankScore`. Pass `beatingRankScore: -1` to get probability of
holding any card in the suit.

**`voidProb(player:suit:)`**
Returns `1 - sum(prob[C][player] for all remaining C in suit)`. A confirmed void
(from `knownVoids`) produces prob ≈ 1.0; an inferred void from distribution produces
a value in 0–1.

**Build algorithm — for each remaining card C:**

1. **Eligible holders** = all players in `0..<6` except `seat` (the bot's own index),
   further excluding any player with a confirmed void in C's suit via `knownVoids`.
   Players with confirmed void get weight 0 and are excluded from normalization.

2. **Base weight** `1.0` per eligible holder

3. **Bid boost** — applied only for high-value cards (pointValue ≥ 10 or rankScore ≥ 9):
   `weight[P] *= 1 + (bidStrength[P] / 5.0) * 0.5`
   Range: 1.0 (bid=0) to 1.5 (bid=5). Strong bidders 50% more likely to hold top cards.

4. **Lead boost** — if player P has led C's suit in any completed trick:
   `weight[P] *= 1.5`
   Leading a suit is the strongest public signal of holdings in that suit.

5. **Normalize** — `prob[C][P] = weight[P] / sum(weight[Q] for all eligible Q)`
   All probabilities for card C sum to 1.0 across eligible holders.

---

### 2. Updated `futureOpponentThreatCount`

**Location:** `AIEngine.futureOpponentThreatCount`

**Change:** Add `handModel: HandModel` parameter. Replace flat remaining-card logic
with per-player probability queries.

**New logic per future opponent `player`:**

```
if winnerCard is trump:
    p = handModel.threatProb(player, suit: trumpRaw, beatingRankScore: rankScore(winnerCard))

else (winnerCard is non-trump):
    ledThreat = handModel.threatProb(player, suit: ledSuit, beatingRankScore: rankScore(winnerCard))
    ruffThreat = handModel.voidProb(player, suit: ledSuit)
              * handModel.threatProb(player, suit: trumpRaw, beatingRankScore: -1)
    p = max(ledThreat, ruffThreat)

risk += p > 0.5 ? 2 : p > 0.2 ? 1 : 0
```

Return type stays `Int`. `canFeedPoints` / `adaptedFeedTolerance` unchanged.

**Threshold rationale:**
- > 0.5: likely threat → +2 (same weight as current confirmed-card threat)
- 0.2–0.5: possible threat → +1 (new: captures probable-but-unconfirmed dangers)
- < 0.2: unlikely → 0 (same as current "card not in remaining pool")

---

### 3. Updated `bestLeadCard` — futureVoidRisk

**Location:** `AIEngine.bestLeadCard`

**Change:** Add `handModel: HandModel` parameter. Replace binary `knownVoids` check
with probability-weighted sum.

**Current:**
```swift
let futureVoidRisk = (0..<6).filter {
    strategicOffenseSet.contains($0) != isKnownOffense
        && knownVoids[$0]?.contains(card.suit) == true
}.count
```

**New:**
```swift
let futureVoidRisk = Int((0..<6).filter { p in
    strategicOffenseSet.contains(p) != isKnownOffense
}.reduce(0.0) { risk, p in
    let vp = handModel.voidProb(player: p, suit: card.suit)
    return risk + (vp > 0.7 ? 1.0 : vp > 0.3 ? 0.5 : 0.0)
}.rounded())
```

**Threshold rationale:**
- > 0.7: almost certainly void → full +1 (includes confirmed voids from knownVoids, which
  produce prob ≈ 1.0 since eligible holders exclude void players)
- 0.3–0.7: probably void (e.g. played few cards in suit, strong bidder in other suits) → +0.5
- < 0.3: unlikely void → 0

`futureVoidRisk` remains `Int`, `score -= futureVoidRisk * voidRiskMultiplier` unchanged.

---

### 4. Wiring in `computeCard`

Build `HandModel` once, immediately after `knownVoids` and `remainingCards` are computed:

```swift
let handModel = HandModel.build(
    seat: seat,
    remainingCards: remainingCards,
    knownVoids: knownVoids,
    completedTricks: completedTricks,
    playerBidStrengths: playerBidStrengths
)
```

Pass to `futureOpponentThreatCount` (following path) and `bestLeadCard` (leading path).

---

## What Does Not Change

- `computeCard` public signature — no new parameters, all callers unchanged
- `inferTeamRead` — existing behavioral scoring unchanged (out of scope)
- All urgency, personality, endgame, trump pull, establishment, 3♠, partner reveal logic
- All ViewModels (`ComputerGameViewModel`, `OnlineGameViewModel`, `BluetoothGameViewModel`)

---

## Testing

New XCTest cases in `AIEngineTests.swift`:

1. **`HandModel.voidProb` returns ~1.0 for confirmed void** — player with knownVoid in ♥
   should get voidProb ≈ 1.0 for any ♥ card.

2. **`HandModel.threatProb` respects bid boost** — with two eligible holders, strong
   bidder should get higher probability on a high-value card than weak bidder.

3. **`HandModel.threatProb` respects lead boost** — player who led ♥ in a completed
   trick should get higher probability on remaining ♥ cards.

4. **`futureOpponentThreatCount` precision** — scenario where only one future opponent
   could plausibly hold the dangerous card (bid strength + lead history concentrates
   probability) should return lower total threat than the flat model would.

5. **`bestLeadCard` probabilistic void risk** — bot avoids leading into a suit where
   an opponent's distribution (not yet a confirmed void) strongly suggests void.

Build + simulator install + launch after implementation as per standard pattern.
