# 2026-05-31 Leaderboard Auth Gate Fix

## Goal
Fix leaderboard game details not updating when the app starts or saves a game before Firebase anonymous auth is ready.

## Symptom
- A completed game was saved to the local pending queue, but leaderboard game details did not appear.
- Simulator logs showed:
  - `Missing or insufficient permissions`
  - `stats listener error — reattaching in 3s`
  - `log listener error — reattaching in 3s`
  - `no current user`
  - Firebase Auth keychain access failures
- The local pending file contained the completed game record, proving the game-save path ran but the remote leaderboard flush did not complete.

## Root Cause
- Firestore rules require `request.auth != null` for `player_stats` and `game_log` reads.
- `AppDelegate.signInAnonymouslyIfNeeded()` starts auth asynchronously.
- `LeaderboardService.startListening()` attached Firestore listeners immediately, before auth was guaranteed.
- `recordGame()` enqueued the record first, but then attempted the HTTP Cloud Function send without first ensuring a current Firebase user.
- If auth was not available, the record stayed pending and might not flush until a later app launch or network transition.
- Simulator-specific finding: an unsigned simulator install built with `CODE_SIGNING_ALLOWED=NO` can make Firebase Auth fail keychain access. That install mode is acceptable for compile/UI smoke checks but not for validating leaderboard sync.

## Fix
- `LeaderboardService.startListening()` now:
  - stops stale listeners/tasks cleanly
  - starts the network monitor
  - starts a Firebase auth-state listener
  - schedules Firestore listener attachment through a shared auth gate
- Added `scheduleAuthenticatedListenerAttach(after:)` so listener attachment only happens after `ensureAuthenticated()` succeeds.
- `reattachListeners()` now tears down only Firestore listeners and re-enters the same auth-gated attach path after the 3s delay.
- `recordGame()` now calls `ensureAuthenticated()` after durable enqueue and before `sendRecord`.
- `flushPendingRecords()` now exits early if auth cannot be established, leaving pending records intact for the next recovery path.
- Network recovery and auth-state recovery both retry listener attachment and pending flush.

## Reusable Pattern
- All modes should call `LeaderboardService.shared.recordGame(...)` for score saves.
- Leaderboard reads and writes must stay behind `LeaderboardService.ensureAuthenticated()`.
- Do not attach `player_stats` or `game_log` listeners directly from mode views.
- Do not call the Cloud Function directly from mode views.
- If leaderboard sync fails, inspect the pending queue before assuming the game did not save locally.
- For simulator leaderboard validation, prefer a normally signed Xcode build/install. Treat unsigned `CODE_SIGNING_ALLOWED=NO` installs as compile/UI smoke tests only.

## Files Changed
- `MyApp/MyApp/LeaderboardService.swift`
- `MyApp/CLAUDE.md`
- `MyApp/docs/superpowers/plans/2026-05-31-leaderboard-auth-gate.md`

## Checklist
- [x] Confirm local pending queue contained the completed game record.
- [x] Confirm Firestore listener failures were permission errors caused by missing auth.
- [x] Gate leaderboard listener attachment on Firebase auth.
- [x] Gate live game-record HTTP sends on Firebase auth.
- [x] Keep pending records durable when auth cannot be established.
- [x] Log the simulator unsigned-install caveat.
- [x] Run Xcode build verification.
- [x] Install and launch on simulator.
- [x] Confirm pending leaderboard record flushes after launch.

## Verification Plan
Run a simulator Debug build, install, and launch:

```sh
xcodebuild -project MyApp/MyApp.xcodeproj -scheme MyApp -destination id=<SIMULATOR_ID> -configuration Debug -derivedDataPath /private/tmp/ShadySpadeDerivedData COMPILER_INDEX_STORE_ENABLE=NO build
xcrun simctl install <SIMULATOR_ID> /private/tmp/ShadySpadeDerivedData/Build/Products/Debug-iphonesimulator/MyApp.app
xcrun simctl launch <SIMULATOR_ID> com.vijaygoyal.theshadyspade
```

Then check:

```sh
xcrun simctl spawn <SIMULATOR_ID> log show --style compact --last 2m --predicate 'subsystem == "com.vijaygoyal.theshadyspade"'
```

Expected:
- No repeated Firestore `Missing or insufficient permissions` listener loop after auth succeeds.
- Pending record flush logs appear if a record exists.
- `leaderboard_pending_v1.json` becomes empty or is absent after a successful flush.

## Verification Result
- Build command completed successfully with normal simulator signing:

```sh
xcodebuild -project MyApp/MyApp.xcodeproj -scheme MyApp -destination id=D6EB3CD2-618C-4B60-A6F5-7A9DA65CFE8F -configuration Debug -derivedDataPath /private/tmp/ShadySpadeSignedDerivedData COMPILER_INDEX_STORE_ENABLE=NO build
```

- Installed and launched on booted iPhone 17 Pro simulator `D6EB3CD2-618C-4B60-A6F5-7A9DA65CFE8F`; final launch returned PID `34676`.
- Recent fixed-process logs had no `Missing or insufficient permissions` events.
- `leaderboard_pending_v1.json` exists with `[]`, confirming the pending queue is empty after launch.
