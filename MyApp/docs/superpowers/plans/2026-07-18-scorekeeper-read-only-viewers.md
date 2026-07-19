# Scorekeeper Phase 2: Read-Only Live Viewers

## Context

Phase 1 added a local-only real-life scorekeeper for six-player physical-card games. One device owns the active scorecard, records rounds, edits/deletes the last round, and saves the finished scorecard to local history.

The next useful extension is a read-only live viewer mode so players around the table can scan a QR code and watch the scorecard on their own devices while the real-life game is in progress.

## Product Decision

Phase 2 should be read-only and one-writer:

- The scorekeeper device remains the only editor.
- Viewer devices can join by QR code or manually entering a short room code.
- Viewers can see the live scoreboard, round history, and session status.
- Viewers cannot edit player names, add rounds, edit/delete rounds, reset, finish/save, or upload to leaderboard.
- Scorekeeping delegation still means physically passing the scorekeeper device. Delegated remote editing is Phase 3.
- No leaderboard upload is introduced by live viewing. Existing leaderboard consent rules still apply only if a finished scorecard is later saved/uploaded through an explicit consent-gated path.

## Recommended Architecture

Use Firebase Firestore because the app already uses Firebase anonymous auth, online session room codes, listeners, and QR/deep-link patterns.

Add a separate collection from online gameplay sessions:

```text
scorekeeperSessions/{sessionCode}
```

Do not reuse `sessions/{sessionCode}` because online gameplay sessions include hands, pending actions, AI seats, presence, and mutable game phases that are not relevant to read-only scorecards.

### Firestore Document Shape

```json
{
  "kind": "scorekeeper",
  "schemaVersion": 1,
  "createdAt": "<server timestamp>",
  "updatedAt": "<server timestamp>",
  "expiresAt": "<timestamp>",
  "hostUid": "<anonymous Firebase uid>",
  "isClosed": false,
  "playerNames": ["Player 1", "Player 2", "..."],
  "rounds": [
    {
      "roundNumber": 1,
      "dealerIndex": 0,
      "bidderIndex": 1,
      "bidAmount": 130,
      "trumpSuit": "♠",
      "partner1Index": 2,
      "partner2Index": 3,
      "offensePointsCaught": 130,
      "createdAt": "<timestamp>"
    }
  ],
  "runningScores": [0, 130, 65, 65, 0, 0],
  "winnerIndex": 1
}
```

`runningScores` and `winnerIndex` can be derived locally, but writing them makes viewer rendering simple and keeps the viewer UI resilient if a future client version changes score derivation.

### Code Shape

Add a small sync layer instead of mixing Firestore calls into `ScorekeeperView`:

- `ScorekeeperSessionService`
  - creates a session code,
  - publishes local `ScorekeeperGameState` updates,
  - closes sessions,
  - listens as a viewer,
  - maps Firestore data to read-only view state.
- `ScorekeeperLiveSessionState`
  - `sessionCode`
  - `isPublishing`
  - `isViewerConnected`
  - `lastSyncAt`
  - `errorMessage`
- `ScorekeeperViewerView`
  - read-only scoreboard and round history,
  - no edit controls,
  - stale/closed/offline states.

Keep Phase 1 local mode as the base. Publishing should be an optional action from the active scorecard, not a required dependency.

## Join and Share Flow

Scorekeeper device:

1. User starts or resumes a local scorecard.
2. User taps `Share Live View`.
3. App creates `scorekeeperSessions/{code}` and starts publishing.
4. App shows QR code, room code, and share sheet.
5. Each scorecard change publishes a document update.
6. `Finish & Save` closes the live session and saves local history.
7. `Reset Scorecard` closes or deletes the live session.

Viewer device:

1. User scans QR code or enters room code.
2. App opens `ScorekeeperViewerView`.
3. Viewer listens to Firestore session updates.
4. If session closes, viewer sees a closed-session state with the final score.
5. If session expires or is missing, viewer sees a clear not-found/expired state.

## Deep Link

Use a distinct path from online-game join links:

```text
shadyspade://scorekeeper/{CODE}
https://shadyspade-d6b84.web.app/shadyspade/scorekeeper/{CODE}
```

Existing `MyAppApp.handleIncomingURL(_:)` only stores room codes for game joins. Phase 2 should add a separate pending deep-link field such as:

