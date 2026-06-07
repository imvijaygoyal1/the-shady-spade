# Leaderboard Simplification

## Goal
Make the leaderboard easier to scan without changing how scores are recorded,
synced, listened to, or retried.

## Implementation
- Kept `LeaderboardService` unchanged for this pass.
- Kept `service.startListening()` in `LeaderboardView` so live leaderboard updates
  continue to flow through the existing Firestore listener.
- Replaced the two-tab leaderboard layout with a rankings-first screen.
- Moved sort and mode selection into compact menus.
- Moved recent game history into a secondary sheet.
- Simplified player rows to rank, name, games, wins, total points, and a detail
  affordance.
- Preserved the player detail sheet for deeper stats.

## Verification
- `xcodebuild -quiet -project MyApp.xcodeproj -scheme MyApp -destination 'generic/platform=iOS Simulator' build`
- Installed and launched on the booted simulator with PID `66134`.
- Captured smoke-check screenshot at `/private/tmp/shadyspade-leaderboard-simplify-check.png`.
