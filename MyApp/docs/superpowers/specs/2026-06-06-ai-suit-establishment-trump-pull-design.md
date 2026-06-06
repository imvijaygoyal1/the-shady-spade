# AI Improvements: Long Suit Establishment & Trump Pull

**Date:** 2026-06-06
**Scope:** `AIEngine.swift` — `bestLeadCard` only
**Applies to:** All bot personalities, all game modes (Solo, Online, Bluetooth)

---

## Problem

`bestLeadCard` penalises cards in suits where higher cards remain, but never rewards the
strategy of building a suit by leading it repeatedly. This causes two observable gaps:

1. **Long suit establishment:** A bot holding 10♥,8♥,7♥,5♥ avoids leading hearts because
   higher cards exist, even though leading hearts repeatedly would exhaust A♥,K♥,Q♥,J♥
   and turn the 10♥ into a winner.

2. **Trump pull:** A bidder holding established non-trump winners (A♥, K♥, A♦) never
   deliberately leads trump to exhaust opponents' ruffs before running those winners.
   Opponents can ruff what should be clean trick captures.

---

## Approach

Both improvements use **additive score bonuses inside `bestLeadCard`** — the same pattern
as every existing heuristic in the function. No structural changes to `AIEngine`, no new
parameters, no new callers to update.

---

## Design

### 1. Long Suit Establishment Bonus

**Location:** inside the non-trump `else` block in `bestLeadCard`, immediately after the
existing `higherRemaining` penalty line.

**Logic:** When the bot holds more cards in a suit than there are higher cards remaining,
it has positive establishment potential — those lower cards become winners once the higher
ones fall. The bonus fires only when there are enough tricks left to actually exhaust the
blocking cards.

```swift
let suitLength = hand.filter { $0.suit == card.suit }.count
if higherRemaining > 0 {
    let establishmentPotential = suitLength - higherRemaining
    if establishmentPotential > 0 && urgency.tricksRemaining >= higherRemaining + 1 {
        score += establishmentPotential * 6
    }
}
```

**Gate conditions:**
- `higherRemaining > 0` — only needed when there ARE blocking cards (the existing `+18`
  already handles the case where none remain)
- `establishmentPotential > 0` — bot holds more cards than blockers
- `urgency.tricksRemaining >= higherRemaining + 1` — enough tricks to exhaust blockers
  and cash at least one winner

**Weight:** `+6` per net card of advantage. With 2 net cards and 5 tricks remaining,
bonus is +12 — enough to overcome a 2-card penalty but not so large it overrides urgency
or void-ruff risk signals.

**Example:** Bot holds 10♥,8♥,7♥,5♥ (length 4). A♥,K♥ still out (higherRemaining 2).
Potential = 4−2 = 2. Tricks remaining = 6 ≥ 3. Bonus = +12. Bot correctly sees hearts
as worth leading to establish the 10♥ and 8♥.

---

### 2. Trump Pull Bonus

**Location:** Two additions to `bestLeadCard`.

**Pre-loop computation** (before `let scored = hand.map ...`):

```swift
let establishedNonTrumpWinners = hand.filter { card in
    guard card.suit != trumpRaw else { return false }
    let higher = remainingCards.filter {
        $0.suit == card.suit && rankScore($0) > rankScore(card)
    }.count
    return higher == 0 && hand.filter { $0.suit == card.suit }.count >= 2
}.count
let trumpPullBonus = isKnownOffense
    && !trumpExhausted
    && urgency.tricksRemaining >= 5
    && establishedNonTrumpWinners >= 2
    ? establishedNonTrumpWinners * 10 : 0
```

**Inside the trump scoring block:**

```swift
score += trumpPullBonus
```

**Gate conditions:**
- `isKnownOffense` — only the bidding team pulls trump; defense wants to preserve ruffs
- `!trumpExhausted` — no point pulling what's already gone
- `urgency.tricksRemaining >= 5` — only in tricks 1–4 (trickNumber ≤ 3); after that urgency takes over
- `establishedNonTrumpWinners >= 2` — needs at least 2 winners worth protecting

**Weight:** `+10` per established winner. Two winners → +20, four winners → +40. Enough
to tip trump leads ahead of suit leads without overriding urgency signals (which already
add their own +8 via `dynamicTrumpBias`).

**Automatic turn-off:** once `trumpExhausted` is true or `tricksRemaining < 5`, the
bonus is 0 and normal scoring resumes.

**Example:** Bidder holds A♠(trump), K♠, plus A♥,K♥ (established, length 2 each).
`establishedNonTrumpWinners = 4`. Trump pull bonus = +40. Bot leads A♠ then K♠ to clear
ruffs, then runs hearts cleanly.

---

## What Does Not Change

- Bot personalities — improvements apply uniformly; personality weights still modulate
  the final score but do not gate these bonuses
- All existing heuristics — 3♠ strategy, over-ruffing check, trump exhaustion bonus,
  void-ruff risk, urgency boosts, partner reveal intent — unchanged
- All callers (`ComputerGameViewModel`, `OnlineGameViewModel`, `BluetoothGameViewModel`)
  — no signature changes

---

## Testing

1. Build passes (`xcodebuild` + `xcrun swiftc -parse`)
2. Simulator install + launch confirms no crash
3. Manual Solo game: observe bot leading a long suit in mid-game after higher cards fall
4. Manual Solo game: observe bidder leading trump before running established side-suit winners
