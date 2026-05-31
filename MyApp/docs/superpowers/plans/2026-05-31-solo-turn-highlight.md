# 2026-05-31 Solo Turn Highlight Fix

## Goal
Fix the Solo mode playing-phase avatar highlight so the green active marker follows the player currently playing a card, and make the active-turn UI pattern reusable across Solo, Online, and Bluetooth.

## Symptom
- Solo mode: during card play, the top avatar row highlighted the hand leader instead of the current card player.
- Online and Bluetooth: highlight already followed the current action player.
- Visible impact: the green active border/arrow, waiting banner, and empty current-hand text could point at the wrong player in Solo.

## Root Cause
- `ComputerGameView` used `game.currentLeaderIndex` for active-turn UI.
- `currentLeaderIndex` changes only when `resolveTrick()` runs after all six cards have been played.
- During a trick, each card is played by a different player, but Solo had no separate "current player acting now" state.
- Online and Bluetooth already use `currentActionPlayer`, which is why those modes behaved correctly.

## Fix
- Added `currentActionPlayer` to `ComputerGameViewModel`.
- `startPlayingPhase()` now sets `currentActionPlayer` before each human or AI card action.
- `currentActionPlayer` is cleared to `-1` during the post-trick reveal / next-hand wait and at round completion.
- Solo playing UI now uses `currentActionPlayer` for:
  - portrait avatar highlight
  - landscape player row active dot/border
  - waiting banner
  - empty current-hand "Waiting for ..." copy
- Shared turn UI was centralized in `Styles.swift`:
  - `TurnUI`
  - `TurnAvatarChip`
  - `TurnWaitingBanner`
- Online and Bluetooth portrait avatar chips and waiting banners were moved to the same shared components.

## Reusable Pattern
- Use `currentActionPlayer` for "whose turn is it right now" UI in all modes.
- Use `currentLeaderIndex` only for trick order: leader/winner/start seat.
- Use `TurnUI.isActive(playerIndex:currentActionPlayer:)` instead of direct equality checks in game views.
- Put active-turn visual styling in `Styles.swift` so color/border/banner changes are made once.

## Files Changed
- `MyApp/MyApp/ComputerGameViewModel.swift`
- `MyApp/MyApp/ComputerGameView.swift`
- `MyApp/MyApp/OnlineGameView.swift`
- `MyApp/MyApp/BluetoothGameView.swift`
- `MyApp/MyApp/Styles.swift`
- `MyApp/CLAUDE.md`
- `MyApp/docs/superpowers/plans/2026-05-31-solo-turn-highlight.md`

## Checklist
- [x] Analyze why Solo differs from Online/Bluetooth.
- [x] Add explicit Solo action-player state.
- [x] Wire Solo playing UI to action-player state.
- [x] Centralize active-turn portrait chip and waiting banner.
- [x] Update Online and Bluetooth to use the same turn UI components.
- [x] Update Claude context with issue/fix/pattern.
- [x] Run lightweight Swift parser verification.
- [x] Run full Xcode build verification.
- [x] Install and launch on booted simulator.

## Verification Plan
Lightweight parser check run:

```sh
xcrun swiftc -parse -parse-as-library MyApp/MyApp/Styles.swift MyApp/MyApp/ComputerGameViewModel.swift MyApp/MyApp/ComputerGameView.swift MyApp/MyApp/OnlineGameView.swift MyApp/MyApp/BluetoothGameView.swift
```

Result: passed.

Full simulator build run:

```sh
xcodebuild -project MyApp/MyApp.xcodeproj -scheme MyApp -destination id=D6EB3CD2-618C-4B60-A6F5-7A9DA65CFE8F -configuration Debug -derivedDataPath /private/tmp/ShadySpadeDerivedData CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO build
```

Result: passed. Non-TTY `xcodebuild` attempts hung at the Xcode build-service clang macro probe, but the same simulator build completed successfully when run under a TTY.

Simulator install:

```sh
xcrun simctl install D6EB3CD2-618C-4B60-A6F5-7A9DA65CFE8F /private/tmp/ShadySpadeDerivedData/Build/Products/Debug-iphonesimulator/MyApp.app
xcrun simctl launch D6EB3CD2-618C-4B60-A6F5-7A9DA65CFE8F com.vijaygoyal.theshadyspade
```

Result: installed and launched on iPhone 17 Pro simulator. Launch returned PID `31362`.

Manual device check:
- Start Solo mode.
- Reach the playing phase.
- Confirm the green avatar highlight moves to each player as their card is pending/played.
- Confirm no active player is highlighted during the post-trick reveal / next-hand wait.
- Confirm Online and Bluetooth still show the same active-turn visuals.