```swift
var pendingScorekeeperCode: String?
```

Do not overload `pendingJoinCode`; online game joins and scorekeeper viewers have different destinations and permissions.

## Privacy and App Review Impact

Phase 2 changes privacy behavior because player names and score data can be uploaded temporarily to Firebase for live viewing.

Before release:

- Update `APPSTORE_PRIVACY.md` data map with scorekeeper live session data.
- Update hosted privacy policy to say live score viewer data is temporarily synced through Firebase when the user chooses to share a live scorecard.
- Ensure app copy says this is optional and read-only for viewers.
- Confirm App Store Connect privacy labels still match the app behavior.

Policy language should distinguish:

- local-only Phase 1 scorekeeping,
- optional temporary live-view sync,
- consent-gated leaderboard uploads.

Live viewer sync should not imply leaderboard upload.

## Security Rules

Firestore rules should enforce one-writer/read-many semantics:

- Authenticated anonymous users can create a scorekeeper session.
- Only `hostUid` can update or close the session.
- Authenticated users can read a session by room code.
- Viewers cannot write.
- Sessions should expire with `expiresAt`.

Open question: whether unauthenticated web viewers are needed. Recommendation: not for Phase 2. Keep viewer access inside the app so Firebase anonymous auth and existing app security rules apply.

## Expiration and Cleanup

Recommended defaults:

- `expiresAt = createdAt + 24 hours`
- `Finish & Save` sets `isClosed = true` and final `updatedAt`.
- A future cleanup Cloud Function can delete expired sessions.
- Until cleanup exists, clients should treat `expiresAt < now` as expired and stop showing stale sessions.

## Implementation Batches

### Batch 1: Data Model and Service

- Add codable Firestore DTOs for live scorekeeper sessions.
- Add `ScorekeeperSessionService`.
- Add room-code generation with collision check, separate from online game sessions.
- Add model tests for DTO mapping and one-writer state transitions.

Status: complete as of 2026-07-18.

Implemented:

- Added `ScorekeeperLiveRoundDTO` and `ScorekeeperLiveSessionDocument` for Firestore mapping.
- Added `ScorekeeperSessionRemoteStore` protocol for deterministic unit tests.
- Added `FirestoreScorekeeperSessionRemoteStore` using `scorekeeperSessions/{sessionCode}`.
- Added `ScorekeeperSessionService` with:
  - six-character room-code generation,
  - uniqueness retry against `scorekeeperSessions`,
  - create session,
  - publish snapshot,
  - close session,
  - fetch session,
  - host-only, non-closed, non-expired update checks.
- Added `ScorekeeperSessionServiceTests` covering DTO round-trip mapping, collision retry, expiration, host-only update rejection, publish, and close.

Verification:

- Focused service tests passed:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.18_14-12-00--0400.xcresult`
- Scorekeeper-related unit tests passed:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.18_14-13-20--0400.xcresult`
- Full unfiltered scheme passed: `40` passed, `0` failed, `0` skipped.
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.18_14-14-33--0400.xcresult`

### Batch 2: Host Publishing UI

- Add `Share Live View` to active scorecard.
- Add session status row: not shared, publishing, live, sync failed, closed.
- Add QR/share sheet for scorekeeper viewer links.
- Publish on start, name edits, add round, edit last round, delete last round, reset, finish.

Status: complete as of 2026-07-18.

Implemented:

- Added `ScorekeeperLivePublishingController` as the host-side bridge between `ScorekeeperView` and `ScorekeeperSessionService`.
- Added explicit `Share Live View` disclosure copy before the first Firebase publish.
- Added live status card with idle, busy, error, live code, Share, Copy, and QR states.
- Added QR/share sheet using the existing QR generator and scorekeeper-specific universal-link shape.
- Publishes after scorecard mutations:
  - start sharing,
  - player-name edits,
  - add round,
  - edit last round,
  - delete last round.
- Closes the live session before reset and before finish/save.
- Added unit coverage for controller start/publish/close transitions and start failure.
- Updated the scorekeeper UI regression test to scroll before asserting round history because the new live sharing card moves history below the first viewport.
- Updated `APPSTORE_PRIVACY.md`.
- Updated and deployed the hosted privacy policy source at `/Users/vijaygoyal/MyiOSApp/shadyspade-web/privacy/index.html`.

Verification:

- Focused scorekeeper UI test passed:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.18_15-03-21--0400.xcresult`
- Full unfiltered scheme passed: `42` passed, `0` failed, `0` skipped.
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.18_15-05-38--0400.xcresult`
- Hosted privacy policy deploy succeeded:
  - Cloudflare Worker version `80a11ff8-bc66-4d3f-8eb1-740bd0c056be`
  - Live URL verified for `Last Updated: July 18, 2026`, `Live Scorekeeper`, `Share Live View`, and `Real-Life Scorekeeper`.

Remaining after Batch 2:

- Viewer UI and deep-link routing are not implemented yet.
- Firestore security rules for `scorekeeperSessions` are still pending and must be completed before production live sharing is considered ready.

### Batch 3: Viewer UI

- Add read-only `ScorekeeperViewerView`.
- Add manual room-code entry path.
- Add deep-link route for scorekeeper viewer links.
- Add closed/expired/offline/error states.

Status: complete as of 2026-07-18.

Implemented:

- Added separate scorekeeper deep-link state: `DeepLinkManager.pendingScorekeeperCode`.
- Updated URL handling for:
  - `shadyspade://scorekeeper/{CODE}`
  - `https://shadyspade-d6b84.web.app/shadyspade/scorekeeper/{CODE}`
