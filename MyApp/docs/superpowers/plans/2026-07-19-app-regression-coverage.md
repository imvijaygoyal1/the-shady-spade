# App Regression Coverage

## Goal

Raise useful regression coverage outside the scorekeeper surface without making tests depend on Firebase, network availability, or SwiftUI app lifecycle timing.

## Implemented

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

## Verification

- Focused `AppRegressionTests` passed with `5` tests and `0` failures:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.19_12-54-24--0400.xcresult`
- Full scheme with `-enableCodeCoverage YES` passed with `59` unit tests and `2` UI tests, `0` failures, `0` skips:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.19_12-56-13--0400.xcresult`
- Coverage target rows from the full coverage bundle:
  - `MyApp.app` 9.94% (6545/65872)
  - `MyAppTests.xctest` 96.55% (1789/1853)
  - `MyAppUITests.xctest` 93.40% (99/106)
- `git diff --check` passed.

## Privacy Impact

- No new data collection, upload, retention, or third-party behavior.
- This batch only made existing privacy/consent and leaderboard-payload decisions testable.
- No privacy policy or App Store privacy-label update required.

## Next Coverage Candidates

- Add Firebase-free tests for `GameViewModel` local SwiftData round add/delete/fetch with an in-memory model container.
- Extract and test final-standings/history-save helpers from Solo/Online/Bluetooth views.
- Add focused tests for `OnlineSessionViewModel` join-code validation and local fallback decisions.
