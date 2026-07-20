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

### Batch 3

- Added `scripts/coverage_report.py` so coverage can be inspected consistently from any Xcode `.xcresult`.
  - Prints raw `MyApp.app` coverage from Xcode.
  - Prints a logic-focused app coverage number that excludes large SwiftUI/render-only files.
  - Lists the top uncovered app files by executable-line count.
- Extracted leaderboard presentation helpers from `LeaderboardView`:
  - `LeaderboardStatsSortKey`,
  - `LeaderboardStatsSorter`,
  - `LeaderboardDisplay`.
- Kept report-mail URL formatting in `LeaderboardReportMail`, with internal visibility so the exact generated mailto URLs can be unit-tested.
- Added `ComputerGameViewModelTests` covering:
  - card point values,
  - suit sorting,
  - deal/reset state,
  - duplicate/invalid/bidder-owned calling-card rejection,
  - follow-suit playable-card rules,
  - completed round score construction from won tricks,
  - player-name/avatar fallback.
- Added `LeaderboardPresentationTests` covering:
  - mode-filter matching,
  - leaderboard stat sorting by wins, points, games, and bid success rate,
  - player-stat derived metrics,
  - Pass & Play display text,
  - encoded report mailto context for player detail and game-log reports.

### Batch 4

- Added `GameFlowRules` as a shared pure helper for six-seat multiplayer rules:
  - first bidder after dealer,
  - bid minimum/maximum/step validation,
  - can-pass and must-pass state,
  - active-player and next-bidder rotation,
  - offense/defense seat grouping,
  - offense/defense point totals,
  - follow-suit playable-card filtering,
  - called-card validation against the 48-card deck and caller hand,
  - partner resolution from called cards,
  - next player within a trick.
- Refactored `OnlineGameViewModel` to use `GameFlowRules` for computed bid/card/score rules, start-bidding first seat, host bid validation, pass/bid rotation, called-card validation, partner resolution, final-round offense totals, and next-player-in-trick.
- Refactored `BluetoothGameViewModel` to use `GameFlowRules` for the same duplicated rules.
- Tightened multiplayer host-side bid validation to require the next legal bid above the current high bid, matching the existing UI minimum.
- Added `GameFlowRulesTests` covering:
  - first-bidder wraparound,
  - minimum bid, can-pass, and must-pass behavior,
  - valid/invalid bid amounts,
  - active-player and next-bidder rotation,
  - called-card validation,
  - follow-suit card filtering,
  - next trick player wraparound,
  - partner resolution,
  - offense and defense point totals.
- Added `MultiplayerViewModelRulesTests` covering:
  - Online view-model bid, offense/defense, valid-card, and calling validation properties,
  - Bluetooth view-model bid, offense/defense, valid-card, and calling validation properties.

### Batch 5

- Added `LeaderboardPendingQueue` as a pure helper for local leaderboard retry persistence:
  - JSON encode/decode,
  - file load/save,
  - legacy `UserDefaults` migration,
  - file-first loading when both file and legacy storage exist,
  - duplicate same-game replacement by `deduplicationKey`,
  - newest-100 queue cap,
  - sent-record removal by UUID and same-game key.
- Refactored `LeaderboardService` pending-queue methods to call `LeaderboardPendingQueue`.
- Added `LeaderboardPendingQueueTests` covering:
  - successful pending-record round-trip,
  - corrupt payload rejection,
  - legacy migration into the file-backed queue,
  - file-backed queue taking precedence over legacy defaults,
  - duplicate replacement preserving the newer record UUID,
  - oldest-record eviction once the queue exceeds 100 records,
  - removal of both the sent record and a same-game replacement.

### Batch 6

- Added `LeaderboardSendRequest` as a pure helper for Cloud Function send behavior:
  - pending-record payload construction,
  - `["data": ...]` request wrapping,
  - HTTP status classification into success, terminal server rejection, or retryable network failure.
- Moved `SendResult` out of private `LeaderboardService` scope so response classification can be unit-tested.
- Refactored `LeaderboardService.sendRecord` to call `LeaderboardSendRequest` while preserving:
  - success removal behavior for HTTP 200,
  - terminal 4xx rejection behavior,
  - retry/enqueue behavior for network errors, 5xx, and unexpected statuses.
- Added `LeaderboardSendRequestTests` covering:
  - exact Cloud Function payload fields,
  - empty-string fallback for a nil session code,
  - wrapped request body shape,
  - 200/4xx/5xx/unexpected status classification.

### Batch 7

- Added `LeaderboardSnapshotMapper` as a pure helper for Firestore read behavior:
  - `player_stats` dictionary to `PlayerStat`,
  - `game_log` dictionary to `GameLogEntry`,
  - Timestamp and direct `Date` conversion,
  - deterministic fallback dates for tests,
  - schema defaults for malformed/missing fields,
  - defense-name extraction and empty/invalid-name filtering.
