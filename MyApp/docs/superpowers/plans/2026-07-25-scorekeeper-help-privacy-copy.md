# Scorekeeper Help And Privacy Copy

## Goal

Align the in-app How to Play guidance, App Store privacy source of truth, hosted privacy policy, and privacy deploy verification with the published scorekeeper scorecard behavior.

## Updates

- Added a dedicated How to Play topic for `Scorekeeper Tools`.
- Clarified that Real-Life Scorekeeper tracks physical-table games without playing cards inside the app.
- Clarified that one host device owns score entry, while live scorecard viewers are read-only.
- Clarified that `Share Live View` creates a temporary viewer code/QR link.
- Clarified that `Save to History` keeps a local final scorecard.
- Clarified that `Save & Share Final Scorecard` saves local history and publishes a final read-only link.
- Updated the hosted privacy policy source to distinguish temporary online/game live sessions from durable published final scorecards.
- Updated `APPSTORE_PRIVACY.md` and `scripts/deploy_privacy_policy.sh` verification commands so future checks assert temporary-session cleanup and published-scorecard retention wording.

## Privacy

Privacy-impacting copy update only. No new data collection, permission, Firebase collection, analytics, or third-party service was added in this change.

The policy now says:

- Temporary online game sessions are deleted when the game session ends.
- Temporary live scorekeeper sessions expire automatically within 24 hours or when the host finishes, resets, or closes live sharing.
- Published final scorecards remain available to anyone with the final scorecard link unless removed or deleted after a support request.

## Deployment

The hosted privacy site was redeployed to Cloudflare Worker `winter-band-18fa`.

Deploy output reported version:

- `f42e39aa-961b-44f9-8a3d-c0323c69551f`

Live verification passed for:

- `https://shadyspade.vijaygoyal.org/privacy`
- `https://shadyspade.vijaygoyal.org/privacy/index.html`

Both returned `Last Updated: July 25, 2026`, the temporary-session cleanup wording, and the published-final-scorecard retention wording.

## Verification

- `git diff --check` passed.
- `ScreenCatalogUITests/testHowToPlayScreenCatalog` passed with `1` test, `0` failures, `0` skips in `build/how-to-play-scorekeeper-copy.xcresult`.
