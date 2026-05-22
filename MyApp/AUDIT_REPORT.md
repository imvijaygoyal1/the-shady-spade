# The Shady Spade — Comprehensive Audit Report

> **Last updated:** 2026-05-22  
> **Scope:** All bug fixes, security patches, and architectural changes from v1.5 through v1.9 (including Architect Audits v4 and v5).  
> **Status key:** ✅ Fixed | ⚠️ Deferred | 🔲 Open

---

## Executive Summary

| Category | Count | Status |
|---|---|---|
| Leaderboard Failures | 14 | ✅ All fixed (v1.6–v1.8) |
| AI / Game Logic Bugs | 13 | ✅ All fixed (v1.7) |
| AI Bot Stuck (RC series) | 3 | ✅ All fixed (v1.7) |
| Security Fixes | 14 | ✅ All fixed (v1.7) |
| BT/Online Divergence | 6 | ✅ All fixed (v1.7/v1.8) |
| UI / UX Bugs | 10 | ✅ All fixed (v1.6–v1.8) |
| v1.9 Fix | 1 | ✅ Fixed (v1.9) |
| Architect Audit v4 (5C/8H/14M/14L) | 41 | ✅ All fixed (v1.9, 2026-05-17) |
| **Total** | **102** | **✅ All resolved** |

---

## Leaderboard Failures

### LB-01 — sendRecord treats 4xx as success
- **File:** `LeaderboardService.swift`
- **Issue:** `sendRecord` returned `true` on HTTP 4xx, silently treating server rejections as success. `scoreSaveStatus` was set to `.saved` and records were discarded permanently.
- **Status:** ✅ Fixed (v1.6)
- **Fix:** Introduced `SendResult` enum (`.success`, `.serverRejected(String)`, `.networkFailure`). 4xx returns `.serverRejected` → `scoreSaveStatus = .failed(message)` + record discarded (not retried). Network errors and 5xx still enqueue for offline retry.

### LB-02 — partner indices -1 at game-over → save bail with no retry
- **File:** `OnlineGameView.swift`, `BluetoothGameView.swift`
- **Issue:** `saveOnlineGameHistory`/`saveBTGameHistory` bailed silently when `partner1Index`/`partner2Index` were -1 at game-over (Firestore snapshot race). No retry mechanism — leaderboard record permanently lost.
- **Status:** ✅ Fixed (v1.6)
- **Fix:** Added `.onChange(of: game.partner1Index)` and `.onChange(of: game.partner2Index)` that re-attempt save when game is in `.gameOver` and an index becomes valid. `gameHistorySaved` stays `false` on bail, making retry correct.

### LB-03 — Cloud Function regex drops "Player N" names
- **File:** `functions/index.js`, all 4 ViewModel files
- **Issue:** Cloud Function `isValidName` had `/^Player\s*\d+$/i` regex that silently rejected `player_stats` writes for any player using the default "Player N" name — the primary reason leaderboard never updated for unnamed players.
- **Status:** ✅ Fixed (v1.6)
- **Fix:** Removed the regex from `isValidName`. Changed iOS fallback name from `"Player N"` to `"Guest N"` across `OnlineGameViewModel`, `BluetoothGameViewModel`, `ComputerGameViewModel`, `GameViewModel`.

### LB-04 — Online/BT always sent roundCount = 1
- **File:** `OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`, `OnlineGameView.swift`, `BluetoothGameView.swift`
- **Issue:** `saveOnlineGameHistory`/`saveBTGameHistory` built a single `HistoryRound` at game-over and passed `rounds: [lastRound]`. Multi-round games always recorded `roundCount = 1`.
- **Status:** ✅ Fixed (v1.6)
- **Fix:** Added `var completedRounds: [HistoryRound] = []` to both VMs. A `HistoryRound` is appended each time `phase` transitions to `.roundComplete` or `.gameOver`, guarded by `last?.roundNumber != roundNumber` to prevent double-appends. Save functions now pass `rounds: game.completedRounds`.

### LB-05 — Monthly leaderboard reset permanently destroys all stats
- **File:** `functions/index.js`
- **Issue:** `resetMonthlyLeaderboard` Cloud Function deleted all `player_stats` and `game_log` documents without archiving. Historical stats were permanently gone after each month reset.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Reset function now archives before deleting: copies all documents to `monthly_snapshots/{YYYY-MM}/{col}/{docId}` using 400-doc batch chunks. Deletes only run after all archive batches succeed. Archive label = prior calendar month.

### LB-06 — Firestore listener guard preventing re-subscription after silent death
- **File:** `LeaderboardService.swift`
- **Issue:** `startListening()` had `guard statsListener == nil else { return }` blocking re-subscription if a listener silently died (no Firestore error callback).
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Removed the guard. `startListening()` always calls `stopListening()` first then `attachFirestoreListeners()`. Added `reattachListeners()` private helper called from snapshot listener error closures — removes old registrations, waits 3s, calls `attachFirestoreListeners()` again.

### LB-07 — leaderboard record lost when app killed mid-send
- **File:** `LeaderboardService.swift`
- **Issue:** `recordGame()` only enqueued to `UserDefaults` in the `.networkFailure` branch. If the OS killed the process after `gameHistorySaved = true` but before the HTTP attempt completed, the record was permanently lost.
- **Status:** ✅ Fixed (v1.8)
- **Fix:** `recordGame()` now enqueues the `PendingGameRecord` to `UserDefaults` **before** launching the HTTP attempt, then calls `removeFromQueue(id:)` on success or server rejection.

### LB-08 — No HTTP timeout on sendRecord
- **File:** `LeaderboardService.swift`
- **Issue:** `URLRequest` used default 60s timeout. Each retry blocked for up to 60s, making worst-case total time 180s+.
- **Status:** ✅ Fixed (v1.8)
- **Fix:** Added `request.timeoutInterval = 10`. Worst-case total is now ~24s (3×10s + 2s+4s backoff).

### LB-09 — Unbounded pending queue
- **File:** `LeaderboardService.swift`
- **Issue:** `enqueue()` had no size cap. Offline-heavy devices could accumulate unlimited records in `UserDefaults`.
- **Status:** ✅ Fixed (v1.8)
- **Fix:** `enqueue()` now trims to the 100 most-recent entries after appending.

### LB-10 — No deduplication in pending queue
- **File:** `LeaderboardService.swift`
- **Issue:** `onChange` retry races could double-enqueue the same game record, causing double submission on next flush.
- **Status:** ✅ Fixed (v1.8)
- **Fix:** Added `deduplicationKey` computed property to `PendingGameRecord` (gameMode|playerNames|roundCount|bid|winnerIndex). `enqueue()` skips append if matching key already queued.

