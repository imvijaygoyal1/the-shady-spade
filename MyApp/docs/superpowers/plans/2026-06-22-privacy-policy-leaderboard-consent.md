# Privacy Policy Leaderboard Consent Reconciliation

## Context

Apple rejected The Shady Spade under Guideline 5.1.2 because leaderboard score data was uploaded without clear prior consent. The app-side fix added an explicit leaderboard consent sheet and upload guards, but the hosted privacy policy still described leaderboard uploads as automatic at game end.

## Changes

- Updated the hosted privacy policy source at `/Users/vijaygoyal/MyiOSApp/shadyspade-web/privacy/index.html`.
- Changed the Last Updated and Last Revised dates to June 22, 2026.
- Clarified that leaderboard uploads happen only if the user allows score uploads.
- Documented the `Allow Score Uploads` and `Play Without Uploading Scores` choices.
- Updated Global Leaderboard, Firebase, Data Retention, Game Modes, and Your Rights language to avoid implying automatic score upload.
- Clarified that offline pending leaderboard records are queued only after consent has been granted.

## Deployment

- Existing Cloudflare Worker custom domain:
  - Worker: `winter-band-18fa`
  - Domain: `https://shadyspade.vijaygoyal.org`
- Deployed from a clean temporary static folder containing only `index.html`, `privacy/`, and `support/`.
- Corrective deploy was needed because deploying directly from `shadyspade-web` initially included local `.wrangler` cache files in the asset manifest.

## Verification

- Live policy URL contains the new consent-gated copy:
  - `https://shadyspade.vijaygoyal.org/privacy`
- Verified live text includes:
  - `Last Updated: June 22, 2026`
  - `Your chosen game name and stats upload only if you allow score uploads.`
  - `Before leaderboard score uploads are enabled, the app asks for your consent...`
  - `Play Without Uploading Scores`
- Verified accidental `.wrangler` cache path returns `404` after the clean deploy.

## Reusable Rule

For App Store privacy/rejection fixes, reconcile all four surfaces before resubmission:

- App UI disclosure.
- Upload/storage guards.
- Hosted privacy policy.
- App Review notes.
