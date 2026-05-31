# 2026-05-31 Random Initial Dealer

## Goal
Make the bid-start player feel more like a real table by randomizing who deals first in each new session, while preserving normal dealer rotation after that.

## Symptom
- User feedback said the same player always appeared to start bidding.
- Code analysis confirmed the bidding rule was correct inside a continuous game, but new sessions usually started with a fixed dealer.

## Root Cause
- First bidder is always computed as `(dealerIndex + 1) % 6`.
- That rule is correct, but fresh sessions often seeded `dealerIndex` as `0`.
- Result: every fresh session started with player `1` bidding.
- Solo Play Again also reused `vm?.dealerIndex ?? 0`, which could restart from the same table position instead of carrying forward.

## Fix
- Solo / Pass & Play:
  - New `ComputerGameView` sessions use a random initial dealer.
  - Next Round keeps the existing rotation.
  - Play Again now starts with `(game.dealerIndex + 1) % 6`.
- Online:
  - `OnlineSessionViewModel` stores a random `currentDealerIndex` when creating/preparing a session.
  - The session listener parses `currentDealerIndex`.
  - `OnlineSessionView` passes it through `onGameReady`.
  - `ModeSelectionView` uses that value when creating `OnlineGameViewModel`.
- Bluetooth:
  - `BluetoothGameViewModel.startHosting(...)` assigns a random dealer when a fresh host session starts.

## Reusable Pattern
- Randomize only the initial dealer for a brand-new game/session.
- Keep bidding deterministic and explainable:
  - first bidder is always the player after the dealer
  - dealer rotates one seat after each round
- Do not randomize the first bidder directly.

## Files Changed
- `MyApp/MyApp/ComputerGameView.swift`
- `MyApp/MyApp/OnlineSessionViewModel.swift`
- `MyApp/MyApp/OnlineSessionView.swift`
- `MyApp/MyApp/ModeSelectionView.swift`
- `MyApp/MyApp/BluetoothGameViewModel.swift`
- `MyApp/CLAUDE.md`
- `MyApp/docs/superpowers/plans/2026-05-31-random-initial-dealer.md`

## Checklist
- [x] Confirm first bidder rule remains `(dealerIndex + 1) % 6`.
- [x] Confirm next-round dealer rotation already works.
- [x] Randomize Solo fresh-session dealer.
- [x] Carry Solo Play Again to the next dealer.
- [x] Randomize/persist Online session initial dealer.
- [x] Pass Online initial dealer into `OnlineGameViewModel`.
- [x] Randomize Bluetooth host initial dealer.
- [x] Run signed simulator Debug build.
- [x] Install and launch simulator build.

## Verification
- Signed simulator Debug build succeeded:

```sh
xcodebuild -project MyApp/MyApp.xcodeproj -scheme MyApp -destination id=D6EB3CD2-618C-4B60-A6F5-7A9DA65CFE8F -configuration Debug -derivedDataPath /private/tmp/ShadySpadeSignedDerivedData COMPILER_INDEX_STORE_ENABLE=NO build
```

- Installed and launched on iPhone 17 Pro simulator `D6EB3CD2-618C-4B60-A6F5-7A9DA65CFE8F`.
- Launch PID: `47712`.

## Manual Check
- Start several fresh Solo games and confirm the Dealer label varies.
- Confirm the bid-start toast names the player after the dealer.
- Finish or advance a round and confirm the next round rotates dealer by one seat.
- Repeat for Online host and Bluetooth host session creation.