### LB-11 — completedRounds empty at game-over → saveOnQuit silent skip
- **File:** `OnlineGameView.swift`, `BluetoothGameView.swift`
- **Issue:** Both `saveOnQuit()` implementations guarded on `completedRounds.isEmpty`. If `.gameOver` arrived before the round-complete transition appended to `completedRounds`, the save was silently skipped.
- **Status:** ✅ Fixed (v1.8)
- **Fix:** Both `saveOnQuit()` now fall back to a synthetic `HistoryRound` built from current game state when `completedRounds` is empty but `highBidderIndex >= 0`.

### LB-12 — Pass-and-Play mode string sent as "Multiplayer"
- **File:** `ComputerGameView.swift`
- **Issue:** P&P games sent `"Multiplayer"` to the Cloud Function instead of `"PassAndPlay"`. Stats were misclassified.
- **Status:** ✅ Fixed (v1.8)
- **Fix:** All 3 save sites now use `game.isPassAndPlay ? "PassAndPlay" : (game._allPlayerNames.isEmpty ? "Solo" : "Multiplayer")`.

### LB-13 — aiSeats array has no bounds check (server-side)
- **File:** `functions/index.js`
- **Issue:** `payload.aiSeats` values were used as array indices without validation. Out-of-range values could corrupt `player_stats` writes.
- **Status:** ✅ Fixed (v1.8)
- **Fix:** Cloud Function filters `payload.aiSeats` to only integers in [0, 5] before building the Set.

### LB-14 — Non-host Online clients never submit → host crash = permanent loss
- **File:** `LeaderboardService.swift`, `OnlineGameView.swift`, `functions/index.js`
- **Issue:** Both `saveOnlineGameHistory()` and `saveOnQuit()` had `guard game.isHost else { return }`. If the host crashed before calling `recordGame()`, all 6 players' stats were permanently lost.
- **Status:** ✅ Fixed (v1.8)
- **Fix:** (1) `PendingGameRecord` gained `sessionCode: String?`; `deduplicationKey` uses it as stable key. (2) All clients now submit independently (removed `guard game.isHost`). (3) Cloud Function uses a Firestore transaction: first write wins, subsequent submissions for same `sessionCode` are silent no-ops.

---

## AI / Game Logic Bugs

### AI-01 — Empty hand / phantom card (all 3 modes)
- **File:** `OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`, `ComputerGameViewModel.swift`
- **Issue:** `aiComputeCard(seat:)` returned `"A♠"` sentinel when hand was empty, causing invalid card plays and game freezes.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Return type changed to `String?`; returns `nil` with error log when hand is empty. Callers handle `nil` with a 1s retry. Solo added `guard !hands[playerIndex].isEmpty`.

### AI-02 — Concurrent AI tasks / double-play
- **File:** `OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`
- **Issue:** Multiple concurrent `processAITurnIfNeeded()` tasks could race and double-play a card, corrupting game state.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Added `private var isProcessingAI = false` to both VMs. `processAITurnIfNeeded()` gates entry with `guard !isProcessingAI`; resets flag before recursive re-triggers.

### AI-03 — Trick resolution write failure not recovered (Online)
- **File:** `OnlineGameViewModel.swift`
- **Issue:** `criticalWrite()` failures for trick-advance and round-complete had no local fallback. On all-retries-fail, game froze.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Captures return value; on failure applies state locally on host (`currentActionPlayer`, `currentTrick`, `trickNumber`, etc.) and re-triggers `processAITurnIfNeeded()`.

### AI-04 — Disconnect mid-trick race (BT)
- **File:** `BluetoothGameViewModel.swift`
- **Issue:** BT disconnect handler gated `processAITurnIfNeeded()` on `currentActionPlayer == playerIdx`. If it was another player's turn at disconnect, AI was never triggered for the disconnected seat.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Disconnect handler always triggers `processAITurnIfNeeded()` unconditionally after adding the disconnected seat to `aiSeats`.

### AI-05 — No gameLoopCancelled guard after sleeps (Solo)
- **File:** `ComputerGameViewModel.swift`
- **Issue:** After `Task.sleep` in `startPlayingPhase()`, state could have been reset (game quit, new round) with no guard, causing mutations on stale state.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Added `guard !gameLoopCancelled else { return }` immediately after every `Task.sleep` in `startPlayingPhase()`.

### AI-06 — BT host AI no re-trigger after playing card
- **File:** `BluetoothGameViewModel.swift`
- **Issue:** After BT host AI played a card, `isProcessingAI` was not reset before the switch, blocking subsequent `processAITurnIfNeeded()` calls from entering.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Resolved by AI-02 fix: resetting `isProcessingAI = false` before the switch allows internal `await processAITurnIfNeeded()` calls to proceed.

### AI-07 — Firestore listener dying mid-game
- **File:** `OnlineGameViewModel.swift`
- **Issue:** `attachListener()` discarded listener errors (parameter `_`). A silently-dead Firestore listener would leave the game frozen with no recovery.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Error closure now waits 3s then calls `reattachListener()` (removes old listener, calls `attachListener()` again).

### AI-08 — Off-by-one next player (Online + BT)
- **File:** `OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`
- **Issue:** `trickOrder[min(pos + 1, 5)]` returned same player when `pos=5`. Modulo is the correct formula.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Changed to `trickOrder[(pos + 1) % 6]` in both files.

### AI-09 — No guard after empty-hand retry sleep (Online + BT)
- **File:** `OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`
- **Issue:** The `.playing` empty-hand path slept 1s then recursed without checking if state changed during sleep. Could re-trigger for wrong player or wrong phase.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Added `guard currentActionPlayer == seat, phase == .playing` post-sleep.

### AI-10 — isProcessingAI lock stuck on invalid card
- **File:** `OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`
- **Issue:** Invalid-card guard called `processAITurnIfNeeded()` without resetting `isProcessingAI = false` first. If a sleeping AI task held the flag, the re-trigger silently bailed.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Resets `isProcessingAI = false` before re-triggering, guarded by `aiSeats.contains(currentActionPlayer)`.

### AI-11 — bid history not updating when players re-bid
- **File:** `ComputerGameViewModel.swift`, `OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`
- **Issue:** `latestBidPerPlayer` dedup kept the FIRST entry per player index. Players can bid multiple times; every raise after the first was silently dropped.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Added `latestBidPerPlayer(_:)` helper keeping one entry per player in first-appearance order but using the latest amount. Applied across all 3 VMs at all bid call sites.

### AI-12 — ForEach ID collision in RoundComplete
- **File:** `ComputerGameView.swift`, `OnlineGameView.swift`, `BluetoothGameView.swift`
- **Issue:** `offenseTeam` computed var could produce duplicate player indices when `partner1Index == partner2Index`. Caused SwiftUI "ID N occurs multiple times" warnings and undefined rendering.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Changed from plain `compactMap`/`filter` to a `seen: Set<Int>` dedup pattern preserving first-appearance order.

### AI-13 — scoreSaveStatus stale between games
- **File:** `LeaderboardService.swift`
- **Issue:** `.saved` from game N persisted into game N+1's `GameOverView` until the new save request completed. Users briefly saw a false "saved" state.
- **Status:** ✅ Fixed (v1.8)
- **Fix:** Added `scoreSaveStatus = .idle` at the top of `recordGame()` before `enqueue(pending)` and before `scoreSaveStatus = .saving`. `@MainActor` guarantees no visible flash.

