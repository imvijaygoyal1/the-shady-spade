# Published Final Scorecards

## Goal

Let a Real-Life Scorekeeper host publish a final read-only scorecard that viewers can open later by link/code, without reusing temporary live scorekeeper sessions or in-app online game sessions.

## Data Separation

- `sessions/{code}` remains for active in-app Online gameplay.
- `scorekeeperSessions/{code}` remains for temporary live scorekeeper viewing.
- `publishedScorecards/{code}` is the new final scorekeeper history collection.

Published scorecards use:

- `kind = "publishedScorecard"`
- `sourceType = "scorekeeper"`
- player names, rounds, running scores, winner, started/finished/published dates
- optional `sourceLiveSessionCode`
- `isDeleted` for future unpublish/delete support

## App Flow

- Host taps `Finish & Save`.
- Confirmation now offers:
  - `Save & Share Final Scorecard`
  - `Save to History`
  - `Cancel`
- Local-only save keeps previous behavior.
- Save/share closes any active live view, creates `publishedScorecards/{code}`, shows QR/share UI, then saves local history and clears the active scorecard when the share sheet closes.
- After share completion, the app shows a `Game Saved` screen with:
  - `View Local History`
  - `View Shared Scorecard`
  - `Return Home`
- `View Local History` opens the just-saved `GameHistoryDetailView` directly so a fresh save does not appear as a blank history screen before persistence/navigation catches up.

## Link Flow

Added final scorecard routes:

- `shadyspade://scorecard/{CODE}`
- `https://shadyspade.vijaygoyal.org/scorecard/{CODE}`
- legacy-compatible `https://shadyspade-d6b84.web.app/shadyspade/scorecard/{CODE}`

`DeepLinkManager.pendingPublishedScorecardCode` drives a separate `PublishedScorecardViewerEntryView`.

## Hosted Fallback

Added source fallback page:

- `/Users/vijaygoyal/MyiOSApp/shadyspade-web/scorecard/index.html`

Updated AASA source and deploy script routing for `/scorecard/*`, `/SCORECARD/*`, and `/shadyspade/scorecard/*`.

Deployment completed:

- Firestore rules deployed to Firebase project `shadyspade-d6b84`.
- Hosted privacy/AASA/fallback site deployed to Cloudflare.
- Latest deployed Cloudflare version from this work: `040866fc-0b2d-495c-b802-bc6c9a296353`.
- Live AASA and scorecard fallback routes were verified.
- Physical-device QR scan for final scorecard links was manually verified to open the app.

## Privacy

This is a privacy-impacting feature because final player names, scores, round history, winner, and dates can be uploaded to Firebase and viewed by anyone with the link.

Updated:

- `APPSTORE_PRIVACY.md`
- `/Users/vijaygoyal/MyiOSApp/shadyspade-web/privacy/index.html`

The privacy policy source now says final scorecards are explicit, user-started, read-only, and separate from temporary live scorekeeper sessions and leaderboard upload consent.

## Verification

- Unit/link/service regression:
  - `build/published-scorecards-unit-rerun.xcresult`
  - `29` tests, `0` failures.
- Scorekeeper UI regression:
  - `build/published-scorecards-scorekeeper-ui.xcresult`
  - `4` tests, `0` failures.
- Saved share/local-history regression:
  - `build/scorekeeper-saved-history-detail-ui-fixed.xcresult`
  - `1` test, `0` failures, `0` skips.
- Full scorekeeper UI regression:
  - `build/scorekeeper-flow-with-saved-summary.xcresult`
  - `5` tests, `0` failures, `0` skips.
- `bash -n scripts/deploy_privacy_policy.sh` passed.
- `git diff --check` passed.

## Remaining

- Optional future work: add unpublish/delete support for final scorecards using the existing `isDeleted` field.
- Optional future work: add a full end-to-end hosted link test once Apple universal-link association refresh behavior can be reliably controlled in automation.
