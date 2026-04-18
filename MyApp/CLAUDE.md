# The Shady Spade — Claude Code Context

> **IMPORTANT FOR CLAUDE:** After every code change to this project, update this file to reflect the change. New file → add to File Map. New component → add to Styles section. Changed pattern → update Key Patterns. Version bump → update App Identity. This file must always stay current.
> **RELEASE TRACKING:** v1.6 (build 7) submitted to App Store on April 16, 2026 — under review. Log all new changes under a **v1.7 Changelog** section. Do not increment the version number until the user confirms v1.7 is ready to submit.

## v1.7 Changelog
> Changes made after v1.6 App Store submission (April 16, 2026). Add entries here as changes are implemented.

- [2026-04-17] Remove all themes except Casino Night — deleted SunsetSocialTheme, ComicBookTheme, MinimalDarkTheme, MinimalLightTheme from `Themes.swift` (kept only ClassicGreenTheme); emptied `PremiumThemes.swift` (MidnightNoir, RoyalCrimson, DiamondClub, BaroqueGold, NeonUnderground) and `CasinoRoyaleTheme.swift`. `ThemeManager.availableThemes` now contains only `ClassicGreenTheme()`, default and fallback both point to it. Removed APPEARANCE (theme picker) and DISPLAY MODE sections from `SettingsView` — both were useless with a single fixed-dark theme. Updated How To Play "Avatars & Themes" text to mention Casino Night only. (`Themes.swift`, `PremiumThemes.swift`, `CasinoRoyaleTheme.swift`, `ThemeManager.swift`, `SettingsView.swift`)
- [2026-04-17] Bug fix #2 — `waitForNextHand()` branched on `humanPlayerIndices.count > 1` at runtime; if a solo game ever had multiple entries (init bug), it would auto-advance after 5s instead of waiting for the "Next Hand" tap — `humanReadyForNextHand()` would never fire. Added `var isPassAndPlay: Bool = false` to `ComputerGameViewModel`; the P&P init (`init(humanSeats:...)`) sets it to `humanSeats.count > 1`. Replaced both runtime `humanPlayerIndices.count > 1` checks (sleep duration + next-hand branch) with `isPassAndPlay`. Also removed stale debug `print` statements from `waitForNextHand`. (`ComputerGameViewModel.swift`)
- [2026-04-17] Bug fix #7 — BT `isMyTurn` had `&& phase == .playing`, making it always `false` during `.bidding` and `.calling`; BT views that gate bid/call controls on `game.isMyTurn` never rendered those controls for the current action player. Removed the phase restriction — `isMyTurn` now matches Online: `myPlayerIndex == currentActionPlayer`. (`BluetoothGameViewModel.swift:131`)
- [2026-04-17] Bug fix #4 — Online AI had no recovery path when `processAITurnIfNeeded`'s post-sleep guard fired (state changed during the 800–1200ms delay). The function just returned, leaving the AI permanently frozen if no new Firestore snapshot arrived. Added a recovery block inside the guard: if another AI seat is the current action player in an active phase (`.bidding`, `.calling`, `.playing`), re-calls `processAITurnIfNeeded()` before returning. Mirrors BT's existing recovery path. (`OnlineGameViewModel.swift`)
- [2026-04-16] Landscape mode selection — `ModeSelectionView` now renders a two-column layout in landscape: left column shows the spade icon + app title + subtitle; right column shows the four `ModeCard` rows in a `ScrollView`. Portrait layout is pixel-identical to before (zero changes). Added reusable `LandscapeModeSelectionLayout<Cards: View>` generic struct to `Styles.swift` for future screens. Top bar buttons (`showingLeaderboard`, `showingSettings`) changed from individual `.padding(.top, 56)` to shared `.padding(.top, 56)` on the enclosing `HStack` so both buttons move together in any orientation. (`Styles.swift`, `ModeSelectionView.swift`)
- [2026-04-16] Leaderboard fix LB4 — Online/BT always sent `roundCount = 1` (only the last round) because `saveOnlineGameHistory`/`saveBTGameHistory` built a single `HistoryRound` at game-over and passed `rounds: [lastRound]`. Added `var completedRounds: [HistoryRound] = []` to `OnlineGameViewModel` and `BluetoothGameViewModel`. In both `parseGameState` (Online) and `applyGameState` (BT), a `HistoryRound` is now appended each time `phase` transitions to `.roundComplete` or `.gameOver`, guarded by `completedRounds.last?.roundNumber != roundNumber` to prevent double-appends. Both save functions now pass `rounds: game.completedRounds` (with a single-round fallback if the array is empty). `completedRounds` is never reset between rounds — it accumulates for the lifetime of the game session. (`OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`, `OnlineGameView.swift`, `BluetoothGameView.swift`)