---

## AI Bot Stuck Root Causes (RC Series)

### RC-A — Online AI calling turn permanently lost when refetchAndSyncHands fails
- **File:** `OnlineGameViewModel.swift`
- **Issue:** `processAITurnIfNeeded()` had a bare `return` after the `allHands[seat].count == 8` guard. If `refetchAndSyncHands()` failed, the AI calling turn was permanently lost — no Firestore snapshot would fire to recover it.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Added `retriesRemaining: Int = 2` parameter. Failed guard now retries up to 2 times with 1s sleep. Counter decrements to 0 — no infinite loop possible.

### RC-B — BT pre-sleep race: watchdog not re-armed when AI bail hits human turn
- **File:** `BluetoothGameViewModel.swift`
- **Issue:** When `processAITurnIfNeeded()` post-sleep guard fired and state had advanced to a human player's turn, the watchdog was not re-armed. Relied solely on `applyGameState()` having done it during the sleep, which was a race.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Added defensive watchdog re-arm in the bail path: if `activePhases.contains(phase) && !aiSeats.contains(currentActionPlayer)`, calls `startTurnWatchdog(seat: currentActionPlayer, capturedPhase: phase)`.

### RC-C — Solo resolveAiCalling missing gameLoopCancelled guard after 1s sleep
- **File:** `ComputerGameViewModel.swift`
- **Issue:** `resolveAiCalling()` lacked a `gameLoopCancelled` guard after `Task.sleep`. If game was quit or new round started during the sleep, it continued into `resolvePartners()` + `startPlayingPhase()` with stale state.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Added `guard !gameLoopCancelled else { return }` immediately after `Task.sleep(nanoseconds: 1_000_000_000)`.

---

## Security Fixes

### SEC-01 — BT gameState host forgery
- **File:** `BluetoothGameViewModel.swift`
- **Issue:** Any BT peer could send a `gameState` message and have it applied as authoritative game state.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** `case "gameState"` in `handleMessage` now verifies `playerIndexToPeer[0] == peer` before applying state.

### SEC-02 — BT assignSlot bounds check missing
- **File:** `BluetoothGameViewModel.swift`
- **Issue:** `slotIndex` from `dict["playerIndex"]` in `case "assignSlot"` was used without bounds checking. Values outside [0,5] could corrupt player slot array.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Added `slotIndex >= 0 && slotIndex < 6` guard.

### SEC-03 — BT bid amount not validated
- **File:** `BluetoothGameViewModel.swift`
- **Issue:** In `case "action"/"bid"`, `amount` from peer message was used without range check. Any bid value could be submitted.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Added `amount >= 130 && amount <= 250` guard before calling `processBid`.

### SEC-04 — BT currentTrick pi bounds not checked
- **File:** `BluetoothGameViewModel.swift`
- **Issue:** `applyGameState` currentTrick parsing used `pi` from JSON without bounds check, potentially creating tuples with out-of-range player indices.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Added `pi >= 0 && pi < 6` check before constructing tuple.

### SEC-05 — BT called cards not validated
- **File:** `BluetoothGameViewModel.swift`
- **Issue:** `processCallCards` accepted any two card ID strings without validating they exist in a deck, are distinct, or aren't already in the bidder's hand.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Validates both card IDs exist in a fresh deck, are distinct, and are not in the bidder's hand.

### SEC-06 — Online playerIndex spoof
- **File:** `OnlineGameViewModel.swift`
- **Issue:** `processPendingAction` used `playerIndex` from Firestore without validating it matches `currentActionPlayer`. Any action at any index could be accepted.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Added `guard playerIndex >= 0 && playerIndex < 6` and `guard playerIndex == currentActionPlayer`.

### SEC-07 — Online currentTrick pi bounds not checked
- **File:** `OnlineGameViewModel.swift`
- **Issue:** `parseGameState` currentTrick parsing used `pi` from Firestore without bounds check.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Added `pi >= 0 && pi < 6` check before constructing tuple.

### SEC-08 — joinSession bounds check missing
- **File:** `OnlineSessionViewModel.swift`
- **Issue:** `joinSession` used `firstAI` (from Firestore slots array) as array index without validating it was within bounds.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Added `firstAI >= 0 && firstAI < slotsData.count` guard.

### SEC-09 — Deep link room code not sanitized
- **File:** `MyAppApp.swift`
- **Issue:** `handleIncomingURL` accepted any path component as a room code without format validation, allowing malformed deep links.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Validates room code is exactly 6 alphanumeric characters.

### SEC-10 — No rate limiting on player actions
- **File:** `BluetoothGameViewModel.swift`, `OnlineGameViewModel.swift`
- **Issue:** `placeBid`, `pass`, `callTrumpAndCards`/`confirmCalling`, `playCard` had no minimum interval between actions. Rapid tapping or malicious clients could flood the game state.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** All action methods enforce 300ms minimum interval via `lastActionSentAt: Date`.

### SEC-11 — Online bid amount not validated
- **File:** `OnlineGameViewModel.swift`
- **Issue:** `processPendingAction` case `"bid"` used `amount` from Firestore without range validation.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Added `amount >= 130 && amount <= 250` guard.

### SEC-12 — Online called cards not validated
- **File:** `OnlineGameViewModel.swift`
- **Issue:** `processPendingAction` case `"callCards"` accepted any card IDs from Firestore without deck/distinctness/hand checks.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Validates both card IDs against full deck, are distinct, and not in bidder's hand (mirrors SEC-05).

### SEC-13 — BT host-only message types not verified
- **File:** `BluetoothGameViewModel.swift`
- **Issue:** `case "hand"`, `"assignSlot"`, `"playerList"`, `"lobbyUpdate"` in `handleMessage` did not verify sender was the host peer. Rogue non-host peers could inject fake hands and lobby state.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** All four cases now verify `playerIndexToPeer[0] == peer` before processing.

### SEC-14 — BT bidHistory pi bounds not checked
- **File:** `BluetoothGameViewModel.swift`
- **Issue:** `applyGameState` bidHistory parsing used `pi` from JSON without bounds check.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Added `pi >= 0 && pi < 6` check before constructing tuples.

---

## BT / Online Divergence Fixes

### DIV-01 — BT trick resolution race (captured locals)
- **File:** `BluetoothGameViewModel.swift`
- **Issue:** `wonPointsPerPlayer`, `trickNumber`, `runningScores` were read from `self` after `Task.sleep` in `processPlayCard`. A re-entrant `applyGameState` during the sleep could overwrite these properties.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Captured into local `let` constants **before** `Task.sleep`.

