# The Shady Spade — v1.5 Release Notes
**Build 6 · April 2026**

---

## App Store Description (What's New)

**Join faster, play smarter.**

**Jump straight into a game** — a new "Join a Game" shortcut is now right on the home screen. If someone hands you a room code, tap it and you're in. No extra taps through menus.

**Smarter calling cards** — when you win the bid and declare trump, the app now hides the cards already in your hand from the calling card picker. You can no longer accidentally call a card you're already holding.

**Cleaner room code sharing** — the QR code share sheet has been redesigned to show the full code and QR image on all screen sizes, with clearly visible share buttons.

**Bug fixes and stability improvements** across Bluetooth and Online multiplayer modes.

---

## Internal Change Log

### New Features
- **"Join a Game" mode card** on `ModeSelectionView` — taps straight to the code-entry sheet, bypassing the Multiplayer host/join picker screen. Uses `autoShowJoin: Bool` threaded through `OnlineEntryView` → `OnlineSessionView` → `CreateOrJoinView`.

### Game Logic Fixes
- **Calling cards filter (all 3 modes)** — `callCardRow` / `btCallCardRow` now accept `handIds: Set<String>` (bid winner's hand card IDs). Rank menu filters out ranks where `rank + currentSuit` is in hand. Suit buttons are dimmed (25% opacity) and disabled when `currentRank + suit` is in hand. Applied to `ComputerGameView`, `OnlineGameView`, `BluetoothGameView`.
- **BT trick resolution race condition** — `wonPointsPerPlayer`, `trickNumber`, and `runningScores` captured into local constants before `Task.sleep` in `BluetoothGameViewModel.processPlayCard`, preventing re-entrant state corruption.
- **BT AI phase guard** — `currentActionPlayer` seat and `phase` captured before sleep in `processAITurnIfNeeded`; guard after sleep verifies all three: `aiSeats.contains(seat)`, `phase == capturedPhase`, `currentActionPlayer == seat`.
- **BT mid-game disconnect → AI replacement** — When a peer disconnects during an active game, their slot is automatically replaced by an AI bot; game state is broadcast and AI turn processing resumes if it was their turn.
- **Online `startNextRound()` host guard** — Added `guard isHost else { return }` to prevent non-host clients from triggering round advancement.
- **AI delay standardized** — Both BT and Online use `800_000_000...1_200_000_000` ns (0.8–1.2s) for AI thinking time.
- **`currentTrickWinnerIndex` type** — BT now returns `Int?` (nil when no trick in progress), matching Online. Removes -1 sentinel.

### Security Hardening (14 fixes)
- **BT host forgery** — `gameState`, `hand`, `assignSlot`, `playerList`, `lobbyUpdate` messages now verify sender is the host peer (`playerIndexToPeer[0] == peer`).
- **Bounds checking** — `playerIndex`, `slotIndex`, and parsed `pi` values in `currentTrick`/`bidHistory` are validated `>= 0 && < 6` before any array access.
- **Bid amount validation** — Both BT and Online reject bids outside 130–250 range.
- **Called cards validation** — Both BT and Online validate called card IDs exist in a fresh deck, are distinct, and are not in the bidder's hand.
- **Online playerIndex spoof** — `processPendingAction` guards `playerIndex == currentActionPlayer`.
- **Deep link sanitization** — `handleIncomingURL` validates room code is exactly 6 alphanumeric characters.
- **Rate limiting** — All action methods (`placeBid`, `pass`, `callTrumpAndCards`, `playCard`) enforce a 300ms minimum interval.

### UI Fixes
- **QR share sheet** — Switched to `.presentationDetents([.large])`, removed `GeometryReader` (was causing infinite height context inside `ScrollView`). Fixed 220×220pt QR image, plain `VStack` split (scrollable content | divider | fixed button footer).
- **"Share" button label** — "Share Code" shortened to "Share" in the lobby room code bar, matching "Copy" and "QR" for consistent single-line appearance.

### Version
- `MARKETING_VERSION`: 1.4 → 1.5
- `CURRENT_PROJECT_VERSION`: 5 → 6

### Privacy Policy
- Added Bluetooth Mode entry to Section 8 (Game Modes & Data)
- Updated "Last Updated" date to April 5, 2026
- Published to: https://imvijaygoyal1.github.io/shadyspade-privacy/
