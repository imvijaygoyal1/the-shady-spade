# Real-Life Scorekeeper Phase 1

## Context

Players may play The Shady Spade with physical cards and still want the app to maintain the scorecard. The feature should not deal cards or run gameplay logic. It should act as a smart score sheet for a six-player real-life table.

## Product Decision

Phase 1 is single-device and local-only:

- One player/device owns the active scorecard.
- Scorekeeping delegation happens by physically passing the device.
- All six players are configured at setup.
- Round entry records dealer, bidder, bid, trump, two partners, and whether the bid was made or set.
- The scorekeeper can edit or delete the last round for corrections.
- Finishing the scorecard saves it into existing local game history.
- No Firebase upload, leaderboard write, account flow, QR sharing, or multi-device sync is introduced.

## Implementation

- Added `ScorekeeperGameState`, `ScorekeeperRoundEntry`, `ScorekeeperRoundDraft`, and `ScorekeeperStore`.
- Active in-progress scorecards persist locally in `UserDefaults` under `scorekeeper_active_game_v1`.
- Added `ScorekeeperRootView` with setup, live scoreboard, round entry, edit-last, delete-last, reset, and finish/save flows.
- Round entry no longer asks for offense points. The saved history compatibility value is generated from the made/set result.
- Added a top-level `Real-Life Scorekeeper` mode card from `ModeSelectionView`.
- Reused existing `ScoringEngine.calculateRoundScores(...)` so manual scorekeeping matches in-app scoring.
- Added local-history export via existing `GameHistory` / `HistoryRound` SwiftData models with `gameMode: "Scorekeeper"`.
- Follow-up UX refinement: added active-scorecard player-name editing from the live header, renamed correction actions to `Edit Last Round` and `Delete Last Round`, and expanded the empty round-history copy so users know when and how to add the first round.
- Rules refinement: bid now defaults to `130` and cannot be lowered below `130`; the round-entry sheet displays the read-only bid starter as the player immediately after the dealer; the winning bidder defaults to that bid starter; Partner 1 and Partner 2 dropdowns exclude the winning bidder; partner validation remains as a backstop and explicitly rejects either partner matching the winning bidder plus duplicate partners.
- Round-history refinement: each recorded round now shows named Offense and Defense sections with every player's score delta instead of anonymous six-position score boxes.
- Regression hardening: added a dedicated `MyAppUITests` target with `ScorekeeperFlowUITests.testScorekeeperAddRoundShowsNamedHistoryAndPartnerRules` to automate the setup -> add round -> partner eligibility -> named history path.
- UI-test launch hardening: added `-SHADYSPADE_UI_TESTING` to skip onboarding and suppress Firebase/background listener startup during UI automation, plus `-SHADYSPADE_RESET_SCOREKEEPER_FOR_UI_TESTS` to clear the active local scorecard before the flow.
- Store reset hardening: `ScorekeeperStore` clears standard persisted state before loading when the UI-test reset argument or environment value is present, preventing active-scorecard leakage across simulator/full-scheme runs.
- Accessibility coverage: added stable identifiers for the scorekeeper mode card, setup player fields, live actions, bid value, partner pickers, and round-entry controls so UI tests do not depend on visual text structure.
- UI-test stability: the final scorekeeper UI regression uses default setup names (`Player 1`...`Player 6`) because full-scheme runs exposed flaky iOS simulator keyboard focus while typing custom names; default names still prove that named round history is rendered.

## Privacy

No App Store privacy policy update is required for Phase 1 because player names and scorecards remain local-only and are not uploaded or shared.

## Verification

- `xcodebuild test -project MyApp.xcodeproj -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyAppTests/ScorekeeperTests` passed `7` tests with `0` failures.
- Result bundle: `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.18_11-58-42--0400.xcresult`
- `xcodebuild test -quiet -project MyApp.xcodeproj -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyAppUITests/ScorekeeperFlowUITests/testScorekeeperAddRoundShowsNamedHistoryAndPartnerRules` passed.
- UI result bundle: `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.18_12-26-57--0400.xcresult`
- Latest focused `ScorekeeperTests` rerun passed.
- Unit result bundle: `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.18_12-29-20--0400.xcresult`
- Step-by-step regression pass:
  - All unit tests: `xcodebuild test -quiet -project MyApp.xcodeproj -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyAppTests` passed.
  - Unit result bundle: `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.18_12-34-42--0400.xcresult`
  - All UI tests: `xcodebuild test -quiet -project MyApp.xcodeproj -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyAppUITests` passed after increasing setup wait timing.
  - UI result bundle: `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.18_12-45-41--0400.xcresult`
  - Full unfiltered scheme: `xcodebuild test -quiet -project MyApp.xcodeproj -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 17'` passed after removing keyboard-dependent custom-name typing from the UI regression.
  - Full result bundle: `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.18_13-01-21--0400.xcresult`
- `xcodebuild build -project MyApp.xcodeproj -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 17'` succeeded.
- Installed and launched the updated build on booted `iPhone 17 Pro` simulator `DA97985A-F7CC-44F6-8281-9DD24C22B978`; latest launch returned PID `92224`.
- Screenshot smoke check was captured and removed after review; normal launch showed the persisted local active scorecard as expected.

## Future Phases

- Phase 2: QR/live view for other devices as read-only viewers.
- Phase 3: controlled scorekeeping delegation to one joined player.
- Avoid unrestricted all-player editing unless an approval/audit workflow is added.