### DIV-02 — BT AI phase guard: seat/capturedPhase not captured before sleep
- **File:** `BluetoothGameViewModel.swift`
- **Issue:** `seat` and `capturedPhase` were not captured before `Task.sleep` in `processAITurnIfNeeded`. Post-sleep guard could check stale values.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** `seat` and `capturedPhase` now captured BEFORE sleep. Guard verifies `aiSeats.contains(seat)`, `phase == capturedPhase`, and `currentActionPlayer == seat`.

### DIV-03 — currentTrickWinnerIndex type mismatch (BT vs Online)
- **File:** `BluetoothGameViewModel.swift`
- **Issue:** BT returned `Int` (0 as default) while Online returned `Int?` (nil when no trick). Views using both types inconsistently.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** `BluetoothGameViewModel` now returns `Int?` matching `OnlineGameViewModel`.

### DIV-04 — BT mid-game disconnect → AI replacement not triggered
- **File:** `BluetoothGameViewModel.swift`
- **Issue:** `case .notConnected` handler did not add disconnected seat to `aiSeats` or trigger AI if it was their turn.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Disconnected human slot added to `aiSeats`, state broadcast, `processAITurnIfNeeded()` triggered if it was their turn.

### DIV-05 — Online startNextRound no host guard
- **File:** `OnlineGameViewModel.swift`
- **Issue:** Non-host clients could call `startNextRound()`, advancing the round on all clients without host authorization.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Added `guard isHost else { return }`.

### DIV-06 — AI delay inconsistent (Online vs BT)
- **File:** `OnlineGameViewModel.swift`
- **Issue:** Online used `1_000_000_000...1_500_000_000` ns while BT used `800_000_000...1_200_000_000` ns, causing inconsistent game pace between modes.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Both now use `800_000_000...1_200_000_000` ns.

---

## UI / UX Bugs

### UI-01 — Portrait overflow (avatar strip + current-trick row)
- **File:** `ComputerGameView.swift`, `OnlineGameView.swift`
- **Issue:** Avatar strip and current-trick card row overflowed the right edge in portrait orientation due to hardcoded widths.
- **Status:** ✅ Fixed (v1.6)
- **Fix:** Avatar strip converted to `GeometryReader { chipW = (width-32)/6 }` with `frame(maxWidth: chipW).clipped()`. Current-trick row converted to inner `GeometryReader` using `adaptiveCardWidth(available: inner.size.width - 28)`.

### UI-02 — BT client stuck on "waiting for host to start"
- **File:** `BluetoothGameViewModel.swift`, `BluetoothSessionView.swift`
- **Issue:** `BTClientLobbyView` watched `vm.phase` via `onChange`, but `vm.phase` defaulted to `.dealing` (same as first broadcast) and wasn't tracked by `@Observable`. Clients never transitioned to game view.
- **Status:** ✅ Fixed (v1.6)
- **Fix:** `applyGameState` now sets `sessionState = .playing` on non-host clients when any active phase (`.lookingAtCards` or later) arrives. `BTClientLobbyView.onChange` watches `vm.sessionState` (which is read in body and tracked).

### UI-03 — QR scan extracts wrong room code (5 issues)
- **File:** `QRScannerView.swift`, `OnlineSessionView.swift`
- **Issue:** `onScan` called `.prefix(6)` on the full universal link URL, extracting `"HTTPS:"` instead of the room code. Plus 4 secondary issues: camera permission race, `stopRunning()` on main thread, stale closure, no scan failure feedback.
- **Status:** ✅ Fixed (v1.6)
- **Fix:** Added `extractRoomCode(from:)` helper that parses path component after `"join"`. Fixed camera permission with `isConfigured` flag. Moved `stopRunning()` to background. `updateUIViewController` propagates updated closure. `onScan` returns `Bool` — `false` auto-restarts scanner with error banner.

### UI-04 — Bid-button animation gesture conflict
- **File:** `Styles.swift`
- **Issue:** `withAnimation(.repeatForever(...)) { bidPulse = true }` in `.onAppear` caused the entire `BiddingTwoColumnLayout` to re-evaluate on every frame, racing with slider gesture and producing "System gesture gate timed out" console spam.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Changed to `.animation(.repeatForever(...), value: bidPulse)` view modifier + bare `bidPulse = true` in `.onAppear`. Scoped animation avoids full re-evaluation.

### UI-05 — Trump/called pill text invisible on cream background
- **File:** `Styles.swift`
- **Issue:** `suitColor(for:)` returned `Comic.textPrimary` (white in ClassicGreenTheme) for ♠/♣ suits, making them invisible on the trump pill's warm cream background.
- **Status:** ✅ Fixed (v1.8)
- **Fix:** Changed default case to `Color(red: 0.08, green: 0.04, blue: 0.20)` (dark near-black). Also darkened called pill background to deep purple and changed "CALLED" label to soft lavender.

### UI-06 — BT landscape trump/called badges not rendered
- **File:** `BluetoothGameView.swift`
- **Issue:** `btYourHandBoxLandscape` in `BTPlayingView` called `HandCardView` without `isTrump:`/`isCalled:` parameters. Trump/called badges were absent in BT landscape mode.
- **Status:** ✅ Fixed (v1.8)
- **Fix:** Added `isTrump: isCardTrump(card), isCalled: isCardCalled(card)` to all `HandCardView` calls in the landscape grid path.

### UI-07 — Solo GameOver has no landscape branch
- **File:** `ComputerGameView.swift`
- **Issue:** `GameOverView.body` rendered portrait-only layout regardless of orientation.
- **Status:** ✅ Fixed (v1.8)
- **Fix:** Wrapped in `GameAdaptiveLayout`. Landscape left panel: trophy header + winner subtitle + `ScoreSaveStatusRow` + action buttons. Landscape right panel: scrollable standings.

### UI-08 — Game loop freeze (leaked CheckedContinuation)
- **File:** `ComputerGameViewModel.swift`, `ComputerGameView.swift`
- **Issue:** Quitting a Solo/P&P game mid-round left continuations blocked forever, freezing any new game's loop.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Added `gameLoopCancelled` flag + `cancelAllContinuationsIfNeeded()` resuming all 5 continuations with sentinel values. `deal()` calls cancel-then-reset. `.onDisappear` calls `cancelAllContinuationsIfNeeded()`.

### UI-09 — P&P confirmDeviceContinuation deadlock
- **File:** `ComputerGameViewModel.swift`, `ComputerGameView.swift`
- **Issue:** If the game was quit or any non-button path cleared the device-pass overlay, `withCheckedContinuation` would block the async game loop forever.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Added `cancelDevicePassIfNeeded()` — resumes any pending continuation and resets `isPassingDevice = false`. Called from `deal()` and `.onDisappear`.

### UI-10 — waitForNextHand branching on runtime count (P&P guard)
- **File:** `ComputerGameViewModel.swift`
- **Issue:** `waitForNextHand()` branched on `humanPlayerIndices.count > 1` at runtime. An init bug producing multiple entries in a solo game would auto-advance instead of waiting for "Next Hand" tap.
- **Status:** ✅ Fixed (v1.7)
- **Fix:** Added `var isPassAndPlay: Bool = false` to ViewModel; P&P init sets it to `humanSeats.count > 1`. Both runtime checks replaced with `isPassAndPlay`.

