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

### Batch 2: Host Publishing UI

- Add `Share Live View` to active scorecard.
- Add session status row: not shared, publishing, live, sync failed, closed.
- Add QR/share sheet for scorekeeper viewer links.
- Publish on start, name edits, add round, edit last round, delete last round, reset, finish.

### Batch 3: Viewer UI

- Add read-only `ScorekeeperViewerView`.
- Add manual room-code entry path.
- Add deep-link route for scorekeeper viewer links.
- Add closed/expired/offline/error states.

### Batch 4: Privacy and Rules

- Update `APPSTORE_PRIVACY.md`.
- Update hosted privacy policy and deploy with `scripts/deploy_privacy_policy.sh`.
- Add or update Firestore security rules for `scorekeeperSessions`.
- Verify rules locally or against a development Firebase project.

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
