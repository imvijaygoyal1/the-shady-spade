# v2.0 (17) — submission pack

Everything App Store Connect needs, prepared 2026-09-22. Paste the sections below into the
matching ASC fields. **Nothing here is invented** — it is drawn from the v2.0 changelog, the
privacy data map in `APPSTORE_PRIVACY.md`, and the Group B device pass.

State at submission: 256 unit + 24 UI tests green; Group B passed in full on hardware;
IPA at `~/MyiOSApp/exports/TheShadySpade-2.0-17.ipa`, verified from the artifact
(`get-task-allow` false, Apple Distribution on both the app and the embedded Watch app,
both at 2.0 (17)).

---

## 1. What's New in This Version

> Paste into **What's New**. This is the first release since v1.10, and the first ever to
> contain the Apple Watch app — lead with that.

```
Apple Watch companion — keep score from your wrist. Add a round, undo the last one, and
see running totals without picking up your phone.

Real-Life Scorekeeper — playing with physical cards? Track a six-player game in the app.
Record the dealer, winning bidder, partners, called cards, bid and result, and the app
does the scoring for you.

Share a live scorecard — let anyone follow along read-only with a six-character code or a
link, then save and share a final scorecard when the game ends.

Also in this release:
• Themes — Casino Night, Midnight Blue and Parchment, with Dark, Light or System
• A guided first game for new players
• Full iPad and landscape support across every screen
• Scan a QR code or tap an invite link to join a game instantly
• A round-by-round review after every hand, showing who caught which points
• Smarter AI opponents that read the table instead of playing at random
```

---

## 2. App Review Notes

> Paste into **Notes for Review**. The leaderboard-consent path is the first thing to list:
> v1.9 was rejected under 5.1.2 for uploading leaderboard data without explicit consent, and
> reviewers need the exact steps to confirm it is fixed.

```
No account or sign-in is required. No demo account is needed.

VERIFYING LEADERBOARD CONSENT (the 5.1.2 fix)

Nothing is uploaded to the global leaderboard unless the player explicitly allows it.

1. Install and open the app. Tap New Game, choose 1 player, and finish one round.
2. At the round-complete screen, a consent sheet appears before any upload. It names
   exactly what would be sent: chosen player names, avatars, game mode, bids, scores and
   round results, uploaded to our Firebase server.
3. Choose "Play Without Uploading Scores". Nothing is uploaded, and the score-save row
   states that scores were not saved.
4. Open Settings. The leaderboard toggle is off. Turning it on re-opens the same consent
   sheet rather than silently enabling uploads.
5. Choose "Allow Score Uploads" to enable it. Only then do completed rounds upload.

Dismissing the consent sheet by swiping counts as a refusal, not consent.

APPLE WATCH COMPANION

The Watch app is a companion to Real-Life Scorekeeper and needs a paired iPhone. To try it:
open Real-Life Scorekeeper on the iPhone, enter six player names, tap Start, then open the
app on the Watch. The Watch shows the active scorecard and can add or undo a round. The
iPhone remains the source of truth; the Watch sends actions to it over WatchConnectivity
and nothing is sent to a server by the Watch.

CAMERA AND LOCAL NETWORK

Camera is used only when the player taps "Scan QR Code" to read a room code for joining a
game. Local networking is used only for Local/Bluetooth multiplayer, to find nearby players
over MultipeerConnectivity. Neither is used for tracking, and the app requests them only at
the point of use.

SHARED SCORECARDS

"Share Live View" and "Save & Share Final Scorecard" are both explicit, confirmed actions.
Each produces a read-only scorecard anyone with the link can view. Live sessions expire
after 24 hours and are deleted by a scheduled cleanup; final scorecards are durable by
design because the link is meant to be kept.
```

---

## 3. Privacy labels — confirm these match

From the data map in `APPSTORE_PRIVACY.md`. **Nothing is used for tracking, and nothing is
linked to an identity** — there are no accounts; Firebase anonymous auth provides only a
token.

| ASC data type | Collected | Linked | Tracking | Why |
|---|---|---|---|---|
| Name (avatar name) | Yes | No | No | App Functionality — only when the player allows leaderboard uploads, or during an Online game |
| Gameplay Content | Yes | No | No | App Functionality — scores, bids, round results, shared scorecards |
| Identifiers | No | — | — | Anonymous auth token only; no advertising or user ID |
| Contacts / Location / Health / Financial / Browsing | No | — | — | Not accessed |

The shipped `PrivacyInfo.xcprivacy` declares exactly two collected types — Name and Gameplay
Content, both unlinked and non-tracking — plus a UserDefaults API reason (`CA92.1`), with
`NSPrivacyTracking` false and no tracking domains. **The ASC labels must match that, not
exceed it.**

---

## 4. Screenshots — ⚠️ check before submitting

**The Watch app ships for the first time in this release, so App Store Connect will require
Apple Watch screenshots.** Previous submissions had none, because there was no Watch app.

- [ ] iPhone 6.9" / 6.7" — required
- [ ] iPad 13" — required, the app supports iPad
- [ ] **Apple Watch — required now, and new for this release**

Good Watch screens to capture: the active scorecard with six players, and the Add Round
screen showing the called-card pickers.

---

## 5. Submission steps

1. **Upload** — Xcode → Window → Organizer → the 2.0 (17) archive → Distribute App → App
   Store Connect. Or Transporter with `~/MyiOSApp/exports/TheShadySpade-2.0-17.ipa`.
2. In ASC, select build **17** for version **2.0**.
3. Paste sections 1 and 2; confirm section 3; complete section 4.
4. Confirm the Privacy Policy URL is `https://shadyspade.vijaygoyal.org/privacy` (live,
   dated 2026-09-12, and it covers consent, called cards and scorekeeper sharing).
5. Submit.
6. **Tag it, at submission time** — the standing rule, because the v1.10 boundary had to be
   reconstructed by inference for want of one:

   ```bash
   git tag -a v2.0-build17 <submitted-commit> -m "2.0 (17) — SUBMITTED $(date +%F)"
   git push origin v2.0-build17
   git tag -d v2.0-build17-prep && git push origin :v2.0-build17-prep
   ```

7. Amend that tag with APPROVED or REJECTED (plus the guideline) when Apple responds.

---

## 6. Not done here, and why

**The upload itself.** This machine has no App Store Connect API key
(`~/.appstoreconnect/private_keys` is empty), no stored ASC credential, and no Transporter
install, so `altool` cannot authenticate. Uploading needs your Apple ID, from Xcode or
Transporter.

**The ASC-side checks** — labels, screenshots, metadata — are all in the web console.

**The Settings consent walkthrough** in section 2 is written from the shipped code paths
(all three upload sites guard on `LeaderboardConsentManager.shared.isGranted`) but has not
been re-walked on a device for this build. It is worth doing once before submitting, since
it is the exact path that caused the v1.9 rejection.