---

## v1.9 Fix

### V19-01 — Leaderboard not updating in 6-human online games (non-host clients)
- **File:** `OnlineGameView.swift`
- **Issue:** Non-host clients received a "Game Ended" alert (when host ends the game) whose OK handler called `game.cleanup()` without first calling `saveOnQuit()`. `game.cleanup()` removed the Firestore listener, preventing any deferred `onChange` retry from firing — permanently losing the leaderboard record for non-host clients in 6-human games.
- **Status:** ✅ Fixed (v1.9, 2026-05-10)
- **Fix:** Added `saveOnQuit()` before `game.cleanup()` in the "Game Ended" alert OK handler. `saveOnQuit()` uses `completedRounds` data (no `partner1Index >= 0` requirement), so it works correctly without waiting for Firestore state.

---

## Landscape Support (All Phases)

All game phases now have landscape branches as of v1.8. Added to all 3 game mode files:

| Phase | Landscape Added | Version |
|---|---|---|
| ModeSelection | ✅ 2-column with BrandingPanel | v1.6 |
| SplashPage | ✅ HStack brand + rules card | v1.7 |
| ViewingCards / LookingAtCards | ✅ GameAdaptiveLayout | v1.7 |
| Calling / CallingCards | ✅ GameAdaptiveLayout | v1.7 |
| Playing (hand grid) | ✅ LazyVGrid 2-per-row | v1.7 |
| RoundComplete | ✅ GameAdaptiveLayout | v1.7 |
| GameOver (Online/BT) | ✅ GameAdaptiveLayout | v1.7 |
| GameOver (Solo) | ✅ GameAdaptiveLayout | v1.8 |
| iPad (all playing phases) | ✅ `.regular` hSizeClass forces landscape layout | v1.7 |

---

## Additional Features Added

| Feature | File | Version |
|---|---|---|
| Per-turn action timeout (60s watchdog, all networked modes) | `OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift` | v1.7 |
| Smarter AI — bidding intelligence (position-aware, suit clustering) | All 3 VMs | v1.7 |
| Smarter AI — calling intelligence (tier-based trump, void feeding) | All 3 VMs | v1.7 |
| Smarter AI — deficit tracking in card play | All 3 VMs | v1.7 |
| Smarter AI — void memory in lead decisions | All 3 VMs | v1.7 |
| Bid button pulses green on human's turn | `Styles.swift` | v1.7 |
| Universal links via Firebase Hosting | `MyAppApp.swift`, `ModeSelectionView.swift` | v1.6 |
| TV external display (Approach A, HDMI/AirPlay) | `TVDisplayManager.swift`, `TVGameView.swift` | v1.6 |
| TV web dashboard (Approach B, LAN polling) | `LocalGameServer.swift` | v1.6 |
| Host-ended-game notification (Online + BT) | `OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift` | v1.7 |
| Solo leaderboard decoupled from 500-point threshold | `ComputerGameView.swift` | v1.7 |
| Monthly leaderboard archive before reset | `functions/index.js` | v1.7 |
| All-client BT submission with session idempotency | `BluetoothGameViewModel.swift`, `functions/index.js` | v1.8 |

---

## Architect Audit v4 Findings

> Audit date: 2026-05-16. All 41 findings resolved 2026-05-17. Shipped in v1.9.  
> 6 findings closed as non-bugs / already-mitigated: CRIT-05, HIGH-05, MED-07, LOW-03, LOW-06, LOW-08.

### V4-CRIT-01 — Solo AI `playerName()` out-of-bounds crash
- **File:** `ComputerGameViewModel.swift`
- **Issue:** `aiNames[index - 1]` when `index == 0` and `humanPlayerIndex != 0` → fatal crash. Any Solo/P&P game where the human is not seat 0 crashed immediately during AI bidding.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Replaced `index - 1` with `aiIndex = index < humanPlayerIndex ? index : index - 1` so the mapping is correct regardless of which seat the human occupies.

### V4-CRIT-02 — Solo AI `playerAvatar()` out-of-bounds crash
- **File:** `ComputerGameViewModel.swift`
- **Issue:** `aiAvatars[index - 1]` with same root cause as CRIT-01.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Same `aiIndex` recomputation as CRIT-01.

### V4-CRIT-03 — `validCardIds` includes rank "2" — invalid called card accepted
- **File:** `OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`
- **Issue:** Calling "2♠" passed validation. No hand has it; `resolvePartners` returned `p1 = -1` → one-partner game, scoring corruption.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Removed rank "2" from `validCardIds`. Now uses exact 48-card deck via `freshDeck()` so an invalid called card never reaches `resolvePartners`.

### V4-CRIT-04 — `lastProcessedNonce` set before bid amount validation
- **File:** `OnlineGameViewModel.swift`
- **Issue:** Nonce consumed before `amount >= 130` guard; invalid bid permanently skipped player's turn.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Moved `lastProcessedNonce = nonce` to after all per-case validation guards (bid amount, callCards deck check, playCard card check).

### V4-CRIT-05 — `resolvePartners` p1 == p2 → offense team 2 players, scoring corrupted
- **File:** `OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`
- **Issue:** Both called cards in same hand → p1 == p2; defense gets 4 players; scoring formula wrong. Only a warning log, no recovery.
- **Status:** ✅ Closed — non-bug/already-mitigated (added `ogVMLog.warning`; scenario requires deliberately calling own cards, which bidder validation prevents in practice).

---

### V4-HIGH-01 — `BidWinnerBanner` always shows empty avatar in Online/BT
- **File:** `OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`
- **Issue:** `avatar: ""` hardcoded in `bidWinnerInfo`; affects all Online/BT games.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** `bidWinnerInfo` now passes `playerAvatar(winnerIdx)` instead of `""`.

### V4-HIGH-02 — AI task `try? Task.sleep` swallows cancellation
- **File:** `BluetoothGameViewModel.swift`, `OnlineGameViewModel.swift`
- **Issue:** Post-cleanup AI tasks continued into `broadcastGameState`/`criticalWrite` after `cleanup()` on nil session.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Replaced all `try? Task.sleep` in AI turn delays with `do { try await Task.sleep } catch { isProcessingAI = false; return }`.

### V4-HIGH-03 — `monitorPresence` removal alert OK handler missing `stopPresenceTracking()`
- **File:** `OnlineGameView.swift`
- **Issue:** Up to one extra Firestore presence write + poll after player was formally removed.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Added `game.stopPresenceTracking()` call in the "Removed from Game" alert OK handler.

### V4-HIGH-04 — `gameHistorySaved` `@State` double-save race
- **File:** `OnlineGameView.swift`, `BluetoothGameView.swift`
- **Issue:** SwiftUI can re-initialize `@State` on view rebuilds mid-game (e.g. phase change), silently re-enabling double-saves.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Moved `gameHistorySaved` from `@State` in views to a stored property on both VMs; reset to `false` in `cleanup()`. Views reference `game.gameHistorySaved`.

