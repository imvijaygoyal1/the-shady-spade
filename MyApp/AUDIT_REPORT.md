# The Shady Spade — Comprehensive Audit Report

> **Last updated:** 2026-05-10  
> **Scope:** All bug fixes, security patches, and architectural changes from v1.5 through v1.9.  
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
| **Total** | **61** | **✅ All resolved** |

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

## Open Items

| Item | Priority | Notes |
|---|---|---|
| v1.8 App Store review | — | Submitted 2026-04-28; under review. All new changes tracked under v1.9. |
| v1.9 submission | — | Only change so far: V19-01 (leaderboard fix). Confirm with user before incrementing version. |