- Refactored `LeaderboardService.attachFirestoreListeners` so listener closures now handle only loading/error/reattach lifecycle and delegate model construction to the mapper.
- Added `LeaderboardSnapshotMapperTests` covering:
  - valid player-stat mapping,
  - missing/empty player-name rejection,
  - malformed numeric/date/mode defaults,
  - valid game-log mapping,
  - Timestamp conversion,
  - defense-name filtering,
  - malformed game-log defaults.
- Fixed a same-file compiler warning in `LeaderboardService.enqueue` by changing an unmutated local from `var` to `let`.

### Batch 8

- Added `SyncedGameStateMapper` as a pure helper shared by Online and Bluetooth game modes:
  - Int/Int64 conversion,
  - six-player Int/Bool array parsing,
  - AI-seat filtering,
  - bid-history decode with latest-value normalization,
  - bid-history encoding,
  - current-trick decode with player bounds and deck-valid card checks,
  - current-trick encoding,
  - completed-round encoding,
  - host-synced completed-round decoding with duplicate/invalid-partner filtering,
  - round-complete `HistoryRound` construction with Online fallback behavior and Bluetooth partner validation.
- Refactored `OnlineGameViewModel` to use the helper for game-state array parsing, bid-history parsing, current-trick parsing, round-complete construction, and outgoing game-state encoding.
- Refactored `BluetoothGameViewModel` to use the helper for the same areas plus host-synced completed-round decoding and completed-round encoding.
- Added `SyncedGameStateMapperTests` covering:
  - mixed Int/Int64 six-value parsing,
  - wrong-count rejection,
  - malformed Bool fallback,
  - AI-seat bounds filtering,
  - latest bid history in first-appearance order,
  - Online-style unbounded and Bluetooth-style bounded bid-history parsing,
  - current-trick card/player validation,
  - completed-round decode/encode/dedupe,
  - Online fallback versus Bluetooth resolved-partner requirement.
- Added `ComputerGameViewModelTests.test_humanConfirmCallingResolvesPartnersAndTransitionsToHumanPlaying` to cover the solo human calling-to-playing transition without UI automation.

### Batch 9

- Added `MultiplayerActionValidator` as a pure helper shared by Online and Bluetooth host action paths:
  - player-index bounds validation,
  - wrong-turn rejection,
  - bid validation against the current minimum and 250 maximum,
  - duplicate called-card rejection,
  - invalid called-card rejection against the 48-card deck,
  - bidder-owned called-card rejection,
  - invalid played-card rejection,
  - card-not-in-hand rejection,
  - follow-suit card-play enforcement.
- Refactored `OnlineGameViewModel.processPendingAction` so bid, pass, call-cards, and play-card actions call the shared validator before consuming the nonce or writing game state.
- Refactored `BluetoothGameViewModel` host action processors so bid, pass, call-cards, and play-card actions call the same validator before local mutation, Multipeer replies, or broadcasts.
- Added `MultiplayerActionValidatorTests` covering:
  - invalid player index,
  - wrong-turn actions,
  - bid below opening minimum,
  - bid below the next legal minimum after an existing high bid,
  - bid above 250,
  - duplicate/invalid/bidder-owned called cards,
  - invalid card IDs,
  - card not in hand,
  - follow-suit rejection,
  - valid bid/called-card/card-play acceptance.

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
- Focused Batch 3 unit tests passed with `10` tests, `0` failures, `0` skips:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.19_13-41-50--0400.xcresult`
- Full scheme with `-enableCodeCoverage YES` after Batch 3 passed with `81` unit tests and `3` UI tests, `0` failures, `0` skips:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.19_13-43-27--0400.xcresult`
- Coverage target rows from the Batch 3 full coverage bundle:
  - `MyApp.app` 10.93% (7205/65934)
  - `MyAppTests.xctest` 97.53% (2565/2630)
  - `MyAppUITests.xctest` 94.70% (125/132)
- `scripts/coverage_report.py` output from the Batch 3 full bundle:
  - Raw app coverage: 10.93% (7205/65934)
  - Logic-focused coverage: 29.49% (3063/10387)
  - Largest remaining uncovered files: `ComputerGameView.swift`, `OnlineGameView.swift`, `BluetoothGameView.swift`, `Styles.swift`, `OnlineSessionView.swift`, `BluetoothGameViewModel.swift`, `BluetoothSessionView.swift`, `SplashView.swift`, `OnlineGameViewModel.swift`, `LeaderboardView.swift`
