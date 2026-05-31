# 2026-05-31 Intent-Based Bot Play

## Goal
Improve shared bot behavior in `AIEngine` so Solo, Online, and Bluetooth all get more realistic strategy from one implementation. Implement all requested analysis items except Human Mistakes/random misplays.

## Requested Scope
- Partner Reveal Intent: hidden partners should reveal only when it helps win, feed, or coordinate.
- Probabilistic Card Reading: bots should reason from played cards and remaining high cards/trump.
- Better Team Inference: bots should infer likely partners from public table behavior, not exact hidden identity.
- Strategic Partner Behavior: revealed/known teammates should feed or support based on urgency and future-seat risk.
- Bidder Strategy: bidder should make plays that help locate or coordinate with called-card partners.
- Excluded: Human Mistakes/random intentional bad plays.

## Root Cause
- The shared AI already separated actual partners from revealed partners, but it still had no explicit reveal-intent layer.
- Team awareness was mostly hard knowledge: bidder, revealed partners, and self-knowledge when holding a called card.
- The bidder did not bias leads toward unrevealed called-card suits, so partner discovery was incidental.
- Future-seat risk was coarse and did not weight how many high cards/trump could still beat the current winner.
- Card memory existed as unseen cards and voids, but lead and feed choices did not use enough of that pressure.

## Fix
- Added `PartnerRevealIntent` with `stayHidden`, `revealToWin`, `revealToFeed`, and `revealToCoordinate`.
- Added `hiddenPartnerRevealCard(...)` so a hidden partner can reveal by playing a called card only when legal and strategically useful.
- Added `TeamRead` and `inferTeamRead(...)` to score suspected offense from public actions:
  - feeding points into known offense
  - low trump used to protect a trick from defense
  - points contributed to tricks won by known offense
  - high accumulated won points
- Added `playedCalledCardIds(...)` so the engine can distinguish unplayed called cards from already revealed called cards.
- Added bidder lead bias toward suits of unrevealed called cards while fewer than two partners are revealed.
- Added stronger remaining-card pressure:
  - lead trump is boosted when no higher trump remains
  - lead trump is penalized when several higher trump remain
  - future opponent threat returns weighted risk from known voids, higher led-suit cards, and higher trump.
- Kept the behavior deterministic and strategic. No random Human Mistakes were added.

## Reusable Pattern
- `AIEngine` owns all bot strategy, including intent, team inference, card memory, urgency, and personalities.
- Mode view models should keep passing state and visibility into `AIEngine`; they should not duplicate strategy.
- Future bot tuning should change the shared helper functions in `AIEngine`:
  - `partnerRevealIntent(...)`
  - `inferTeamRead(...)`
  - `bestLeadCard(...)`
  - `futureOpponentThreatCount(...)`
- Keep exact hidden-partner identity out of non-bidder decisions unless that bot is the actual partner holding or revealing a called card.

## Files Changed
- `MyApp/MyApp/AIEngine.swift`
- `MyApp/CLAUDE.md`
- `MyApp/docs/superpowers/plans/2026-05-31-intent-based-bot-play.md`

## Checklist
- [x] Add explicit partner reveal intent.
- [x] Add behavior-based suspected-team inference.
- [x] Improve card-memory pressure from remaining high cards/trump.
- [x] Add bidder partner-finding lead bias.
- [x] Add weighted future-seat threat scoring.
- [x] Exclude Human Mistakes/random misplays.
- [x] Run signed simulator Debug build.
- [x] Install and launch simulator build.
- [x] Update `CLAUDE.md`.

## Verification
Signed simulator Debug build succeeded:

```sh
xcodebuild -project MyApp/MyApp.xcodeproj -scheme MyApp -destination id=D6EB3CD2-618C-4B60-A6F5-7A9DA65CFE8F -configuration Debug -derivedDataPath /private/tmp/ShadySpadeSignedDerivedData COMPILER_INDEX_STORE_ENABLE=NO build
```

Installed and launched on iPhone 17 Pro simulator `D6EB3CD2-618C-4B60-A6F5-7A9DA65CFE8F`.

Launch PID: `49540`.

## Manual Tuning Notes
- Watch whether hidden partners reveal too early on late tricks. If yes, raise the `lateRound` threshold in `partnerRevealIntent(...)`.
- Watch whether bidder called-suit leads happen too often with low-value dead suits. If yes, reduce the `24 - card.pointValue` boost in `bestLeadCard(...)`.
- Watch whether suspected-team inference becomes too trusting after one point feed. If yes, raise the suspected-offense threshold above `4` in `inferTeamRead(...)`.
- Watch whether point feeding is too conservative after weighted threat scoring. If yes, tune `unsafeFeedTolerance` per `BotPersonality`.
