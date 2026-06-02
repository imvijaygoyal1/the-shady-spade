# Remove 500-Point Game-Ending Rule

Date: 2026-06-01

## Context

The user clarified that they never provided a requirement for the game to end, or otherwise be affected, when a player reaches 500 score points. Existing code treated 500 as a winning score in Solo, Online, and Bluetooth modes, and the How to Play copy repeated that as a rule.

## Decision

Remove score-threshold impact from gameplay. Running score remains visible as accumulated scoring history, but reaching 500 must not automatically end or alter a game.

## Implementation

- Solo: removed the `targetScore = 500` constant, stopped passing it into `RoundCompleteView`, and removed the `updated.max() >= targetScore` branch that set `isGameOver = true`.
- Online: removed `OnlineGameViewModel.winningScore` and changed the final trick resolution to always write `.roundComplete` after scoring the round.
- Bluetooth: removed `BluetoothGameViewModel.winningScore` and changed final trick resolution to always set `.roundComplete` after scoring the round.
- Help copy: removed both 500-point win-condition sentences from `SettingsView`.

## Verification

- Search confirmed no remaining `winningScore`, `500 points`, `reach 500`, or score-threshold-to-game-over references in `MyApp/MyApp`.
- `xcrun swiftc -parse -parse-as-library MyApp/*.swift` passed.
- Full `xcodebuild` resolved packages and started building, but stalled with no compiler errors and was interrupted.

## Touched Files

- `MyApp/ComputerGameView.swift`
- `MyApp/OnlineGameViewModel.swift`
- `MyApp/OnlineGameView.swift`
- `MyApp/BluetoothGameViewModel.swift`
- `MyApp/BluetoothGameView.swift`
- `MyApp/SettingsView.swift`
- `CLAUDE.md`