- Focused Batch 4 tests passed with `6` tests, `0` failures, `0` skips:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.19_13-54-20--0400.xcresult`
- Full scheme with `-enableCodeCoverage YES` after Batch 4 passed with `87` unit tests and `3` UI tests, `0` failures, `0` skips:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.19_13-56-13--0400.xcresult`
- Coverage target rows from the Batch 4 full coverage bundle:
  - `MyApp.app` 11.36% (7496/65976)
  - `MyAppTests.xctest` 97.72% (2792/2857)
  - `MyAppUITests.xctest` 94.70% (125/132)
- `scripts/coverage_report.py` output from the Batch 4 full bundle:
  - Raw app coverage: 11.36% (7496/65976)
  - Logic-focused coverage: 32.16% (3354/10429)
  - Largest remaining uncovered files: `ComputerGameView.swift`, `OnlineGameView.swift`, `BluetoothGameView.swift`, `Styles.swift`, `OnlineSessionView.swift`, `BluetoothGameViewModel.swift`, `BluetoothSessionView.swift`, `SplashView.swift`, `OnlineGameViewModel.swift`, `LeaderboardView.swift`
- Focused Batch 5 queue tests passed with `5` tests, `0` failures, `0` skips:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.19_14-16-29--0400.xcresult`
- Full scheme with `-enableCodeCoverage YES` after Batch 5 passed with `92` unit tests and `3` UI tests, `0` failures, `0` skips:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.19_14-18-12--0400.xcresult`
- Coverage target rows from the Batch 5 full coverage bundle:
  - `MyApp.app` 11.45% (7556/66005)
  - `MyAppTests.xctest` 97.84% (2949/3014)
  - `MyAppUITests.xctest` 94.70% (125/132)
- `scripts/coverage_report.py` output from the Batch 5 full bundle:
  - Raw app coverage: 11.45% (7556/66005)
  - Logic-focused coverage: 32.64% (3414/10458)
  - `LeaderboardService.swift` coverage: 50.12%
  - Largest remaining uncovered files: `ComputerGameView.swift`, `OnlineGameView.swift`, `BluetoothGameView.swift`, `Styles.swift`, `OnlineSessionView.swift`, `BluetoothGameViewModel.swift`, `BluetoothSessionView.swift`, `SplashView.swift`, `OnlineGameViewModel.swift`, `LeaderboardView.swift`
- Focused Batch 6 send-request tests passed with `3` tests, `0` failures, `0` skips.
- First full scheme coverage attempt after Batch 6 failed before assertions because the simulator test runner died during launch:
  - `NSMachErrorDomain -308`, `Failed to install or launch the test runner`, `Lost connection to testmanagerd`
- Full scheme with `-enableCodeCoverage YES` after Batch 6 passed on rerun with `98` tests, `0` failures, `0` skips:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.19_14-29-24--0400.xcresult`
- `scripts/coverage_report.py` output from the Batch 6 full bundle:
  - Raw app coverage: 11.49% (7587/66020)
  - Logic-focused coverage: 32.89% (3445/10473)
  - Largest remaining uncovered files: `ComputerGameView.swift`, `OnlineGameView.swift`, `BluetoothGameView.swift`, `Styles.swift`, `OnlineSessionView.swift`, `BluetoothGameViewModel.swift`, `BluetoothSessionView.swift`, `SplashView.swift`, `OnlineGameViewModel.swift`, `LeaderboardView.swift`
- Focused Batch 7 snapshot-mapper tests passed with `5` tests, `0` failures, `0` skips.
- A resumed full coverage run after the warning fix failed before app assertions due to simulator UI-test infrastructure:
  - `Timed out while preparing execution worker`
  - `The test runner failed to initialize for UI testing`
  - `Timed out while loading Accessibility`
- Full scheme with `-enableCodeCoverage YES` after Batch 7 passed on rerun with `103` tests, `0` failures, `0` skips:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.19_21-40-21--0400.xcresult`
- Coverage target rows from the Batch 7 full coverage bundle:
  - `MyApp.app` 11.41% (7527/65940)
  - `MyAppTests.xctest` 98.08% (3315/3380)
  - `MyAppUITests.xctest` 94.70% (125/132)
- `scripts/coverage_report.py` output from the Batch 7 full bundle:
  - Raw app coverage: 11.41% (7527/65940)
  - Logic-focused coverage: 32.57% (3385/10393)
  - Largest remaining uncovered files: `ComputerGameView.swift`, `OnlineGameView.swift`, `BluetoothGameView.swift`, `Styles.swift`, `OnlineSessionView.swift`, `BluetoothGameViewModel.swift`, `BluetoothSessionView.swift`, `SplashView.swift`, `OnlineGameViewModel.swift`, `LeaderboardView.swift`