## v1.6 Changelog
> Changes made after v1.5 App Store submission (April 5, 2026). Add entries here as changes are implemented.

<!-- TEMPLATE: - [YYYY-MM-DD] Short description of change (`FileChanged.swift`) -->

- [2026-04-16] Leaderboard fix LB3 — Cloud Function `isValidName` had a `/^Player\s*\d+$/i` regex that silently dropped `player_stats` writes for any player using a default "Player N" name; this was the primary reason leaderboard never updated for games with unnamed players. Removed the regex from `isValidName` in `functions/index.js` and deployed. Changed iOS fallback name from `"Player N"` to `"Guest N"` across all 4 ViewModel files (`OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`, `ComputerGameViewModel.swift`, `GameViewModel.swift`) — also updated the default `playerNames` initial value in `GameViewModel`. This improves leaderboard readability and avoids any future name-pattern conflicts.
- [2026-04-16] Leaderboard fix LB2 — `saveOnlineGameHistory`/`saveBTGameHistory` silently bailed when `partner1Index`/`partner2Index` were -1 at game-over with no retry mechanism. Added `.onChange(of: game.partner1Index)` and `.onChange(of: game.partner2Index)` in `OnlineGameView` and `BluetoothGameView` that re-attempt the save when the game is in `.gameOver` and an index becomes valid. `gameHistorySaved` was already set after the guard so it stays `false` on a bail, making the retry correct. Added `btLog.warning`/`ogLog.warning` to the guard bail for diagnostics (`OnlineGameView.swift`, `BluetoothGameView.swift`)
- [2026-04-16] Leaderboard fix LB1 — `sendRecord` used to return `true` on HTTP 4xx, silently treating server rejections as success (`scoreSaveStatus = .saved`, `errorMessage = nil`). Introduced `SendResult` enum (`.success`, `.serverRejected(String)`, `.networkFailure`). 4xx now returns `.serverRejected` → `scoreSaveStatus = .failed(message)` + `errorMessage` shown to user, record discarded. `flushPendingRecords` discards enqueued records that get a server rejection instead of retrying forever. Network failures and 5xx still enqueue for offline retry as before (`LeaderboardService.swift`)
- [2026-04-16] How to Play updated — added Pass & Play mode, TV Dashboard (Bluetooth) description, in-app QR scanner joining instructions, win condition (first to 500), and fixed score chart description to not reference removed 500-target UI (`SettingsView.swift`)
- [2026-04-16] QR code scan fix — 5 issues resolved in `QRScannerView.swift` + `OnlineSessionView.swift`: (1) **Primary**: `onScan` was calling `.prefix(6)` on the full universal link URL, extracting `"HTTPS:"` instead of the room code; fixed by parsing the path component after `"join"` via `extractRoomCode(from:)` helper mirroring `handleIncomingURL`; (2) first-launch camera permission race fixed with `isConfigured` flag + `beginConfiguration`/`commitConfiguration`; (3) `stopRunning()` moved to background thread in `metadataOutput` and `viewWillDisappear`; (4) `updateUIViewController` now propagates updated `onScan` closure to VC; (5) `onScan` changed to `(String) -> Bool` — returning `false` auto-restarts the scanner; error banner shown in scanner sheet for invalid scans (`QRScannerView.swift`, `OnlineSessionView.swift`)
- [2026-04-16] BT AI stall fix — added `guard playerIndex == currentActionPlayer` to `processBid`, `processPass`, `processCallCards`, and `processPlayCard` in `BluetoothGameViewModel`; stale/delayed human action messages could advance the turn past an AI's slot. Added recovery call in `processAITurnIfNeeded` bail path: when the guard-after-sleep fires, if it's still an AI's turn in an active phase, re-trigger to mirror Online mode's Firestore-snapshot failsafe (`BluetoothGameViewModel.swift`)
- [2026-04-05] Universal links — full implementation via Firebase Hosting: AASA at root domain with correct Team ID/bundle ID; `DeepLinkManager` singleton stores pending join code across cold-start navigation; `ModeSelectionView` watches `DeepLinkManager` and auto-navigates to join screen; `CreateOrJoinView` passes code directly to `JoinByCodeView` via `initialCode` param (not notification, which fires before view is mounted); `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` handles https universal links; QR encodes full universal link URL; share messages use `https://` link (`MyAppApp.swift`, `MyApp.entitlements`, `ModeSelectionView.swift`, `OnlineSessionView.swift`)
- [2026-04-05] Bluetooth leaderboard fix — Cloud Function `validModes` array was missing `"Bluetooth"` and `"PassAndPlay"`; BT games received HTTP 400 which `sendRecord()` treated as terminal, silently dropping records; fixed by adding both modes to `validModes` in `functions/index.js` and deploying
- [2026-04-08] Leaderboard save fix (BT + Online) — `saveBTGameHistory()` / `saveOnlineGameHistory()` were being called (1) from the "Next Round" handler on every intermediate round, creating bogus Cloud Function records, and (2) on all 6 client devices independently, inflating every stat 6x. Fix: added `guard game.isHost else { return }` so only the host submits; removed save calls from "Next Round" handler and `onQuit` in `BTRoundCompleteView` / `OnlineRoundCompleteView` (non-game-over quits no longer create partial records); the `.task(id: game.phase)` + `.onAppear` on `GameOverView` remain as the sole save triggers (`BluetoothGameView.swift`, `OnlineGameView.swift`)
- [2026-04-06] Remove score-500 UI references — removed "Target: 500" row from TV scoreboard (`TVGameView.swift`); removed `targetScore: Int = 500` from `PlayerScoreBarChart` — bars now scale against highest current score; removed `targetScore` from `GameOverView` progress bar (same relative-to-leader scaling); removed `const WIN=500` from web dashboard (`LocalGameServer.swift`) replaced with dynamic max-score scaling (`PlayerScoreBarChart.swift`, `ComputerGameView.swift`, `OnlineGameView.swift`, `BluetoothGameView.swift`, `TVGameView.swift`, `LocalGameServer.swift`)
- [2026-04-07] Portrait overflow fix (all game modes) — avatar strip and current-trick card row were overflowing right edge in portrait. Fix: (1) avatar strip converted from bare `HStack` to `GeometryReader { chipW = (width-32)/6 }` with `frame(maxWidth: chipW).clipped()` per chip in `ComputerGameView.swift` and `OnlineGameView.swift`; (2) current-trick card row converted from hardcoded-width HStack to inner `GeometryReader` using `adaptiveCardWidth(available: inner.size.width - 28)` so cards always fit regardless of device or padding — `currentHandBox(geo:)` → `currentHandBox()` and `onlineCurrentHandBox(geo:)` → `onlineCurrentHandBox()` (both files). `LastHandView` and your-hand boxes were already using GeometryReader correctly.
- [2026-04-06] BT client stuck fix — clients were permanently stuck on "waiting for host to start" because `BTClientLobbyView` used `onChange(of: vm.phase)` but `vm.phase` defaulted to `.dealing` (same as first broadcast) and wasn't read in body so `@Observable` didn't track it. Fix: `applyGameState` now sets `sessionState = .playing` on non-host clients when any active phase (`.lookingAtCards` or later) arrives; `BTClientLobbyView.onChange` now watches `vm.sessionState` (which IS tracked since it's read in body) instead of `vm.phase` (`BluetoothGameViewModel.swift`, `BluetoothSessionView.swift`)
- [2026-04-06] TV web dashboard redesign — full-screen TV-optimized layout with fixed left scoreboard (all 6 players with role badges + score bars), fixed right info panel (trick points with offense/defense bars, bid target countdown, called cards), and center content area; playing phase shows 6-seat card table (top row: seats 5-4-3, center felt strip, bottom row: seats 0-1-2) with large card visuals, gold glow on winning card, blue pulse animation on next-to-play seat; bidding phase shows 6-seat bid grid with large amounts; all sizes in vh/vw for TV scaling; polling reduced from 2000ms to 500ms (`LocalGameServer.swift`)
- [2026-04-05] TV web dashboard (Approach B) — `LocalGameServer.swift` (new) runs a minimal HTTP server on the host iPhone using `Network.framework`; serves a live-polling HTML dashboard at `http://<local-ip>:<port>/` and JSON game state at `/state`; `BluetoothGameViewModel` starts the server in `startHosting()`, pushes updated state JSON after every `broadcastGameState()` call, and stops it in `cleanup()`; `BTHostLobbyView` shows the URL and a QR code (Core Image `CIQRCodeGenerator`) so the TV operator can open the dashboard in any browser on the same Wi-Fi; works with AirPlay mirroring since no special iOS display API is required
- [2026-04-05] TV external display (Approach A) — BT games now show a shared game board on AirPlay/HDMI external screen: `TVDisplayManager.swift` (new) manages secondary `UIWindow` lifecycle using `UIScreen.didConnectNotification`; `TVGameView.swift` (new) renders phase-aware game board (no private hand cards); `MyAppApp.swift` calls `TVDisplayManager.shared.startMonitoring()` at launch; `BTEntryView` in `ModeSelectionView.swift` sets/clears `TVDisplayManager.shared.activeGame`; `BTHostLobbyView` in `BluetoothSessionView.swift` shows "TV Connected" indicator when external screen detected

## App Identity
- **Name:** The Shady Spade
- **Bundle ID:** `com.vijaygoyal.theshadyspade`
- **Platform:** iOS (SwiftUI, supports portrait + landscape)
- **Current version:** 1.6 (build 7) — submitted to App Store April 16, 2026, under review
- **Previous version:** 1.5 (build 6) — approved on App Store
- **Swift:** SwiftUI + SwiftData + Firebase + MultipeerConnectivity
- **Project path:** `/Users/vijaygoyal/MyiOSApp/MyApp`

## Game Overview
6-player Indian card game (like Seep/Court Piece variant). 52-card deck dealt 8 cards per player (6×8=48, 4 left over). One player wins the bid, declares trump suit and calls 2 secret cards — the players holding those cards become silent partners. Defense (3 players) tries to prevent bid being made. Scoring: 250 total points in a deck (Ace/K/Q/J/10 = 10pts each, 5 = 5pts, 3♠ = 30pts). Bid made = offense earns points, bid set = defense earns points. First team to 500 wins.

## Key Numbers
- 6 players always (indices 0–5)
- 8 cards per hand
- Bid range: 130–250 (must be higher than previous bid, or pass)
- Winning score: 500 (internal only — not shown in UI)

## Firebase
- **Project:** `shadyspade-d6b84`
- **Cloud Function URL:** `https://us-central1-shadyspade-d6b84.cloudfunctions.net/recordGame`
  - Called via HTTP POST with `Authorization: Bearer <Firebase ID token>`
  - Body: `{ "data": { ...payload } }`
  - Records game to Firestore `player_stats` and `game_log` collections
  - Retry logic: 3 attempts, 2s/4s backoff, no retry on 4xx
- **Anonymous auth:** Always signed in anonymously at app launch (`signInAnonymouslyIfNeeded`)
- **Firestore collections:** `player_stats`, `game_log`, `sessions/` (online multiplayer rooms)

## Simulators
- **iPhone 17 Pro:** `DA97985A-F7CC-44F6-8281-9DD24C22B978` ← primary test device
- **iPhone Air:** `AA2EBD32-FA9F-4A3B-80CA-EDAA311FEEAC`
- Build path: `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Build/Products/Debug-iphonesimulator/MyApp.app`
- Build command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build`
- Install + launch: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl install <UUID> <APP_PATH> && xcrun simctl launch <UUID> com.vijaygoyal.theshadyspade`
- **Always build and run on simulator after implementing a feature.**

## File Map

### Entry Point
- `MyAppApp.swift` — App entry, Firebase init, anonymous auth, SwiftData model container (`Round`, `GameHistory`, `HistoryRound`), `LeaderboardService.shared.startListening()`, URL handler for `shadyspade://join/ROOMCODE`

### Navigation
- `ModeSelectionView.swift` — Root after setup; user picks Solo, Multiplayer, Local / Bluetooth, or **Join a Game** (direct shortcut to code-entry). Contains `BTEntryView` (private, handles BT lobby → game transition) and `OnlineEntryView` (private, handles online lobby → game transition). `OnlineEntryView` accepts `autoShowJoin: Bool` — when true, the join-by-code sheet opens immediately, bypassing the host/join picker screen.
- `SplashView.swift` — First-launch onboarding
- `MainView.swift` — Legacy tab view (Leaderboard / History / Settings) — still present but not primary

### Solo / Computer Game
- `ComputerGameView.swift` — Full solo game UI. Contains:
  - `ViewingCardsView` — looking at hand phase
  - `BiddingPhaseView` — uses `BiddingTwoColumnLayout`
  - `AICallingView` — waiting for AI to call
  - `PlayingPhaseView` — portrait + landscape layouts, trick history sheet (`TrickHistoryView`)
  - `RoundResultBanner` — bid made/set result
  - `TrickHistoryView` + `TrickHistoryRow` — view all completed tricks
- `ComputerGameViewModel.swift` — Solo game logic + Card/ComputerGamePhase definitions

### Online / Multiplayer (Firebase)
- `OnlineGameView.swift` — Full online game UI. Contains:
  - `OnlineBiddingView` — uses `BiddingTwoColumnLayout`
  - `OnlineCallingView` — trump + called card selection
  - `OnlinePlayingView` — portrait + landscape layouts, trick history sheet (`OnlineTrickHistoryView`)
  - `OnlineRoundCompleteView` — round result, Next Round / Quit
  - `OnlineTrickHistoryView` + `OnlineTrickHistoryRow` — view completed tricks (online version)
- `OnlineGameViewModel.swift` — Online game state, Firestore listener, host-driven game flow
- `OnlineSessionView.swift` — Lobby: create/join room, manage players
- `OnlineSessionViewModel.swift` — Lobby state, Firestore session doc management

### Bluetooth / Local Multiplayer (MultipeerConnectivity)
- `BluetoothGameView.swift` — Full BT game UI. Contains:
  - `BTLookingAtCardsView` — viewing hand phase
  - `BTBiddingView` — uses `BiddingTwoColumnLayout`
  - `BTCallingView` — trump + called card selection
  - `BTPlayingView` — portrait + landscape layouts, trick history sheet (`BTTrickHistoryView`)
  - `BTRoundCompleteView` — round result, Next Round / Quit
  - `BTGameOverView` — game over screen with final scores
  - `BTRoundResultBanner`, `BTPartnerRevealBanner`, `BTTrickHistoryView`, `BTTrickHistoryRow`
  - `saveBTGameHistory()` — saves to SwiftData + LeaderboardService with `gameMode: "Bluetooth"`
- `BluetoothGameViewModel.swift` — `@Observable @MainActor final class BluetoothGameViewModel: NSObject`. Implements `MCSessionDelegate`, `MCNearbyServiceAdvertiserDelegate`, `MCNearbyServiceBrowserDelegate`. Host drives all game logic (same flow as `OnlineGameViewModel`), broadcasts `gameState` JSON via `MCSession.send(.reliable)`. Clients send `action` messages to host.
  - `BTSessionState` enum: `.idle`, `.hosting`, `.browsing`, `.connected`, `.playing`
  - `BTPlayerSlot` struct — mirrors `SessionPlayer` without Firebase
  - Key methods: `startHosting()`, `startBrowsing()`, `connectTo(peerID:)`, `startGame()`, `placeBid()`, `pass()`, `callTrumpAndCards()`, `playCard()`, `cleanup()`
- `BluetoothSessionView.swift` — Lobby UI. Contains:
  - `BluetoothSessionView` — entry, mode picker
  - `BTModePickerView` — Host a Game / Join a Game buttons
  - `BTHostLobbyView` — shows connected players, Start Game button
  - `BTClientLobbyView` — shows found sessions list or "waiting for host" state
  - `BTFoundSessionRow`, `BTPlayerSlotCard`

### Leaderboard
- `LeaderboardService.swift` — `@Observable` singleton; Firestore listeners for `player_stats` + `game_log`; `recordGame()` calls Cloud Function
- `LeaderboardView.swift` — Leaderboard UI

### Shared Models
- `GameModel.swift` — `TrumpSuit`, `PlayerRole`, `Player`, `Round` (SwiftData), `HistoryRound` (SwiftData), `GameHistory` (SwiftData)
- `ScoringEngine.swift` — Bid scoring logic

### UI / Styles
- `Styles.swift` — All shared UI components:
  - Brand colors: `.masterGold`, `.offenseBlue`, `.defenseRose`, `.adaptivePrimary`, `.adaptiveSecondary`, `Comic.*`
  - `resolveAvatarRole(playerIndex:bidderIndex:revealedPartner1:revealedPartner2:isRoundComplete:) → AvatarRole` — determines a player's role for display
  - `AvatarRoleCard` — player avatar card with role badge
  - `BidderCard` — compact bid status card during bidding
  - `HandCardView` — card in hand (grayed if invalid)
  - `PlayingCardView` — card display
  - `LastHandView` — strip showing last completed trick
  - `LiveDot` — pulsing green dot
  - `TurnArrow` — triangle above active player
  - `GameInfoPillsRow` — trump / called cards / score progress bar (landscape)
  - `LandscapePlayerRow` — compact player row for landscape sidebar
  - `ShimmerModifier` + `View.shimmer(isActive:)` — gold shimmer on playable cards
  - `BiddingTwoColumnLayout` — shared bidding UI (portrait + landscape, used by both game modes)
  - `currentHandStage()` modifier — container styling for current trick box

### TV Display

#### Approach A — External display (HDMI/AirPlay extended display only)
- `TVDisplayManager.swift` — `@Observable @MainActor` singleton managing the secondary `UIWindow` on AirPlay/HDMI screens. Monitors `UIScreen.didConnectNotification` / `didDisconnectNotification`. Set `TVDisplayManager.shared.activeGame` to a `BluetoothGameViewModel` to show the TV view; nil it to tear down. Prefers `UIWindowScene`-based window (iOS 16+), falls back to `UIWindow.screen`.
- `TVGameView.swift` — Phase-aware SwiftUI view rendered on the external screen during BT games. Shows: waiting screen during deal/look phase; bidder row during bidding; trump/called-cards info during calling; 3-column playing layout (scores | 6-seat table | bid info) during playing; standings on round-complete/game-over. Never shows any player's private hand cards.

#### Approach B — Local web dashboard (works with AirPlay mirroring)
- `LocalGameServer.swift` — `final class LocalGameServer: @unchecked Sendable`. Minimal HTTP server via `NWListener`. Serves HTML at `/` and JSON at `/state` (polled every 2 s). Thread-safe via `NSLock`. `onReady((String)->Void)` fires from background thread when URL is ready. `makeQRCode(from:size:)` uses Core Image `CIQRCodeGenerator`.
- `BluetoothGameViewModel.localServerURL: String` — observable URL shown in lobby. Server starts in `startHosting()`, state pushed in `broadcastGameState()` (augmented with `currentTrickWinnerIndex`/`offensePoints`/`defensePoints`), stopped in `cleanup()`.
- `BTHostLobbyView` shows QR code + URL when `vm.localServerURL` is non-empty. QR generated via `LocalGameServer.makeQRCode`.

### Other
- `AuthView.swift` / `AuthViewModel.swift` — Sign-in (email/Google), links anonymous account
- `SettingsView.swift` — App settings
- `ThemeManager.swift` / `ThemeEngine.swift` — Theme system
- `AdaptiveColours.swift` — Light/dark color helpers
- `HapticManager` — Haptic feedback (used throughout)
- `ProfanityFilter.swift` — Player name filtering
- `TurnNudge.swift` — Screen pulse when it's your turn
- `QRScannerView.swift` — QR scan to join online room
- `CardDealAnimationView.swift` — Deal animation

## Key Patterns

### State Management
- `@Observable` + `@MainActor` on all ViewModels
- `@Bindable` in views that need two-way binding to `@Observable` classes
- `@State private var game = SomeViewModel()` at view level

### Orientation / Layout
- `GeometryReader { geo in let isLandscape = geo.size.width > geo.size.height }` — used in `PlayingPhaseView`, `OnlinePlayingView`, and `BiddingTwoColumnLayout`
- Landscape playing: 3-column HStack — left 22% player list | center flexible trick area | right 26% hand
- Portrait playing: ScrollView with VStack

### Game Phases
**Solo (`ComputerGamePhase`):**
`.viewingCards` → `.bidding` / `.humanBidding` → `.aiCalling` / `.callingCards` → `.playing` / `.humanPlaying` → `.roundComplete`

**Online (`OnlineGamePhase` — synced via Firestore):**
`.dealing` → `.lookingAtCards` → `.bidding` → `.calling` → `.playing` → `.roundComplete` → `.gameOver`

### Leaderboard Offline Retry
- `PendingGameRecord: Codable` — serializable record struct; stored as JSON in `UserDefaults` key `leaderboard_pending_records_v1`.
- `ScoreSaveStatus` enum: `.idle | .saving | .saved | .pending | .failed(String)` — observable on `LeaderboardService.shared.scoreSaveStatus`.
- `NWPathMonitor` in `LeaderboardService.startListening()` — when connectivity is restored, calls `flushPendingRecords()` which retries all queued records. Also flushes at app launch.
- `recordGame` enqueues to `pendingRecords` instead of giving up when all 3 HTTP attempts fail due to network error. 4xx errors are terminal (not enqueued).
- `ScoreSaveStatusRow` in `Styles.swift` — shared view used by `GameOverView` (solo), `OnlineRoundCompleteView`, `BTRoundCompleteView`, `BTGameOverView` to display `.saving / .saved / .pending / .failed` states.
- `.pending` renders a gold wifi-slash banner: "No internet — score will sync automatically when you're back online."

### Leaderboard Recording
- Called from both `ComputerGameView` and `OnlineGameView` when a game ends
- `LeaderboardService.shared.recordGame(gameMode:playerNames:finalScores:winnerIndex:aiSeats:rounds:)`
- `gameHistorySaved: Bool` @State flag prevents double-saves; reset to `false` after "Next Round"
- Solo game mode string: `"Solo"`, Online: `"Online"`, Pass-and-Play: `"PassAndPlay"`, Bluetooth: `"Bluetooth"`
- `HistoryRound` is the SwiftData model passed as `rounds:` array

### Online Game Architecture
- Host device drives all game logic; writes to Firestore `sessions/{code}/gameState`
- All clients (including host) read from Firestore via real-time listener
- `isHost: Bool` on `OnlineGameViewModel` gates all mutation calls
- `currentActionPlayer` = whose turn it is (equivalent of `currentLeaderIndex` in solo)
- `revealedPartner1Index: Int` uses `-1` as sentinel (not revealed); solo uses `Int?`

### BidWinnerBanner Tap-Block Fix
- In `OnlineGameViewModel.parseGameState` and `BluetoothGameViewModel.applyGameState`, `bidWinnerInfo` is forcibly cleared when `newPhase` is `.playing`, `.roundComplete`, or `.gameOver`.
- Reason: the banner has a full-screen `Color.black.opacity(0.55).onTapGesture {}` that absorbs all taps. If the bid winner calls trump quickly (< 2.5s), the game enters playing phase while the non-bid-winner's auto-dismiss timer is still pending, freezing card play for those players.

### Concurrent Snapshot State Capture (Online + BT)
- In `OnlineGameViewModel.processPendingAction` and `BluetoothGameViewModel.processPlayCard` (playCard, 6th card path), `wonPointsPerPlayer`, `trickNumber`, and `runningScores` are captured into local `let` constants **before** `Task.sleep`.
- Reason: the show-state write triggers a re-entrant state parse on the host during the sleep (Firestore snapshot or MC message), which can overwrite those instance properties. The resolve-state logic reads from captured locals, not `self`.

### BT/Online Divergence Fixes (applied)
1. **BT trick resolution race** — `wonPointsPerPlayer`, `trickNumber`, `runningScores` captured before sleep in `BluetoothGameViewModel.processPlayCard`.
2. **BT AI phase guard** — `seat` and `capturedPhase` now captured BEFORE sleep in `processAITurnIfNeeded`. Guard after sleep verifies `aiSeats.contains(seat)`, `phase == capturedPhase`, and `currentActionPlayer == seat`.
3. **`currentTrickWinnerIndex` type** — `BluetoothGameViewModel` now returns `Int?` (nil when no trick), matching `OnlineGameViewModel`. `BluetoothGameView` comparison `entry.playerIndex == game.currentTrickWinnerIndex` still compiles via Swift Optional Equatable.
4. **BT mid-game disconnect → AI replacement** — In `case .notConnected:`, when host + game in active phase, disconnected human slot is added to `aiSeats`, state is broadcast, and `processAITurnIfNeeded()` is triggered if it was their turn.
5. **Online `startNextRound()` host guard** — Added `guard isHost else { return }` to prevent non-host clients from advancing the round.
6. **AI delay standardized** — Both BT and Online now use `800_000_000...1_200_000_000` ns (was `1_000_000_000...1_500_000_000` in Online).

### Security Fixes (applied)
1. **BT gameState host forgery** — `case "gameState"` in `handleMessage` now verifies `playerIndexToPeer[0] == peer` before applying state; only the host peer is trusted.
2. **BT assignSlot bounds check** — `slotIndex` extracted from `dict["playerIndex"]` in `case "assignSlot"` is now guarded `>= 0 && < 6`.
3. **BT bid amount validation** — In `case "action"/"bid"`, `amount` is checked `>= 130 && <= 250` before calling `processBid`.
4. **BT currentTrick pi bounds** — `applyGameState` currentTrick parsing checks `pi >= 0 && pi < 6` before constructing tuple.
5. **BT called cards validation** — `processCallCards` validates both card IDs exist in a fresh deck, are distinct, and are not already in the bidder's hand.
6. **Online playerIndex spoof** — `processPendingAction` adds `guard playerIndex >= 0 && playerIndex < 6` and `guard playerIndex == currentActionPlayer` after extracting playerIndex.
7. **Online currentTrick pi bounds** — `parseGameState` currentTrick parsing checks `pi >= 0 && pi < 6`.
8. **joinSession bounds check** — `OnlineSessionViewModel.joinSession` checks `firstAI >= 0 && firstAI < slotsData.count` before using AI seat as array index.
9. **Deep link sanitization** — `handleIncomingURL` in `MyAppApp.swift` validates room code is exactly 6 alphanumeric chars.
10. **Rate limiting** — `placeBid`, `pass`, `callTrumpAndCards`/`confirmCalling`, `playCard` in both `BluetoothGameViewModel` and `OnlineGameViewModel` enforce a 300ms minimum interval via `lastActionSentAt: Date`.
11. **Online bid amount validation** — `processPendingAction` case `"bid"` now guards `amount >= 130 && amount <= 250` before using the value.
12. **Online called cards validation** — `processPendingAction` case `"callCards"` validates both card IDs against a full deck set, are distinct, and not in the bidder's hand (mirrors BT fix).
13. **BT host-only message types** — `case "hand"`, `case "assignSlot"`, `case "playerList"`, `case "lobbyUpdate"` in `handleMessage` now all verify `playerIndexToPeer[0] == peer`; a rogue non-host peer can no longer inject fake hands, slot assignments, or lobby state.
14. **BT bidHistory pi bounds** — `applyGameState` bidHistory parsing checks `pi >= 0 && pi < 6` before constructing tuples.

### Bluetooth Game Architecture
- Uses `MultipeerConnectivity` framework; service type `"shady-spade"` (matches `NSBonjourServices` in Info.plist)
- Host = player index 0, drives all game logic identically to Online mode
- All messages sent via `MCSession.send(.reliable)` as JSON data
- Message types: `gameState` (host→all), `assignSlot` (host→peer), `hand` (host→specific peer), `action` (client→host), `playerList` / `lobbyUpdate` (host→all in lobby)
- `BluetoothGameViewModel` uses `nonisolated` MC delegate methods that bridge to `@MainActor` via `Task { @MainActor in }`
- `peerToPlayerIndex: [MCPeerID: Int]` and `playerIndexToPeer: [Int: MCPeerID]` map peers to game slots
- AI bots fill empty slots on host side; host computes AI turns after each state update
- Leaderboard game mode string: `"Bluetooth"`

### Card Point System
- 3♠ = 30 pts, A/K/Q/J/10 = 10 pts each, 5 = 5 pts, all others = 0
- Total points in deck = 250

### resolveAvatarRole
```swift
// In Styles.swift — determines display role for a player
func resolveAvatarRole(
    playerIndex: Int,
    bidderIndex: Int,
    revealedPartner1: Int?,   // nil = unrevealed
    revealedPartner2: Int?,   // nil = unrevealed
    isRoundComplete: Bool = false
) -> AvatarRole  // .bidder | .partner | .defense | .unknown
```
- Solo passes `Int?` directly (already optional in ComputerGameViewModel)
- Online converts: `game.revealedPartner1Index >= 0 ? game.revealedPartner1Index : nil`

### Shimmer (playable cards)
```swift
HandCardView(card: card, width: cardW, isValid: !isMyTurn || valid)
    .shimmer(isActive: isMyTurn && valid)
```
- `ShimmerModifier` in Styles.swift — gold sweep animation + border on valid cards
- Always renders gradient (opacity-controlled) to prevent animation restart flicker

### BiddingTwoColumnLayout
Shared component in Styles.swift. Portrait: vertical scroll with bidder cards + history + controls + hand. Landscape: left column (bidder cards + history) | right column (controls + hand).

## SwiftData Models
- `Round` — single round result (no running scores)
- `HistoryRound` — round result with `runningScores: [Int]` (6-element array)
- `GameHistory` — wrapper for a full game session
- Container registered in `MyAppApp.swift`

## Privacy Policy
- Hosted at: https://imvijaygoyal1.github.io/shadyspade-privacy/
- Source: `git@github.com:imvijaygoyal1/shadyspade-privacy.git` (local clone at `/tmp/shadyspade-privacy`)

## Deep Link / QR
- Custom URL scheme: `shadyspade://join/{ROOMCODE}` (fallback, used if app not installed)
- Universal link: `https://shadyspade-d6b84.web.app/shadyspade/join/{ROOMCODE}` — served via Firebase Hosting
- AASA: `https://shadyspade-d6b84.web.app/.well-known/apple-app-site-association` (correct Team ID + bundle ID, `application/json`)
- Join redirect page: `/shadyspade/join/index.html` — auto-triggers app open, falls back to App Store after 2s
- Firebase Hosting config: `/tmp/shadyspade-hosting/` (deploy with `firebase deploy --only hosting`)
- Associated domains entitlement: `applinks:shadyspade-d6b84.web.app`, `applinks:shadyspade-d6b84.firebaseapp.com`
- QR codes encode the full universal link URL (not just the room code)
- Share messages include the `https://` universal link
