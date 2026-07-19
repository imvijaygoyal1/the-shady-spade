# App Regression Coverage

## Goal

Raise useful regression coverage outside the scorekeeper surface without making tests depend on Firebase, network availability, or SwiftUI app lifecycle timing.

## Implemented

### Batch 1

- Added `AppDeepLinkRouter.route(for:)` and `AppDeepLinkRoute` so join and scorekeeper links can be tested as pure parsing logic.
- Refactored app URL handling to use `AppDeepLinkRouter` while preserving existing side effects:
  - join links set `DeepLinkManager.pendingJoinCode` and post `.joinRoomFromQR`,
  - scorekeeper links set `DeepLinkManager.pendingScorekeeperCode`.
- Added `LeaderboardConsentState.resolvedStoredState(...)` and `allowsLeaderboardUpload` so consent/disclosure-version decisions are testable without mutating the singleton.
- Added `PendingGameRecord.makeValidated(...)` so completed-round leaderboard payload shaping is shared by `recordGame` and `preEnqueue`.
- Added `AppRegressionTests` covering:
  - custom-scheme and hosted join links,
  - hosted scorekeeper links,
  - invalid deep-link routes/codes,
  - stale granted-consent reset when disclosure version changes,
  - consent upload gating,
  - leaderboard record session scoping,
  - player-name profanity sanitization before upload,
  - AI-seat filtering,
  - invalid leaderboard payload dimensions,
  - empty-round rejection,
  - `Round` and `HistoryRound` role and score-delta behavior for save/history displays.

### Batch 2

- Added `GameHistoryBuilder` in `GameModel.swift` for deterministic local history behavior:
  - winner selection from six final scores,
  - sorted `GameHistory` creation,
  - latest final-score lookup from completed history rounds,
  - local SwiftData save,
  - pruning to the most recent 10 stored games.
- Refactored Solo, Online, and Bluetooth local-history save paths to use `GameHistoryBuilder`.
- Added `OnlineSessionViewModel.normalizedRoomCode`, `isValidRoomCode`, and `canStartAsSoloFallback`.
- Reused the shared room-code normalization and solo-fallback helper from `OnlineSessionView`.
- Added `GameViewModelPersistenceTests` covering:
  - in-memory SwiftData setup,
  - valid round add/fetch/newest-first behavior,
  - invalid draft rejection,
  - online-session delete protection,
  - offline delete,
  - player-name trimming, length capping, and blank-name fallback.
- Added `GameHistoryBuilderTests` covering:
  - sorted local history creation,
  - winner selection,
  - invalid input rejection,
  - pruning to 10 games,
  - latest final-score resolution by round number.
- Added `OnlineSessionViewModelTests` covering:
  - plain-code and universal-link normalization,
  - six-character code validation,
  - local host/AI slot seeding without network,
  - solo-fallback decision gating.
- Added `AppLaunchFlowUITests` covering the normal UI-test app launch path and mode-selection screen.

## Verification

- Focused `AppRegressionTests` passed with `5` tests and `0` failures:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.19_12-54-24--0400.xcresult`
- Full scheme with `-enableCodeCoverage YES` passed with `59` unit tests and `2` UI tests, `0` failures, `0` skips:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.19_12-56-13--0400.xcresult`
- Coverage target rows from the full coverage bundle:
  - `MyApp.app` 9.94% (6545/65872)
  - `MyAppTests.xctest` 96.55% (1789/1853)
  - `MyAppUITests.xctest` 93.40% (99/106)
- Focused Batch 2 unit tests passed with `12` tests and `0` failures:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.19_13-14-51--0400.xcresult`
- Focused normal launch UI smoke passed with `1` test and `0` failures:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.19_13-16-48--0400.xcresult`
- Full scheme with `-enableCodeCoverage YES` after Batch 2 passed with `71` unit tests and `3` UI tests, `0` failures, `0` skips:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.19_13-18-33--0400.xcresult`
- Coverage target rows from the Batch 2 full coverage bundle:
  - `MyApp.app` 10.39% (6847/65931)
  - `MyAppTests.xctest` 97.14% (2175/2239)
  - `MyAppUITests.xctest` 94.70% (125/132)
- `git diff --check` passed.

## Privacy Impact

- No new data collection, upload, retention, or third-party behavior.
- These batches only made existing privacy/consent, leaderboard-payload, local-history, room-code, and launch decisions testable.
- No privacy policy or App Store privacy-label update required.

## Next Coverage Candidates

- Add focused tests around `ComputerGameViewModel` phase transitions that can run without UI timing.
- Extract/test leaderboard status messaging currently embedded in Solo/Online/Bluetooth views.
- Add integration-style tests for `LeaderboardService` queue persistence using isolated `UserDefaults` suites.
