# Theme, Leaderboard, and Multiplayer Polish Implementation Record

**Goal:** Implement the next practical improvements after app-wide themes: theme status-color polish, better leaderboard UX, and clearer multiplayer resilience/status UI.

**Status:** Implemented on 2026-06-06.

## Changes

### Theme Polish

- Added semantic status tokens to `ThemeColours`:
  - `successColor`
  - `warningColor`
  - `passColor`
  - `waitingColor`
  - `activeTurnColor`
- Populated those tokens in all current palettes:
  - Casino Night light/dark
  - Midnight Blue light/dark
  - Parchment light/dark
- Routed high-visibility status colors through tokens:
  - Live turn dot
  - Waiting turn banners
  - Score save success/pending pills
  - Leaderboard bid-rate success color
  - TV active-player status
  - Bluetooth reconnect warning pill

### Leaderboard UX

- Added client-side mode filtering in `LeaderboardView`:
  - All
  - Solo
  - Online
  - Bluetooth
  - Pass & Play
- Added summary metric pills for filtered player stats.
- Added tap-through player detail sheet with games, wins, total points, average points, bid success, and last mode.
- Added filter-aware empty states for both stats and game log.
- Replaced remaining partner-row hardcoded blue with the themed offense token.

### Multiplayer Resilience UI

- Added reusable `MultiplayerStatusPill`.
- Online gameplay now shows a compact active status pill with host/player role, round, human count, and AI count.
- Online lobby now shows host/joined lobby context and explains invite/AI behavior.
- Bluetooth gameplay now shows host/player/migration status and clearer reconnect/migration messaging.
- Bluetooth host/client lobbies now show readiness and host-control context.

## Verification

Passed:

```bash
xcodebuild -quiet -project MyApp.xcodeproj -scheme MyApp -destination 'generic/platform=iOS Simulator' build
```

Installed and launched on the booted simulator:

```bash
xcrun simctl install booted /Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Build/Products/Debug-iphonesimulator/MyApp.app
xcrun simctl launch booted com.vijaygoyal.theshadyspade
```

Launch returned PID `65796`. Screenshot smoke check:

```bash
xcrun simctl io booted screenshot /private/tmp/shadyspade-ui-check.png
```

Observed Settings rendering with Appearance controls and three theme swatches.

## Follow-Up

- Run deeper visual QA through live Solo, Online, Bluetooth, and TV gameplay screens in all three themes.
- Consider adding per-theme tokens for card highlight backgrounds if future QA finds contrast issues.
- Continue decorative hardcoded-color cleanup only where it affects readability or theme coherence; avoid churn on purely fixed card/suit colors unless needed.
