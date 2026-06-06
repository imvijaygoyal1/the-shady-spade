# AI Improvement: Defense Point Denial

**Date:** 2026-06-06
**Scope:** `AIEngine.swift` only — `Urgency` struct, `urgencyState`, `computeCard` following path, `bestLeadCard`
**Applies to:** Defense bots only (`!isKnownOffense`), all game modes

---

## Problem

Defense bots have no explicit "block" mode when the bidder is close to making their bid.
`defenseUrgent` only fires when defense is behind on *their own* target (251 − highBid).
A bidder at 130/150 — one good trick away — is not caught by any existing condition, so
defense bots continue playing passively: feeding points to teammates, leading safe low
cards, never taking tricks aggressively to accumulate points before offense reaches their
target.

---

## Approach

Add `bidderCloseToWin: Bool` to the existing private `Urgency` struct. Compute it in
`urgencyState` from two conditions (A OR B). Use it in two consumers:
1. `computeCard` following path — suppress point feeding entirely
2. `bestLeadCard` — boost confirmed-winner leads

All changes are internal to `AIEngine`. No signature changes on `computeCard` or any
caller.

---

## Design

### 1. `bidderCloseToWin` in `Urgency` + `urgencyState`

**Struct change:**

```swift
private struct Urgency {
    let offense: Bool
    let defense: Bool
    let offensePoints: Int
    let defensePoints: Int
    let remainingPoints: Int
    let tricksRemaining: Int
    let bidderCloseToWin: Bool   // new field
    var eitherSide: Bool { offense || defense }
}
```

**Computation in `urgencyState`** (after existing offense/defense urgent calculations):

```swift
let bidderCloseToWin = remainingPoints > 0
    && ((Double(offensePoints) >= Double(highBid) * 0.75
         && offenseShortfall <= remainingPoints / 2)
        || (offenseShortfall <= remainingPoints && remainingPoints < 30))
```

**Condition A** — bidder has captured ≥ 75% of bid AND needs ≤ half of remaining points.
Offense is well advanced; a single high-value trick could seal the bid.

**Condition B** — late-game denial: fewer than 30 points remain unplayed AND offense can
still complete their bid from those points alone. Pure "deny now or lose" territory.

`bidderCloseToWin` is a game-state property — both offense and defense bots can read it,
but consumers gate on `!isKnownOffense` before acting on it.

---

### 2. Following Path — Suppress Point Feeding

**Location:** `computeCard`, immediately before the `canFeedPoints` assignment.

**Current:**
```swift
let canFeedPoints = futureThreats <= adaptedFeedTolerance
    || (isKnownOffense && urgency.offense)
    || (!isKnownOffense && urgency.defense)
```

**New:**
```swift
let canFeedPoints = (!isKnownOffense && urgency.bidderCloseToWin)
    ? false
    : (futureThreats <= adaptedFeedTolerance
       || (isKnownOffense && urgency.offense)
       || (!isKnownOffense && urgency.defense))
```

**Effect:** defense bots in denial mode always play their lowest-value card when a
teammate is winning the trick, rather than feeding high-point cards. Point cards stay
out of the trick pool and are not captured by offense when they win later tricks.

The override fires only for defense (`!isKnownOffense`) and only when `bidderCloseToWin`.
All other `canFeedPoints` logic is unchanged.

---

### 3. `bestLeadCard` — Boost Trick-Winning Leads

**Location:** inside the `scored = hand.map { card -> (Card, Int) in ... }` block, after
all existing per-card scoring, before the `return (card, score)` line.

```swift
if !isKnownOffense && urgency.bidderCloseToWin {
    if !isTrump && higherRemaining == 0 { score += 20 }
    if isTrump && higherTrumpRemaining == 0 { score += 15 }
}
```

**Effect:**
- Non-trump confirmed winners (`higherRemaining == 0`) get `+20`. Defense leads
  established suit winners aggressively to accumulate trick points.
- Top trump (`higherTrumpRemaining == 0`) gets `+15`. Defense's highest trump is played
  assertively to capture trick points.

**Weight rationale:** `+20` and `+15` exceed typical positive scoring signals (largest
non-denial bonus is establishment at `+12`, trump at `+18` for high-rank trump). They
are deliberately larger to override passive play in denial mode. They do NOT override:
- 3♠ protection penalty (−28) — always preserved
- Trump exhaustion logic — correct regardless of denial mode
- Urgency-based trump bias (`+8`) — already applied; denial adds on top

---

## What Does Not Change

- `computeCard` public signature — no new parameters, all callers unchanged
- Offense bot behaviour — `bidderCloseToWin` is read-only for offense consumers
- `eitherSide` computed property — unchanged; denial mode is separate from offense/defense urgency
- `HandModel`, establishment, trump pull, partner reveal, 3♠ logic — all unchanged

---

## Testing

New XCTest cases in `AIEngineTests.swift`:

1. **`bidderCloseToWin` fires on condition A** — offense at 75%+ of bid with shortfall ≤
   remaining/2 → verify `urgencyState` produces `bidderCloseToWin = true` via an
   end-to-end `computeCard` call where the behaviour change is observable.

2. **`bidderCloseToWin` does not fire for offense bots** — same game state, but bot
   is on the bidding team → denial mode must not alter offense play.

3. **Following path suppresses point feeding** — defense bot following teammate's winning
   trick in denial mode must discard lowest-value card even when future threats are low.

4. **`bestLeadCard` boosts confirmed winner in denial mode** — defense bot with an
   established winner leads it over a safer low card when `bidderCloseToWin`.

Build + simulator install + launch after implementation per standard pattern.
