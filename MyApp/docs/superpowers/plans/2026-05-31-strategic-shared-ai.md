# 2026-05-31 Strategic Shared AI

## Goal
Improve bot play in the shared `AIEngine` so one AI change affects Solo, Online, and Bluetooth.

## Requested Changes
- Hidden-partner awareness: non-bidder bots must not use exact hidden partner identities before reveal.
- Overpaying fix: when taking a trick, play the lowest winning card.
- Seat-order awareness: account for players still waiting to act before feeding points.
- Card memory: use played cards to reason about remaining trump and high cards.
- Bot personalities: conservative, aggressive, point-feeder, trump-controller, risk-taker.
- Strategic urgency for both offense and defense based on bid, points remaining, and trick count.

## Root Cause
- `AIEngine.computeCard(...)` accepted a single exact `offenseSet`, so host-side bots could act with hidden partner knowledge before the public reveal.
- The follow-suit beat path selected the highest winning same-suit card, which spent more card strength than needed.
- Point feeding only checked whether a known teammate was currently winning; it did not evaluate future seats that could still beat or trump the trick.
- Card memory tracked only completed-trick voids. It did not use the full played-card set to reason about remaining high cards or trump.
- All bot seats used the same deterministic style, and urgency existed only for offense.

## Fix
- Added `AIEngine.BotPersonality` with deterministic seat assignment:
  - `conservative`
  - `aggressive`
  - `pointFeeder`
  - `trumpController`
  - `riskTaker`
- Added explicit visibility inputs to `AIEngine.computeCard(...)`:
  - `actualPartnerIndices`
  - `revealedPartnerIndices`
  - `calledCardIds`
- Added `AIEngine.revealedPartnerIndices(...)` so Solo can derive public partner reveal from called cards already played.
- Replaced omniscient `offenseSet` AI input in Solo, Online, and Bluetooth adapters.
- Hidden partner model:
  - bidder may use actual partner identities
  - revealed partners are public
  - a hidden partner bot knows only itself and the bidder if it still holds a called card
  - defense treats unrevealed partners as unknown until reveal
- Added unseen-card memory by subtracting the bot hand, current trick, and completed tricks from `AIEngine.fullDeck`.
- Added future-seat threat evaluation before point feeding:
  - future known opponents
  - known voids that can trump
  - remaining higher led-suit cards
  - remaining higher trump
- Changed trick-taking choices to the lowest winning card/trump.
- Added offense and defense urgency from known points, bid target, remaining points, and trick count.
- Applied personality to bidding, calling, trump leadership, trump-in thresholds, and point-feeding risk tolerance.

## Reusable Pattern
- `AIEngine` owns bot strategy.
- Mode view models must pass state and visibility, not strategy.
- Do not pass a single exact offense set to bot strategy; pass actual partners and revealed partners separately.
- If future AI behavior needs more context, extend `AIEngine` inputs once and update all three adapters together.

## Files Changed
- `MyApp/MyApp/AIEngine.swift`
- `MyApp/MyApp/ComputerGameViewModel.swift`
- `MyApp/MyApp/OnlineGameViewModel.swift`
- `MyApp/MyApp/BluetoothGameViewModel.swift`
- `MyApp/CLAUDE.md`
- `MyApp/docs/superpowers/plans/2026-05-31-strategic-shared-ai.md`

## Checklist
- [x] Add shared bot personality model.
- [x] Replace exact hidden-partner `offenseSet` input with visibility-aware inputs.
- [x] Update Solo adapter to derive revealed partners from played called cards.
- [x] Update Online adapter to pass host actual partners and public revealed partners.
- [x] Update Bluetooth adapter to pass host actual partners and public revealed partners.
- [x] Fix overpaying by choosing the lowest winning card/trump.
- [x] Add future-seat threat checks before feeding points.
- [x] Add card memory from unseen remaining cards.
- [x] Add offense and defense urgency.
- [x] Run signed simulator Debug build.
- [x] Install and launch simulator build.

## Verification
- Signed simulator Debug build succeeded:

```sh
xcodebuild -project MyApp/MyApp.xcodeproj -scheme MyApp -destination id=D6EB3CD2-618C-4B60-A6F5-7A9DA65CFE8F -configuration Debug -derivedDataPath /private/tmp/ShadySpadeSignedDerivedData COMPILER_INDEX_STORE_ENABLE=NO build
```

- Installed and launched on iPhone 17 Pro simulator `D6EB3CD2-618C-4B60-A6F5-7A9DA65CFE8F`.
- Launch PID: `45906`.

## Manual Tuning Notes
- Play several Solo rounds and watch whether point-feeding is too conservative after the future-seat risk check.
- Observe whether `riskTaker` over-trumps too often because its trump-in threshold is intentionally low.
- Observe whether hidden partners play plausibly before reveal: they should know themselves if holding a called card, but should not know the other hidden partner unless public.