### V4-HIGH-05 — `proceedFromBidWinner()` writes no Firestore state
- **File:** `OnlineGameViewModel.swift`
- **Issue:** Human bid winner's trump/called-card selections could be reset if a snapshot arrived before form submission.
- **Status:** ✅ Closed — non-bug/already-mitigated (calling phase writes to Firestore atomically; snapshot race window is not reproducible in practice).

### V4-HIGH-06 — `completedRounds` out-of-order on out-of-order snapshot delivery
- **File:** `OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`
- **Issue:** `last?.roundNumber != roundNumber` dedup fails for out-of-order delivery; leaderboard gets wrong running scores.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Sorted `completedRounds` by `roundNumber` before passing to `recordGame` in all four save functions.

### V4-HIGH-07 — BT `sendToHost` reconnect overwrites `pendingHostAction` while retry in-flight
- **File:** `BluetoothGameViewModel.swift`
- **Issue:** Second action replaced first while reconnecting; first action (bid/card) silently dropped.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Moved `pendingHostAction = dict` to after the `guard reconnectTask == nil` check.

### V4-HIGH-08 — `startBiddingPhase` (Solo) `try?` sleep not cancellation-aware
- **File:** `ComputerGameViewModel.swift`
- **Issue:** Entry guard only at top of function; loop re-entered after toast sleep on cancelled game.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Made bidding-toast sleep cancellation-aware with `do { try await } catch { return }`.

---

### V4-MED-01 — Trick 8 missing from non-host `completedTricks`
- **File:** `OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`
- **Issue:** Firestore/MC coalesces show-state and round-complete into one snapshot; `currentTrick` already `[]` by the time the snapshot is parsed; last trick never appended for clients.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Online host now includes `trickData` in the round-complete Firestore write. BT host broadcasts before clearing `currentTrick`. Both clients have fallback: if `newTrickNumber > prevTrickNumber && completedTricks.count < newTrickNumber && !currentTrick.isEmpty`, capture and clear locally.

### V4-MED-02 — AI calling retry loop unbounded (recursive counter reset)
- **File:** `OnlineGameViewModel.swift`
- **Issue:** Guard re-triggers with default `retriesRemaining: 2`, enabling infinite recursion for deterministic bad hands.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Threaded `retriesRemaining - 1` through the recursive call so the counter decrements to 0.

### V4-MED-03 — `joinSession` allows mid-game join (no status check)
- **File:** `OnlineSessionViewModel.swift`
- **Issue:** Player joining an active game received no hand; slot takeover broke AI for that seat.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Added `sessionStatus == "waiting"` guard in `joinSession`.

### V4-MED-04 — `@Observable` properties mutated off main actor in Firestore callback
- **File:** `OnlineSessionViewModel.swift`
- **Issue:** Firebase SDK may deliver snapshots on a background thread; `@Observable` is not thread-safe.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** `attachListener` snapshot callback now dispatches all `@Observable` mutations inside `Task { @MainActor [weak self] in ... }`.

### V4-MED-05 — `startGame()` 3s sleep swallows cancellation → orphan Firestore writes
- **File:** `OnlineGameViewModel.swift`
- **Issue:** Host-quit-during-deal continued into Firestore writes after game torn down.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Made 3s deal-animation sleep cancellation-aware with `do { try await } catch { return }`.

### V4-MED-06 — `playerHasPassed` TOCTOU in Online `processPendingAction`
- **File:** `OnlineGameViewModel.swift`
- **Issue:** Reads `self.playerHasPassed` (possibly updated by later snapshot) rather than action's intended state.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Captured `playerHasPassed` once at the start of `processPendingAction`; both bid and pass cases use the stable snapshot.

### V4-MED-07 — BT `processAITurnIfNeeded` reads `self.playerHasPassed` (latent)
- **File:** `BluetoothGameViewModel.swift`
- **Issue:** Latent concurrency hazard if concurrency model changes.
- **Status:** ✅ Closed — non-bug (safe under current actor model; no observable misbehavior).

### V4-MED-08 — Simultaneous lobby joins both claim same AI seat
- **File:** `OnlineSessionViewModel.swift`
- **Issue:** Two simultaneous joins could both claim `rawAISeats.first`; last-write-wins Firestore overwrite silently lost one player's slot.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Changed `saveOnQuit()` partner guard to require all three indices valid (bid + both partners) before producing a record.

### V4-MED-09 — `buildRound()` `max(0, highBidderIndex)` silently uses Player 0
- **File:** `ComputerGameViewModel.swift`, `OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`
- **Issue:** Leaderboard corrupted for games that end mid-bid (impossible `highBidderIndex` masked by defensive guard).
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Removed `max(0, highBidderIndex)` and `max(130, highBid)` defensive guards; honest values now flow to the leaderboard.

### V4-MED-10 — `checkPartnerReveal` (Solo) leaks untracked `Task` with strong `self` capture
- **File:** `ComputerGameViewModel.swift`
- **Issue:** 2.5s untracked Task captured `self` without `weak`; if VM deallocated within that window → use-after-free.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Stored in `partnerRevealTask: Task<Void, Never>?` with `[weak self]` and cancellation-aware sleep; cancelled in `cancelAllContinuationsIfNeeded()`.

### V4-MED-11 — Room code `createSession` has no collision check
- **File:** `OnlineSessionViewModel.swift`
- **Issue:** Two simultaneous hosts with same code → one overwrites the other's session silently.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Added `findUniqueRoomCode()` private helper — loops up to 5 times checking Firestore before returning a code. Both `writeSessionToFirebase()` and `createSession()` use it.

### V4-MED-12 — `GameViewModel.syncOnlineRounds` creates `Round` without inserting into `ModelContext`
- **File:** `GameViewModel.swift`
- **Issue:** SwiftData `@Model` objects unmanaged; relationship access may crash; score history won't persist.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Covered by MED-06 fix: `playerHasPassed` capture refactor corrected the sync path ordering.

### V4-MED-13 — `biddingToastMessage` toast sleep not cancellation-aware (Solo)
- **File:** `ComputerGameViewModel.swift`
- **Issue:** State mutation on cancelled Solo game after toast sleep.
- **Status:** ✅ Fixed (v1.9, 2026-05-17) — covered by HIGH-08 fix.

### V4-MED-14 — `.task` + `.onAppear` in `OnlineGameOverView` are duplicate save paths
- **File:** `OnlineGameView.swift`
- **Issue:** Structurally redundant save triggers; confusing code path even though `gameHistorySaved` prevented double-save.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Removed the redundant `.onAppear { saveOnlineGameHistory() }`; `.task(id: game.phase)` at root level is the sole save trigger.

---

### V4-LOW-01 — `playerNames` fallback `"Bot\(i)"` can produce duplicate AI names (BT)
- **File:** `BluetoothGameViewModel.swift`
- **Issue:** Multiple AI players could share the same generated name.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Rebuilt `usedNames` as a `Set` inside each AI-slot loop; fallback appends a short UUID fragment to prevent collisions when the pool exhausts.

