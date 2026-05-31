# 2026-05-31 Leaderboard In-Flight Send De-Duplication

## Goal
Stop the same completed game from being sent twice when the live leaderboard save and pending-queue flush run at the same time.

## Symptom
- After completing a Solo game, device logs showed:
  - `ComputerGameView.saveGameHistory: mode=Solo rounds=1 savedRounds=0`
  - `recordGame called mode=Solo names=6 rounds=1 winner=1`
  - `flushing 1 pending record(s)`
  - two `record sent ✓ attempt=1` lines
  - `pending record flushed ✓ id=...`
- Logs also showed `nw_protocol_instance_set_output_handler Not calling remove_input_handler ... udp`.
- Follow-up device test after the in-flight fix showed only one `record sent ✓`, with `flushPendingRecords: skipping in-flight record` while the live save was still active. That confirmed the duplicate-send bug was fixed, but the expected skip logs still looked like errors in Xcode.

## Root Cause
- The `nw_protocol_instance_set_output_handler ... udp` and `nw_path_necp_check_for_updates Failed to copy updated result (22)` lines are Apple Network framework diagnostics. They are noisy, but not the leaderboard bug.
- `LeaderboardService.recordGame()` intentionally enqueues a pending record before sending it. This is correct because the record survives a process suspension, crash, or network loss.
- `flushPendingRecords()` can run from startup, network recovery, or auth recovery.
- If a flush reads the queue while the live `recordGame()` path is sending the same queued record, both paths can call `sendRecord()`.
- The previous `isFlushing` flag only prevented overlapping flushes. It did not prevent a live send and a flush from sending the same game concurrently.
- There was a second edge case: if a flush started with an older queued copy and `recordGame()` replaced that queued copy while the flush was sending, removing the sent UUID alone could leave the replacement queued for a later resend.

## Fix
- Added in-flight tracking in `LeaderboardService`:
  - `inFlightRecordIDs`
  - `inFlightDeduplicationKeys`
- Added shared helpers:
  - `claimSend(_:)`
  - `releaseSend(_:)`
- `recordGame()` now claims the pending record before authentication/HTTP send. If the same game is already in flight, it leaves the record queued and exits with `.pending`.
- `flushPendingRecords()` now claims each queued record before sending. If the same record or same deduplication key is already in flight, flush skips it.
- Follow-up: `flushPendingRecords()` now filters out in-flight records before calling `ensureAuthenticated()`, and returns quietly when every queued record is already being sent. This avoids repeated `flushing 1 pending record(s)` logs and avoids unnecessary auth/network work during an active live send.
- Successful and permanently rejected sends now call `removeFromQueue(matching:)`, which removes:
  - the exact pending UUID
  - any same-game queued replacement with the same deduplication key
- Server-side `sessionCode`/deduplication remains defense-in-depth, but the client no longer intentionally sends the same game from two paths.

## Reusable Pattern
- Keep the durable enqueue-before-send pattern for all modes.
- All score saves must go through `LeaderboardService.recordGame(...)`.
- Synchronous game-over handlers may use `LeaderboardService.preEnqueue(...)`, but should not send HTTP directly.
- Any retry or flush path must use `claimSend(_:)` and `releaseSend(_:)` before calling `sendRecord(_:)`.
- Expected in-flight skip states should be logged at debug level or returned silently. Info/error logs should be reserved for actual send attempts, terminal rejections, or retryable failures.
- Queue removal after a terminal send should remove by same-game identity, not only by UUID, because the queue can be replaced while a send is in flight.
- Treat Apple `nw_protocol_instance_set_output_handler ... udp` logs as OS/network diagnostics unless they appear with an actual app failure.

## Files Changed
- `MyApp/MyApp/LeaderboardService.swift`
- `MyApp/CLAUDE.md`
- `MyApp/docs/superpowers/plans/2026-05-31-leaderboard-inflight-send.md`

## Checklist
- [x] Identify the duplicate send as a live-save vs pending-flush race.
- [x] Preserve durable enqueue-before-send behavior.
- [x] Add shared in-flight send claims by UUID and same-game deduplication key.
- [x] Make pending flush skip records already being sent.
- [x] Filter out in-flight records before auth/network work to reduce misleading flush logs.
- [x] Remove same-game queued replacements after terminal send outcomes.
- [x] Document the issue, root cause, fix, and reusable pattern.
- [x] Run simulator Debug build verification.
- [x] Install and launch on simulator.

## Verification Plan
Run a normal simulator Debug build, install, and launch:

```sh
xcodebuild -project MyApp/MyApp.xcodeproj -scheme MyApp -destination id=<SIMULATOR_ID> -configuration Debug -derivedDataPath /private/tmp/ShadySpadeSignedDerivedData COMPILER_INDEX_STORE_ENABLE=NO build
xcrun simctl install <SIMULATOR_ID> /private/tmp/ShadySpadeSignedDerivedData/Build/Products/Debug-iphonesimulator/MyApp.app
xcrun simctl launch <SIMULATOR_ID> com.vijaygoyal.theshadyspade
```

Then complete or replay a leaderboard save path and inspect logs:

```sh
xcrun simctl spawn <SIMULATOR_ID> log show --style compact --last 5m --predicate 'subsystem == "com.vijaygoyal.theshadyspade"'
```

Expected:
- A single game should not produce both a live `record sent ✓` and a pending `record sent ✓` at the same time.
- If flush sees a record already in flight, logs should show `flushPendingRecords: skipping in-flight record`.
- Pending queue should be empty after a successful send.

## Verification Result
- Normal signed simulator Debug build succeeded after the in-flight logging cleanup:

```sh
xcodebuild -project MyApp/MyApp.xcodeproj -scheme MyApp -destination id=D6EB3CD2-618C-4B60-A6F5-7A9DA65CFE8F -configuration Debug -derivedDataPath /private/tmp/ShadySpadeSignedDerivedData COMPILER_INDEX_STORE_ENABLE=NO build
```

- Installed and launched on iPhone 17 Pro simulator `D6EB3CD2-618C-4B60-A6F5-7A9DA65CFE8F`.
- Latest launch returned PID `42145`.
- Recent app-subsystem log query showed no warnings/errors:

```sh
xcrun simctl spawn D6EB3CD2-618C-4B60-A6F5-7A9DA65CFE8F log show --style compact --last 2m --predicate 'subsystem == "com.vijaygoyal.theshadyspade"'
```

- A full game-end flow was not replayed during this verification pass, so the next physical-device check should complete a Solo game and confirm only one leaderboard send path logs for that game.
