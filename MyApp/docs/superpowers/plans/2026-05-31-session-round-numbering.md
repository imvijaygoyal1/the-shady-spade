# 2026-05-31 Session Round Numbering Fix

## Goal
Make every live game session start at `Round 1` regardless of old persisted score history.

## Symptom
- Starting a fresh Solo game could immediately show `Round 8`.
- The user expected a new game session to start at `Round 1`.

## Root Cause
- `ComputerGameView.init(vm:humanName:humanAvatar:)` initialized `ComputerGameViewModel.roundNumber` with `vm.nextRoundNumber`.
- `GameViewModel.nextRoundNumber` is computed from the persisted legacy/manual `Round` table:
  - `(rounds.map(\.roundNumber).max() ?? 0) + 1`
- If that table already had rounds `1...7`, a brand-new live Solo game started with `roundNumber = 8`.
- `ComputerGameView.nextRound()`, `saveAndQuit()`, and `playAgain()` also used `vm.nextRoundNumber`.
- `ComputerGameView.nextRound()` recorded live completed rounds back into the legacy `GameViewModel.rounds` table via `vm.recordRound(builtRound)`, so the stale global table kept influencing future sessions.
- Online and Bluetooth game models already use session-local `roundNumber` starting at `1`; the leak was in the Solo/P&P `ComputerGameView` path.

## Fix
- Added `ComputerGameView.firstSessionRoundNumber = 1`.
- New Solo/P&P sessions now initialize `ComputerGameViewModel.roundNumber` with `1`.
- `nextRound()` now:
  - builds the completed round with `game.roundNumber`
  - advances the next live game to `game.roundNumber + 1`
  - no longer calls `vm.recordRound(builtRound)`
- `saveAndQuit()` now captures the currently completed round with `game.roundNumber`.
- `playAgain()` now resets the live game to round `1`.
- `RoundCompleteView` now builds its current scoring preview with `game.roundNumber` instead of `0`.

## Reusable Pattern
- Live gameplay round labels must be session-local.
- Do not initialize gameplay round numbers from persisted/manual scorekeeper state.
- Do not use `GameViewModel.nextRoundNumber` in `ComputerGameView`, Online gameplay, or Bluetooth gameplay.
- Persisted `HistoryRound.roundNumber` values saved for a game should match the active session's visible round numbers.
- The legacy/manual `Round` table can keep its own numbering for the old scorekeeper, but it must not drive live New Game sessions.

## Files Changed
- `MyApp/MyApp/ComputerGameView.swift`
- `MyApp/CLAUDE.md`
- `MyApp/docs/superpowers/plans/2026-05-31-session-round-numbering.md`

## Checklist
- [x] Identify source of stale `Round 8` label.
- [x] Decouple live Solo/P&P initial round from `GameViewModel.nextRoundNumber`.
- [x] Decouple next-round creation from `GameViewModel.nextRoundNumber`.
- [x] Decouple quit-save and Play Again from `GameViewModel.nextRoundNumber`.
- [x] Stop live Solo/P&P rounds from writing into the legacy global `Round` table.
- [x] Document the issue, fix, and reusable pattern.
- [x] Run signed simulator build verification.
- [x] Install and launch simulator build.

## Verification Plan
Run a normal signed simulator Debug build:

```sh
xcodebuild -project MyApp/MyApp.xcodeproj -scheme MyApp -destination id=<SIMULATOR_ID> -configuration Debug -derivedDataPath /private/tmp/ShadySpadeSignedDerivedData COMPILER_INDEX_STORE_ENABLE=NO build
```

Then install/launch:

```sh
xcrun simctl install <SIMULATOR_ID> /private/tmp/ShadySpadeSignedDerivedData/Build/Products/Debug-iphonesimulator/MyApp.app
xcrun simctl launch <SIMULATOR_ID> com.vijaygoyal.theshadyspade
```

Expected manual check:
- Start `New Game` with 1 player.
- The first live game screen should show `Round 1`, even if old local score/history data exists.
- Tap Play Again after a game-over; it should also restart at `Round 1`.
- Next Round within the same game should show `Round 2`, then `Round 3`, etc.

## Verification Result
- Normal signed simulator Debug build succeeded:

```sh
xcodebuild -project MyApp/MyApp.xcodeproj -scheme MyApp -destination id=D6EB3CD2-618C-4B60-A6F5-7A9DA65CFE8F -configuration Debug -derivedDataPath /private/tmp/ShadySpadeSignedDerivedData COMPILER_INDEX_STORE_ENABLE=NO build
```

- Installed and launched on iPhone 17 Pro simulator `D6EB3CD2-618C-4B60-A6F5-7A9DA65CFE8F`.
- Launch returned PID `43034`.
- Manual device verification still needed: start `New Game` with 1 player and confirm the first live game label is `Round 1`.