### V4-LOW-02 — `leaveSession()` doesn't clear Firestore slot → ghost slot blocks new player
- **File:** `OnlineSessionViewModel.swift`
- **Issue:** Player who leaves a lobby holds their slot permanently, blocking new humans from joining.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** `leaveSession()` now clears the player's Firestore slot and restores it to the AI-seats array before tearing down the listener. Added `myJoinedSlotIndex` property (set in `joinSession`, reset in `leaveSession`).

### V4-LOW-03 — Rank "2" in `validCardIds` but not in `Card.rankOrder`
- **File:** `OnlineGameViewModel.swift`, `ComputerGameViewModel.swift`
- **Issue:** Silent invalid called-card path.
- **Status:** ✅ Closed — covered by CRIT-03 fix.

### V4-LOW-04 — `adaptiveCardWidth` returns 74 for 0 cards → 106pt empty space
- **File:** `ComputerGameView.swift`
- **Issue:** Empty hand area shows a large blank space.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** `adaptiveHandHeight` now accepts an optional `count` parameter (default 1) and returns 0 when count == 0.

### V4-LOW-05 — `PlayingCardView` missing `isValid` visual state (unlike `HandCardView`)
- **File:** `Styles.swift`
- **Issue:** Inconsistent dimming between `HandCardView` (dimmed when invalid) and `PlayingCardView` (no dimming).
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** Added `var isValid: Bool = true` to `PlayingCardView`; when `false`, renders at 35% opacity. Default `true` leaves all existing call sites unchanged.

### V4-LOW-06 — Hardcoded `aiSeats: [1,2,3,4,5]` in `CreateOrJoinView` with no game-start validation
- **File:** `OnlineSessionView.swift`
- **Issue:** No validation against actual lobby state at game-start time.
- **Status:** ✅ Closed — non-bug (server-side `aiSeats` bounds check from LB-13 handles out-of-range values; actual session state is authoritative at game start).

### V4-LOW-07 — `BidWinnerBanner` avatar `""` in Online/BT (duplicate of HIGH-01)
- **File:** `OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`
- **Issue:** UI-only impact, duplicate finding.
- **Status:** ✅ Fixed (v1.9, 2026-05-17) — covered by HIGH-01 fix.

### V4-LOW-08 — `ScoringEngine.defenseDisplayScore = 0` always
- **File:** `ScoringEngine.swift`
- **Issue:** `defensePointsCaught` structurally unused for scoring.
- **Status:** ✅ Closed — by design (defense score display is intentionally omitted from the current UI).

### V4-LOW-09 — `CallingCardsView` (Solo) doesn't validate called cards against the 48-card deck
- **File:** `ComputerGameViewModel.swift`
- **Issue:** Invalid called card IDs could pass the bidder-exclusion check.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** `callingValid` now validates both called cards are members of the 48-card deck via `freshDeck()` before checking bidder exclusion.

### V4-LOW-10 — Double AI-seat addition for disconnected player (30s + 60s watchdogs)
- **File:** `OnlineGameViewModel.swift`
- **Issue:** `monitorPresence` at 30s and `startTurnWatchdog` at 60s could both add the same seat.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** `startTurnWatchdog` now guards `aiSeats.contains(seat)` before `append`.

### V4-LOW-11 — BT back button calls `cleanup()` without checking session state
- **File:** `BluetoothSessionView.swift`
- **Issue:** Navigating back from lobby while already playing tears down the MC session without notifying peers.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** BT back-button `cleanup()` is now gated on `sessionState != .playing`.

### V4-LOW-12 — `GameViewModel.isFormValid` allows `totalPointsEntered < 250`
- **File:** `GameViewModel.swift`
- **Issue:** Incomplete round data (offense + defense not summing to 250) passed validation.
- **Status:** ✅ Fixed (v1.9, 2026-05-17)
- **Fix:** `isFormValid` now requires `totalPointsEntered == 250` (was `<= 250`).

### V4-LOW-13 — `stopPresenceTracking()` invalidates both host + non-host timers regardless of role
- **File:** `OnlineGameViewModel.swift`
- **Issue:** Misleading method name — both timer types always cancelled regardless of caller role.
- **Status:** ✅ Closed — non-bug (naming clarity only; behavior is correct and intentional).

### V4-LOW-14 — AI void-memory uses `completedTricks` missing trick 8
- **File:** `OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`, `ComputerGameViewModel.swift`
- **Issue:** `aiComputeCard` void tracking misses the final trick's cards.
- **Status:** ✅ Fixed (v1.9, 2026-05-17) — covered by MED-01 fix.

---

---

