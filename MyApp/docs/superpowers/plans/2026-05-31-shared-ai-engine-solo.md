# 2026-05-31 Shared AIEngine For Solo Bots

## Goal
Refactor Solo bots to use the same AI decision engine as Online and Bluetooth, so one future AI strategy change applies everywhere.

## Symptom / Motivation
- Online and Bluetooth bot decisions already used `AIEngine`.
- Solo bot decisions were duplicated inside `ComputerGameViewModel`:
  - bidding heuristic
  - AI trump/called-card selection
  - AI card-play heuristic
- Any future tuning in `AIEngine` would improve Online/BT but leave Solo unchanged.

## Root Cause
- `ComputerGameViewModel` predated or bypassed the shared engine and carried local copies of the AI heuristics.
- `AIEngine` file comment described it as Online/BT only, reinforcing the split ownership.
- Solo also had its own deck builder, even though the deck definition was identical to `AIEngine.fullDeck`.

## Fix
- Updated `AIEngine` documentation to make it the shared engine for Solo, Online, and Bluetooth.
- `ComputerGameViewModel.freshDeck()` now returns `AIEngine.fullDeck`.
- Replaced Solo local bidding heuristic with:
  - `AIEngine.computeBid(...)`
- Replaced Solo local AI calling heuristic with:
  - `AIEngine.computeCalling(...)`
  - a small local card-ID splitter to apply returned card IDs to Solo's `calledCard1Rank/Suit` and `calledCard2Rank/Suit` state.
- Replaced Solo local AI card-play heuristic with:
  - `AIEngine.computeCard(...)`
  - a small local adapter that converts Solo `wonTricks` into `wonPointsPerPlayer` and maps returned card IDs back to `Card`.
- Kept Solo-specific behavior in `ComputerGameViewModel`:
  - async sleep/timing
  - pass-and-play device handoff
  - UI messages
  - partner reveal banner state
  - cancellation guards

## Additional Correctness Fix
- While refactoring, found that `AIEngine.computeCard` identified the current trick winner with a local comparator.
- That comparator could treat an off-suit non-trump card as winning when no trump had been played.
- Solo's previous local `trickWinner(...)` did not have that issue.
- Fixed `AIEngine.computeCard` to call `trickWinnerIndex(trick:trumpSuit:)` and then resolve the winning entry from `currentTrick`.
- This prevents the refactor from making Solo's mid-trick teammate/opponent-winning read worse and improves Online/BT as well.

## Reusable Pattern
- Future bot strategy changes belong in `AIEngine`.
- Mode-specific view models should not duplicate strategy heuristics.
- Mode-specific view models may adapt state into `AIEngine` inputs and apply the returned action.
- Keep UI timing, network synchronization, retries, and local state mutation outside `AIEngine`.
- If a future strategy needs more context, add parameters to `AIEngine` and update all mode adapters together.

## Files Changed
- `MyApp/MyApp/AIEngine.swift`
- `MyApp/MyApp/ComputerGameViewModel.swift`
- `MyApp/CLAUDE.md`
- `MyApp/docs/superpowers/plans/2026-05-31-shared-ai-engine-solo.md`

## Checklist
- [x] Confirm Online/BT already use `AIEngine`.
- [x] Replace Solo local AI bid heuristic with `AIEngine.computeBid`.
- [x] Replace Solo local AI calling heuristic with `AIEngine.computeCalling`.
- [x] Replace Solo local AI card-play heuristic with `AIEngine.computeCard`.
- [x] Keep Solo mode-specific async/UI behavior outside `AIEngine`.
- [x] Fix shared current-trick winner detection found during refactor.
- [x] Document the new shared-AI pattern.
- [x] Run signed simulator build verification.
- [x] Install and launch simulator build.

## Verification Plan
Run a signed simulator Debug build:

```sh
xcodebuild -project MyApp/MyApp.xcodeproj -scheme MyApp -destination id=<SIMULATOR_ID> -configuration Debug -derivedDataPath /private/tmp/ShadySpadeSignedDerivedData COMPILER_INDEX_STORE_ENABLE=NO build
```

Install and launch:

```sh
xcrun simctl install <SIMULATOR_ID> /private/tmp/ShadySpadeSignedDerivedData/Build/Products/Debug-iphonesimulator/MyApp.app
xcrun simctl launch <SIMULATOR_ID> com.vijaygoyal.theshadyspade
```

Manual check:
- Start a Solo game.
- Let AI players bid, call, and play cards.
- Confirm game proceeds through bidding, calling, playing, and round-complete without AI freeze.
- Future strategy edits should now be made in `AIEngine`.

## Verification Result
- Signed simulator Debug build succeeded with:

```sh
xcodebuild -project MyApp/MyApp.xcodeproj -scheme MyApp -destination id=D6EB3CD2-618C-4B60-A6F5-7A9DA65CFE8F -configuration Debug -derivedDataPath /private/tmp/ShadySpadeSignedDerivedData COMPILER_INDEX_STORE_ENABLE=NO build
```

- Installed and launched on iPhone 17 Pro simulator `D6EB3CD2-618C-4B60-A6F5-7A9DA65CFE8F`.
- Launch PID: `44149`.
- Full manual Solo game flow still should be played through to confirm the shared engine drives bidding, calling, and card play end-to-end on-device.
