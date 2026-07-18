# App Store Privacy

This file is the source of truth for The Shady Spade privacy review surfaces. Check it before completing any change involving data collection, storage, upload, Firebase, leaderboard, camera, contacts, photos, notifications, accounts, analytics, or third-party services.

## Live Privacy Policy

URL: https://shadyspade.vijaygoyal.org/privacy

## Privacy Policy Source

File: `/Users/vijaygoyal/MyiOSApp/shadyspade-web/privacy/index.html`

Related static pages:

- `/Users/vijaygoyal/MyiOSApp/shadyspade-web/index.html`
- `/Users/vijaygoyal/MyiOSApp/shadyspade-web/support/index.html`

## Deployment

Cloudflare Worker: `winter-band-18fa`

Domain: `shadyspade.vijaygoyal.org`

Use the deploy script instead of deploying directly from `shadyspade-web`:

```bash
./scripts/deploy_privacy_policy.sh
```

Reason: `shadyspade-web` can contain local `.wrangler` cache files. The script copies only public files into a clean temporary directory before deploying.

Manual equivalent:

```bash
tmpdir=/private/tmp/shadyspade-web-clean
rm -rf "$tmpdir"
mkdir -p "$tmpdir"
cp -R /Users/vijaygoyal/MyiOSApp/shadyspade-web/index.html \
  /Users/vijaygoyal/MyiOSApp/shadyspade-web/privacy \
  /Users/vijaygoyal/MyiOSApp/shadyspade-web/support \
  "$tmpdir"
npx wrangler deploy "$tmpdir" \
  --name winter-band-18fa \
  --assets "$tmpdir" \
  --compatibility-date 2026-06-22 \
  --domain shadyspade.vijaygoyal.org
```

## Verification

After every privacy policy deploy:

```bash
curl -L https://shadyspade.vijaygoyal.org/privacy | rg "Last Updated|Allow Score Uploads|Play Without Uploading Scores|only if you allow score uploads"
curl -I https://shadyspade.vijaygoyal.org/.wrangler/cache/wrangler-account.json
```

Expected:

- The live policy contains the latest date and consent-gated leaderboard language.
- The `.wrangler` cache URL returns `404`.

## Privacy Data Map

| Data | Source | Stored Local | Uploaded | Third Party | Consent | Policy Section |
|---|---|---:|---:|---|---|---|
| Avatar name | User entry | Yes | Only if leaderboard uploads are allowed, or during Online game sync | Firebase | Yes for leaderboard upload | Sections 2, 3, 8 |
| Avatar selection | User selection | Yes | Only if leaderboard uploads are allowed | Firebase | Yes for leaderboard upload | Sections 2, 3, 8 |
| Scores and round results | Gameplay | Yes | Only if leaderboard uploads are allowed | Firebase, Google Cloud Functions | Yes | Sections 2, 3, 7, 8 |
| Game mode and bid history | Gameplay | Yes | Only if leaderboard uploads are allowed | Firebase, Google Cloud Functions | Yes | Sections 2, 3, 7, 8 |
| Online session code | Online mode | Temporary | Yes, for game session sync | Firebase | User starts or joins Online mode | Sections 2, 3, 8 |
| Online game actions | Online mode gameplay | Temporary | Yes, for game session sync | Firebase | User starts or joins Online mode | Sections 3, 8 |
| Anonymous auth token | Firebase anonymous auth | Yes | Yes, authentication metadata | Firebase | App functionality, no account data | Sections 2, 7 |
| Camera QR scan | User taps Scan QR Code | No | No | Apple AVFoundation | iOS camera permission | Section 2 |
| Local network TV dashboard data | Bluetooth host opt-in | Temporary | Local network only | None | User starts dashboard | Sections 2, 4, 8 |
| Theme and display preferences | Settings | Yes | No | None | User setting | Sections 2, 7 |

## Review-Sensitive Rules

- Leaderboard records must not be stored, queued, flushed, or uploaded unless leaderboard consent is granted.
- App copy, privacy policy, App Store privacy labels, and App Review notes must describe the same behavior.
- Avoid automatic-upload wording unless upload actually happens without user consent.
- If the app behavior changes, update the hosted privacy policy and verify the live URL before resubmission.