- Focused Batch 8 model/mapper tests passed:
  - `MyAppTests/ComputerGameViewModelTests`
  - `MyAppTests/SyncedGameStateMapperTests`
- Full scheme with `-enableCodeCoverage YES` after Batch 8 passed with `110` tests, `0` failures, `0` skips:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.19_21-56-02--0400.xcresult`
- Coverage target rows from the Batch 8 full coverage bundle:
  - `MyApp.app` 11.79% (7780/65986)
  - `MyAppTests.xctest` 98.18% (3554/3620)
  - `MyAppUITests.xctest` 94.70% (125/132)
- `scripts/coverage_report.py` output from the Batch 8 full bundle:
  - Raw app coverage: 11.79% (7780/65986)
  - Logic-focused coverage: 34.85% (3638/10439)
  - Largest remaining uncovered files: `ComputerGameView.swift`, `OnlineGameView.swift`, `BluetoothGameView.swift`, `Styles.swift`, `OnlineSessionView.swift`, `BluetoothSessionView.swift`, `BluetoothGameViewModel.swift`, `SplashView.swift`, `OnlineGameViewModel.swift`, `LeaderboardView.swift`
- Focused Batch 9 validator tests passed:
  - `MyAppTests/MultiplayerActionValidatorTests`
- Full scheme with `-enableCodeCoverage YES` after Batch 9 passed with `114` tests, `0` failures, `0` skips:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.20_16-32-49--0400.xcresult`
- Coverage target rows from the Batch 9 full coverage bundle:
  - `MyApp.app` 11.76% (7766/66012)
  - `MyAppTests.xctest` 98.31% (3840/3906)
  - `MyAppUITests.xctest` 94.51% (155/164)
- `scripts/coverage_report.py` output from the Batch 9 full bundle:
  - Raw app coverage: 11.76% (7766/66012)
  - Logic-focused coverage: 35.16% (3709/10550)
  - Largest remaining uncovered files: `ComputerGameView.swift`, `OnlineGameView.swift`, `BluetoothGameView.swift`, `Styles.swift`, `OnlineSessionView.swift`, `BluetoothSessionView.swift`, `BluetoothGameViewModel.swift`, `SplashView.swift`, `OnlineGameViewModel.swift`, `LeaderboardView.swift`
- `git diff --check` passed.

## Privacy Impact

- No new data collection, upload, retention, or third-party behavior.
- These batches only made existing privacy/consent, leaderboard-payload, leaderboard-read mapping, send-classification, local-history, room-code, synced game-state, completed-round, multiplayer action validation, and launch decisions testable.
- No privacy policy or App Store privacy-label update required.

## Next Coverage Candidates

- The user-requested main menu UI uplift was completed in `docs/superpowers/plans/2026-07-19-main-menu-uplift.md`. Do not start the next coverage batch until the user explicitly resumes coverage work.
- Extract/test leaderboard status messaging currently embedded in Solo/Online/Bluetooth views.
- Continue extracting and unit-testing remaining pure reducers from `OnlineGameViewModel` and `BluetoothGameViewModel`, especially host action validation/result decisions that still combine state mutation with Firestore/Multipeer writes.
- Add focused tests around additional `ComputerGameViewModel` phase transitions only where continuations can be cancelled deterministically without long sleeps.
- Add targeted UI smoke tests for `GameHistoryView`, `SettingsView`, and leaderboard empty/error states only if they remain stable in simulator automation.
- Consider extracting deterministic view-state builders from `ComputerGameView.swift`, `OnlineGameView.swift`, and `BluetoothGameView.swift`; these files dominate raw coverage but are mostly declarative SwiftUI.

## Coverage Interpretation

- Raw `MyApp.app` coverage is the honest Xcode target metric and currently sits at 11.76%.
- The raw target denominator is dominated by large SwiftUI views. Raising that raw number to 80% would require broad UI/snapshot rendering coverage, significant view decomposition, or explicit coverage exclusions.
- The practical path is to first drive logic-focused app coverage toward 80% by extracting deterministic behavior from views and service singletons, while keeping UI tests limited to stable smoke coverage. After Batch 9, logic-focused coverage is 35.16%.
- Batch 7 increased direct contract coverage but moved covered inline listener code into a new helper, so the raw and logic-focused percentages dipped slightly while the suite grew from `98` to `103` passing tests. Batch 8 recovered and improved the baseline by moving duplicated Online/Bluetooth synced-state logic into a tested helper, raising the suite to `110` passing tests. Batch 9 added host action-admission coverage and raised the suite to `114` passing tests; raw app coverage dipped slightly because the new helper added executable lines while the large SwiftUI denominator still dominates.