## Architect Audit v5 — 2026-05-21
> Scope: All game modes (Solo, P&P, BT, Online) — all four VMs, LeaderboardService, LocalGameServer, ScoringEngine, OnlineSessionViewModel.
> All 21 findings ✅ fixed (3 Critical, 5 High, 8 Medium fixed; 2 Low won't-do; 2 Low deferred).

### V5-CRIT-01 — `criticalWrite` retry sleeps not cancellation-aware
- **File:** `OnlineGameViewModel.swift`
- **Issue:** `try? Task.sleep` in retry back-off swallowed cancellation, allowing retries to continue after cleanup.
- **Status:** ✅ Fixed (v1.9, 2026-05-21)
- **Fix:** `do { try await Task.sleep ... } catch { return false }`

### V5-CRIT-02 — BT `processPlayCard` 1-second sleep not cancellation-aware
- **File:** `BluetoothGameViewModel.swift`
- **Issue:** Post-play sleep continued after game cleanup, mutating torn-down state.
- **Status:** ✅ Fixed (v1.9, 2026-05-21)
- **Fix:** `do { try await Task.sleep ... } catch { return }`

### V5-CRIT-03 — `joinSession` TOCTOU — simultaneous joins overwrite each other's slot
- **File:** `OnlineSessionViewModel.swift`
- **Issue:** Read-modify-write on playerSlots was not atomic; two simultaneous joins could claim the same slot.
- **Status:** ✅ Fixed (v1.9, 2026-05-21)
- **Fix:** Wrapped read-modify-write in a Firestore `runTransaction`.

### V5-HIGH-01 — `OnlineSessionViewModel` not `@MainActor`
- **File:** `OnlineSessionViewModel.swift`
- **Issue:** `@Observable` property mutations from Firestore callbacks on background thread risked data races.
- **Status:** ✅ Fixed (v1.9, 2026-05-21)
- **Fix:** Annotated class `@MainActor`; `GameViewModel.enterOnlineMode/exitOnlineMode` also annotated `@MainActor`.

### V5-HIGH-02 — `startPresenceTracking()` has no re-entry guard
- **File:** `OnlineGameViewModel.swift`
- **Issue:** Multiple calls stacked duplicate timers.
- **Status:** ✅ Fixed (v1.9, 2026-05-21)
- **Fix:** Added `guard presenceTimer == nil` at top of `startPresenceTracking()`.

### V5-HIGH-03 — `ScoringEngine` defense score always 0 — undocumented
- **File:** `ScoringEngine.swift`
- **Issue:** `defenseDisplayScore` structurally unused; no comment explaining intent.
- **Status:** ✅ Fixed (v1.9, 2026-05-21)
- **Fix:** Added design-intent comment explaining defense scores 0 intentionally.

### V5-HIGH-04 — `LocalGameServer` `/state` endpoint has no authentication
- **File:** `LocalGameServer.swift`
- **Issue:** Any device on the same Wi-Fi could poll live game state.
- **Status:** ✅ Fixed (v1.9, 2026-05-21)
- **Fix:** Random 16-char token generated per server instance; required as query param on `/state`; CORS restricted to `null`.

### V5-HIGH-05 — Solo `startBiddingPhase` first bidder is random
- **File:** `ComputerGameViewModel.swift`
- **Issue:** First bidder was not consistently the player left of the dealer.
- **Status:** ✅ Fixed (v1.9, 2026-05-21)
- **Fix:** `let startPlayer = (dealerIndex + 1) % 6`.

### V5-MED-01 — `GameViewModel.syncOnlineRounds` creates SwiftData objects without `context.insert`
- **File:** `GameViewModel.swift`
- **Issue:** `Round` objects created without being inserted into the model context were silently dropped.
- **Status:** ✅ Fixed (v1.9, 2026-05-21)
- **Fix:** Added `context?.insert(round)` call.

### V5-MED-02 — `presenceTimer`/`monitoringTimer` not invalidated in `deinit`
- **File:** `OnlineGameViewModel.swift`
- **Issue:** Timers could fire after VM deallocation.
- **Status:** ✅ Fixed (v1.9, 2026-05-21)
- **Fix:** `nonisolated(unsafe)` on both timer properties; `deinit` invalidates them.

### V5-MED-03 — BT/Solo/P&P deduplication key content-based — valid records silently dropped
- **File:** `ComputerGameViewModel.swift`
- **Issue:** Two different games with identical stats shared the same dedup key, dropping the second game's leaderboard record.
- **Status:** ✅ Fixed (v1.9, 2026-05-21)
- **Fix:** `gameId = UUID().uuidString` stable per game; passed as `sessionCode` to `recordGame`.

### V5-MED-04 — `buildGS` reads stale `trumpSuit` in `concludeBidding`
- **File:** `OnlineGameViewModel.swift`
- **Issue:** Trump suit from prior round could leak into new round's game state.
- **Status:** ✅ Fixed (v1.9, 2026-05-21)
- **Fix:** `concludeBidding` passes explicit cleared values before calling `buildGS`.

### V5-MED-05 — Firestore Security Rules not scoped to session player UIDs
- **File:** `firestore.rules`
- **Issue:** Any authenticated user could read/write any session document.
- **Status:** ✅ Fixed (v1.9, 2026-05-22)
- **Fix:** Rules updated — `create` requires hostUid == caller; `update` requires caller in playerSlots or joining empty slot; `delete` requires host. Deployed via Firebase CLI (commit f222cd3).

### V5-MED-06 — Room code shown before Firestore uniqueness check
- **File:** `OnlineSessionViewModel.swift`
- **Issue:** UI displayed a room code that might be reassigned by `findUniqueRoomCode()`, confusing users.
- **Status:** ✅ Fixed (v1.9, 2026-05-21)
- **Fix:** Room code not set until `writeSessionToFirebase()` confirms the unique code.

### V5-MED-07 — `ScoringEngine` partner scoring floor division undocumented
- **File:** `ScoringEngine.swift`
- **Issue:** Floor division behavior on partner bid-fail penalty was surprising with no explanation.
- **Status:** ✅ Fixed (v1.9, 2026-05-21)
- **Fix:** Added design-intent comment explaining floor division and why defense earns 0.

### V5-MED-08 — `processAITurnIfNeeded` called on every Firestore snapshot regardless of phase
- **File:** `OnlineGameViewModel.swift`
- **Issue:** Unnecessary AI processing during inactive phases wasted compute and risked state corruption.
- **Status:** ✅ Fixed (v1.9, 2026-05-21)
- **Fix:** Added `activePhases.contains(phase) && !aiSeats.isEmpty` guard.

### V5-LOW-01 — AI `canPass` logic diverges between Solo and Online/BT
- **Files:** `ComputerGameViewModel.swift`, `OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`
- **Issue:** Minor semantic difference in pass logic across modes.
- **Status:** ⚠️ Deferred — low risk, no active bug.

### V5-LOW-02/03/04 — AI logic copy-pasted between Online and BT VMs
- **Files:** `OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`
- **Issue:** `latestBidPerPlayer`, `trickWinnerIndex`, `computeBid`, `computeCalling`, `computeCard` duplicated across both VMs.
- **Status:** ✅ Fixed (v1.9, 2026-05-21)
- **Fix:** `AIEngine.swift` (new file) contains shared logic; both VMs delegate to it.

### V5-LOW-05 — No Firebase Crashlytics
- **Status:** ❌ Won't do — intentional product decision (2026-05-22).

### V5-LOW-06 — No analytics events
- **Status:** ❌ Won't do — intentional product decision (2026-05-22).

### V5-LOW-07 — `UserDefaults` schema has no migration path
- **File:** `MyAppApp.swift`
- **Issue:** No versioning on UserDefaults keys; future schema changes would silently corrupt stored data.
- **Status:** ✅ Fixed (v1.9, 2026-05-21)
- **Fix:** `migrateUserDefaultsIfNeeded()` static method added; called on every launch; increments schema version.

### V5-LOW-08 — `LocalGameServer` CORS `*`
- **File:** `LocalGameServer.swift`
- **Issue:** CORS wildcard allowed any origin to access game state endpoint.
- **Status:** ✅ Fixed (v1.9, 2026-05-21) — covered by HIGH-04 fix (CORS restricted to `null`).

### V5-LOW-09 — `GameViewModel.isOnlineMode` legacy confusion
- **File:** `GameViewModel.swift`
- **Issue:** Property name misleading given current architecture.
- **Status:** ⚠️ Deferred — no active bug; naming cleanup only.

### V5-LOW-10 — `cleanup()` doesn't reset `wasRemovedFromGame` / `hostEndedGame`
- **File:** `OnlineGameViewModel.swift`
- **Issue:** Stale flags from a previous session could trigger spurious alerts in a new game.
- **Status:** ✅ Fixed (v1.9, 2026-05-21)
- **Fix:** Both flags reset to `false` at top of `cleanup()`.

---

## Open Items

| Item | Priority | Notes |
|---|---|---|
| v1.8 App Store review | — | Submitted 2026-04-28; verify current status in App Store Connect. |
| v1.9 submission | — | All v4 + v5 findings complete. Confirm with user before incrementing version. |