- Added `Watch Live Scorecard` from mode selection.
- Added `ScorekeeperViewerEntryView` for manual 6-character code entry and deep-link auto-start.
- Added `ScorekeeperLiveViewingController` with states:
  - idle,
  - loading,
  - live,
  - closed,
  - expired,
  - not found,
  - invalid code,
  - sync error.
- Added Firestore snapshot observation for `scorekeeperSessions/{sessionCode}` through `ScorekeeperSessionService`.
- Added read-only viewer scoreboard and round history rendering.
- Reused `ScorekeeperRoundRow` so host and viewer history display stay consistent.
- Added unit tests for invalid-code rejection and live/closed/not-found observer transitions.
- Kept viewer read-only: no scorecard edit, add, delete, reset, or finish controls are exposed.

Verification:

- Focused scorekeeper service/viewer tests passed:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.18_15-20-21--0400.xcresult`
- Focused scorekeeper UI test passed:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.18_15-25-40--0400.xcresult`
- Full unfiltered scheme passed: `44` passed, `0` failed, `0` skipped.
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.18_15-27-47--0400.xcresult`
- `git diff --check` passed.

Remaining after Batch 3:

- Firestore security rules for `scorekeeperSessions` are still pending.
- A two-simulator/manual live host-viewer smoke is still pending until rules are in place.

### Batch 4: Privacy and Rules

- Update `APPSTORE_PRIVACY.md`.
- Update hosted privacy policy and deploy with `scripts/deploy_privacy_policy.sh`.
- Add or update Firestore security rules for `scorekeeperSessions`.
- Verify rules locally or against a development Firebase project.

Status: complete as of 2026-07-18.

Implemented:

- Added `match /scorekeeperSessions/{sessionId}` to `/Users/vijaygoyal/MyiOSApp/firestore.rules`.
- Rule behavior:
  - reads require `request.auth != null` and a valid scorekeeper session document,
  - creates require authenticated host UID ownership,
  - creates require six-character uppercase alphanumeric document IDs,
  - creates require `isClosed == false`,
  - creates require `createdAt == updatedAt`,
  - creates require `expiresAt > request.time`,
  - updates require the original host UID,
  - updates are denied after the session is closed or expired,
  - `hostUid`, `createdAt`, and `expiresAt` are immutable,
  - `updatedAt` must not go backwards,
  - deletes are denied.
- Added helper functions:
  - `isValidRoomCode(code)`
  - `isScorekeeperSession(data)`
- `isScorekeeperSession` validates the top-level document contract:
  - `kind == "scorekeeper"`
  - `schemaVersion == 1`
  - timestamp fields,
  - non-empty `hostUid`,
  - bool `isClosed`,
  - six `playerNames`,
  - `rounds` list capped at 100 entries,
  - six `runningScores`,
  - `winnerIndex` in `0..<6`.
- Nested round object validation remains app-side because Firestore rules cannot ergonomically iterate and validate every element in a variable-length rounds list.

Verification:

- Deployed rules to production Firebase:
  - `firebase deploy --only firestore:rules --project shadyspade-d6b84 --non-interactive`
- Firebase CLI output:
  - `cloud.firestore: rules file firestore.rules compiled successfully`
  - `firestore: released rules firestore.rules to cloud.firestore`
- Prior full app regression remains valid for app code:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.18_15-27-47--0400.xcresult`
  - `44` passed, `0` failed, `0` skipped.

