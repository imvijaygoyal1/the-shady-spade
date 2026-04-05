# The Shady Spade — Claude Code Context

> **IMPORTANT FOR CLAUDE:** After every code change to this project, update this file to reflect the change. New file → add to File Map. New component → add to Styles section. Changed pattern → update Key Patterns. Version bump → update App Identity. This file must always stay current.

## App Identity
- **Name:** The Shady Spade
- **Bundle ID:** `com.vijaygoyal.theshadyspade`
- **Platform:** iOS (SwiftUI, supports portrait + landscape)
- **Current version:** 1.4 (build 5)
- **Swift:** SwiftUI + SwiftData + Firebase + MultipeerConnectivity
- **Project path:** `/Users/vijaygoyal/MyiOSApp/MyApp`

## Game Overview
6-player Indian card game (like Seep/Court Piece variant). 52-card deck dealt 8 cards per player (6×8=48, 4 left over). One player wins the bid, declares trump suit and calls 2 secret cards — the players holding those cards become silent partners. Defense (3 players) tries to prevent bid being made. Scoring: 250 total points in a deck (Ace/K/Q/J/10 = 10pts each, 5 = 5pts, 3♠ = 30pts). Bid made = offense earns points, bid set = defense earns points. First team to 500 wins.

## Key Numbers
- 6 players always (indices 0–5)
- 8 cards per hand
- Bid range: 130–250 (must be higher than previous bid, or pass)
- Winning score: 500

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
- `ModeSelectionView.swift` — Root after setup; user picks Solo, Multiplayer, or Local / Bluetooth. Contains `BTEntryView` (private, handles BT lobby → game transition) and `OnlineEntryView` (private, handles online lobby → game transition).
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

### Concurrent Snapshot State Capture (Online)
- In `OnlineGameViewModel.processPendingAction` (playCard, 6th card path), `wonPointsPerPlayer`, `trickNumber`, and `runningScores` are captured into local `let` constants **before** `Task.sleep(1_000_000_000)`.
- Reason: the Firestore show-state write triggers `handleSnapshot` on the host during the sleep, which calls `parseGameState` and overwrites those instance properties. The resolve-state logic now reads from captured locals, not `self`.

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
- URL scheme: `shadyspade://join/{ROOMCODE}`
- Web fallback: `https://imvijaygoyal1.github.io/shadyspade/join/{ROOMCODE}`
