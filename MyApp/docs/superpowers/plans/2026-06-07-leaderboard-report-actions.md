# Leaderboard Report Actions

## Goal
Add a visible moderation path for public leaderboard names and recent game-log
rows without changing leaderboard write behavior or adding new collected report
data.

## Implementation
- Added `LeaderboardReportMail` in `LeaderboardView.swift`.
- Player detail sheets now show `Report Player Name`.
- Recent game cards now show a compact flag menu with report links for the game
  entry, bidder, partners, and defense names.
- Report links open the user's mail app with support email, subject, player name,
  source, game mode, round, bid result, scores, and a blank reason field
  prefilled.

## Privacy and App Review Notes
- This is a user-initiated support email flow, not an in-app account or stored
  Firestore report collection.
- No `LeaderboardService` save path, Cloud Function payload, Firestore listener,
  privacy manifest, or App Store privacy label change was required.
- If the app later switches to Firestore-stored reports, update the hosted
  privacy policy, retention notes, and review notes before shipping.

## Verification
- `git diff --check` passed.
- `xcodebuild -quiet -project MyApp.xcodeproj -scheme MyApp -destination 'generic/platform=iOS Simulator' build` passed.