Remaining after Batch 4:

- Run a two-simulator/device live host-viewer smoke against production Firebase:
  - host starts live scorecard,
  - viewer joins by code or QR/deep link,
  - add/edit/delete round updates viewer,
  - finish closes viewer.

### Batch 5: Regression

- Unit tests for DTO mapping, expiration, host-only write decisions, and local score derivation.
- UI test for opening viewer from a test session fixture if Firebase can be isolated.
- Full scheme test with `-enableCodeCoverage YES`.
- Manual smoke on two simulators/devices:
  - host starts live scorecard,
  - viewer joins,
  - add/edit/delete round updates viewer,
  - finish closes viewer,
  - expired code shows expired state.

Status: substantially complete as of 2026-07-18.

Implemented and verified:

- Added viewer-state coverage for expired sessions.
- Hardened troubleshooting copy:
  - invalid code asks for exactly the six-character code shown on the scorekeeper device,
  - missing code includes the attempted code and tells the viewer to confirm the host shows `Live View On`,
  - closed/expired/sync banners now tell the viewer what to do next.
- Added accessibility labels/identifiers for live sharing controls:
  - live code,
  - share link,
  - copy code,
  - QR sheet,
  - close viewer,
  - change code.
- Fixed mode-card title wrapping so `Real-Life Scorekeeper` does not truncate on iPhone 17.
- Full scheme with code coverage passed:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.18_20-50-19--0400.xcresult`
  - `44` unit tests passed,
  - `1` UI test passed,
  - `0` failures,
  - `0` skipped.
- Coverage target summary from that run:
  - `MyApp.app`: 9.23% (`6080/65685`)
  - `MyAppTests.xctest`: 95.59% (`1213/1269`)
  - `MyAppUITests.xctest`: 90.00% (`81/90`)
- Latest build installed and launched on both booted simulators:
  - iPhone 17 Pro `DA97985A-F7CC-44F6-8281-9DD24C22B978`
  - iPhone 17 `11AFDD37-BF1B-4BAB-8679-1B570C5530EC`
- Visual smoke screenshots captured:
  - `/private/tmp/shadyspade-17pro-final.png`
  - `/private/tmp/shadyspade-17-final.png`

Lifecycle decision:

- Keep scorekeeper live sessions temporary.
- `Share Live View` creates a session with `expiresAt = createdAt + 24 hours`.
- `Finish & Save` and `Reset Scorecard` close the active live session.
- Firestore rules deny host updates after close or expiry.
- Client viewers show closed/expired states rather than stale editable UI.
- Deleting expired documents remains a future backend cleanup task, best handled by a scheduled Cloud Function or similar server job.

Remaining optional hardening:

- Add a Firebase-isolated UI test fixture for viewer entry states if the project gets a test Firebase emulator setup.
- Add backend cleanup for expired `scorekeeperSessions`.
- Add manual real-device smoke before App Store release if live score viewing is intended for the next submitted build.

## Non-Goals for Phase 2

- Multi-device editing.
- Viewer chat/reactions.
- Leaderboard upload changes.
- Web browser viewers outside the app.
- Public searchable scorecards.
- Account creation or named viewer identity.

## Open Questions

- Should viewers see the current unsaved round draft, or only saved rounds?
  - Recommendation: only saved rounds in Phase 2.
- Should a live scorecard require an explicit confirmation before publishing player names?
  - Recommendation: yes, a short disclosure in `Share Live View`.
- Should sharing be available before Round 1?
  - Recommendation: yes, viewers can see initial names and zero scores.
- Should expired sessions be deleted immediately by the app?
  - Recommendation: host can mark closed, but server cleanup should own deletion later.

## Recommended First Implementation Step

Start with Batch 1 only:

1. Create `ScorekeeperSessionService`.
2. Add Firestore DTO mapping from `ScorekeeperGameState`.
3. Add unit tests for mapping, expiration, and host-only update intent.
4. Do not add UI until the data contract is stable.
