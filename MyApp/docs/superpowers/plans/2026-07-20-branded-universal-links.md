# Branded Universal Links for QR and SMS Invites

Date: 2026-07-20

## Goal

Allow players to join Online games and read-only Real-Life Scorekeeper sessions from links scanned outside the app, especially iPhone Camera QR scans and SMS/iMessage invite taps.

Canonical host:

```text
https://shadyspade.vijaygoyal.org
```

Canonical routes:

```text
/join/{CODE}
/scorekeeper/{CODE}
```

## Analysis

- The app already had a generic deep-link parser in `AppDeepLinkRouter` that can route URLs containing `join/{CODE}` or `scorekeeper/{CODE}`.
- The app was still generating Firebase Hosting links for QR/share flows.
- Release and debug entitlements did not include `applinks:shadyspade.vijaygoyal.org`.
- The branded domain did not serve a live AASA file before this work.
- SMS support does not require SMS-reading permission. The correct implementation is a normal HTTPS universal link that iOS opens from Messages.
- Camera support outside the app does not require in-app camera access. The correct implementation is a QR code containing the same HTTPS universal link; iOS Camera resolves it through Associated Domains.

## Implementation

- Added `ShadySpadeLinks` as the single source for branded join and scorekeeper URLs.
- Updated Online game sharing and QR generation to use `https://shadyspade.vijaygoyal.org/join/{CODE}`.
- Updated Real-Life Scorekeeper live sharing to use `https://shadyspade.vijaygoyal.org/scorekeeper/{CODE}`.
- Added `applinks:shadyspade.vijaygoyal.org` to both app entitlements.
- Kept legacy Firebase associated domains and parser support so old invites continue to work.
- Added AASA files at:
  - `shadyspade-web/.well-known/apple-app-site-association`
  - `shadyspade-web/apple-app-site-association`
- Added fallback pages:
  - `shadyspade-web/join/index.html`
  - `shadyspade-web/scorekeeper/index.html`
- Updated the Cloudflare deploy script to publish a Worker shim that:
  - serves AASA as `application/json`
  - routes `/join/{CODE}` to the join fallback page
  - routes `/scorekeeper/{CODE}` to the scorekeeper fallback page
  - keeps `.wrangler` cache files out of production
- Updated privacy documentation to describe branded universal links.

## Tests

Covered by unit tests:

- branded join route parsing
- branded scorekeeper route parsing
- canonical branded URL generation
- Online QR scan normalization for branded URLs
- scorekeeper share URL generation

Executed:

- Focused link-related tests passed:
  - `MyAppTests/AppRegressionTests`
  - `MyAppTests/OnlineSessionViewModelTests`
  - `MyAppTests/ScorekeeperSessionServiceTests`
- Full scheme with code coverage passed:
  - Result bundle: `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.20_19-34-39--0400.xcresult`
  - `115` passed, `0` failed, `0` skipped
  - Raw app coverage: `11.92%`
  - Logic-focused coverage: `35.29%`

Hosted verification:

- Deployed Cloudflare Worker/static assets version: `298884cb-5e59-44bc-a4f6-c12a7c5a4f24`
- Live AASA verified at `https://shadyspade.vijaygoyal.org/.well-known/apple-app-site-association`
- AASA response verified as `content-type: application/json`
- `/join/ABC123` fallback verified with embedded code `ABC123`
- `/scorekeeper/HOST01` fallback verified with embedded code `HOST01`
- Hidden `.wrangler` cache path verified as `404`

Manual checks still required on a physical iPhone:

- Scan a generated Online game QR code with the iOS Camera app.
- Tap a branded join link from Messages.
- Tap a branded scorekeeper link from Messages.
- Confirm installed app opens directly and routes to the right flow.

Simulator testing can verify parsing, generated URLs, fallback pages, and app launch behavior, but it cannot fully prove Apple's live universal-link association cache and Camera-app behavior.
