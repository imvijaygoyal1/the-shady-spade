# Deduplicate Turn Prompts

## Goal
Remove repeated "Your turn" instructions from the playing screen without
changing card legality, turn flow, scoring, networking, or leaderboard behavior.

## Implementation
- In solo, online, and Bluetooth playing views, changed current trick copy from
  an action prompt to neutral table state:
  - `Trick N — waiting for your play`
- Shortened the hand-area action prompt from:
  - `Your turn — tap a card to play`
  to:
  - `Your turn`
- Cleared the solo/pass-and-play `ComputerGameViewModel.message` value for
  human turns so the same long instruction does not render below Last Hand.
- Left waiting banners for other players' turns unchanged.
- Left valid-card shimmer and invalid-card dimming unchanged.

## Rollback
Restore the two string literals in each file:
- `MyApp/ComputerGameView.swift`
- `MyApp/OnlineGameView.swift`
- `MyApp/BluetoothGameView.swift`

To restore the old solo/pass-and-play message below Last Hand, also restore:
- `ComputerGameViewModel.message = "Your turn — tap a card to play"`

## Verification
- `xcodebuild -quiet -project MyApp.xcodeproj -scheme MyApp -destination 'generic/platform=iOS Simulator' build`
