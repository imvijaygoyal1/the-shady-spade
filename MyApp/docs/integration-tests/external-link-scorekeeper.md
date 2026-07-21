# External Link and Scorekeeper Integration Tests

Date: 2026-07-21
App: The Shady Spade

## Purpose

This integration setup covers the parts of QR, SMS/universal links, and Real-Life Scorekeeper that cross app boundaries.

Normal unit/UI tests already verify URL parsing, generated branded URLs, join-screen rendering, scorekeeper setup, seeded scorekeeper history, and seeded live viewer rendering. This integration layer adds simulator-driven OS handoff checks and a physical-device checklist for Camera and Messages.

## Automated Simulator Smoke

Run from the repo root:

```bash
MyApp/scripts/run_external_link_integration.sh
```

Common options:

```bash
MyApp/scripts/run_external_link_integration.sh --device "iPhone 17"
MyApp/scripts/run_external_link_integration.sh --join ABC123 --scorekeeper VIEW01
MyApp/scripts/run_external_link_integration.sh --skip-hosted
MyApp/scripts/run_external_link_integration.sh --skip-xctests
MyApp/scripts/run_external_link_integration.sh --skip-build
```

The script:

- checks the hosted AASA file and fallback pages on `https://shadyspade.vijaygoyal.org`
- runs focused link/scorekeeper regression tests
- builds and installs the app on a booted simulator
- launches the app in UI-test-safe mode
- opens branded universal links with `xcrun simctl openurl`
- opens custom-scheme fallback links with `xcrun simctl openurl`
- captures screenshots under `MyApp/build/integration-artifacts/...`

Review screenshots:

- `01-universal-join-*.png`: branded join-link result
- `02-universal-scorekeeper-*.png`: branded scorekeeper-link result
- `03-custom-join-*.png`: custom-scheme join result
- `04-custom-scorekeeper-*.png`: custom-scheme scorekeeper result

On simulators, branded universal links may open Safari fallback pages instead of the app. That does not by itself prove the production feature is broken, because Associated Domains are cached and simulator `openurl` does not model Camera/Messages exactly. Treat these screenshots as evidence to review. Physical-device validation remains required for Camera and Messages.

## What This Proves

- The hosted AASA and fallback pages are reachable and contain the expected app ID/code.
- The app still parses branded join and scorekeeper links.
- The app still renders join and scorekeeper viewer surfaces.
- A simulator can hand URLs to iOS via `simctl openurl`, with screenshots showing whether the app, Safari fallback, or an iOS confirmation prompt appeared.

## What Still Requires Physical Device Validation

These are Apple system app behaviors and cannot be fully proven by XCTest alone:

- iPhone Camera app scanning a QR code and offering/opening the universal link.
- Messages/SMS rendering a branded invite URL and opening the installed app when tapped.
- Universal-link association cache behavior on a freshly installed production/TestFlight build.

## Manual Device Checklist

Use a real iPhone with the installed app.

1. Install the app.
2. Open Safari and visit:
   `https://shadyspade.vijaygoyal.org/.well-known/apple-app-site-association`
   Confirm it downloads/displays JSON, not HTML.
3. Start an Online game and open the QR/share screen.
4. Scan the QR with the iPhone Camera app from outside The Shady Spade.
5. Tap the detected link.
6. Confirm The Shady Spade opens directly to the join flow with the expected code.
7. Send the branded join URL through Messages/SMS.
8. Tap the Messages/SMS link.
9. Confirm The Shady Spade opens directly to the join flow with the expected code.
10. Start Real-Life Scorekeeper Live View on one device.
11. Send or scan the scorekeeper URL from another device.
12. Confirm the viewer opens as read-only and shows the expected live scorecard code.
13. Add/edit/delete a round on the scorekeeper host.
14. Confirm the viewer updates.

## Notes

- If a universal link opens Safari instead of the app, delete and reinstall the app, then retry after a few seconds. iOS caches associated-domain decisions.
- The custom scheme fallback uses `shadyspade://join/{CODE}` and `shadyspade://scorekeeper/{CODE}`.
- The canonical production URLs are:
  - `https://shadyspade.vijaygoyal.org/join/{CODE}`
  - `https://shadyspade.vijaygoyal.org/scorekeeper/{CODE}`
