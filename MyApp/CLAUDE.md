# The Shady Spade — Claude Code Context

> **IMPORTANT FOR CLAUDE:** After every code change to this project, update this file to reflect the change. New file → add to File Map. New component → add to Styles section. Changed pattern → update Key Patterns. Version bump → update App Identity. This file must always stay current.
> **RELEASE TRACKING:** v1.7 submitted to App Store on April 23, 2026 — under review. Log all new changes under a **v1.8 Changelog** section. Do not increment the version number until the user confirms v1.8 is ready to submit.

## v1.8 Changelog
> Changes made after v1.7 App Store submission (April 23, 2026). Add entries here as changes are implemented.

- [2026-04-28] How to Play — Trump & Calling Cards: added visual cue descriptions (trump cards = yellow tint + gold border, called cards you hold = purple border + glow, 3♠ = gold regardless). No privacy policy changes needed — policy already accurately describes offline queuing and all-mode leaderboard recording; no new data collected in v1.8. (`SettingsView.swift`)

- [2026-04-25] Fix landscape trump/called highlighting + Solo GameOver landscape + scoreSaveStatus stale state — (1) **BT landscape hand isTrump/isCalled:** `btYourHandBoxLandscape` in `BTPlayingView` (`BluetoothGameView.swift`) was calling `HandCardView` without `isTrump:`/`isCalled:` in the `LazyVGrid` landscape path. Added `isTrump: isCardTrump(card), isCalled: isCardCalled(card)` — trump/called badges now render in landscape for BT mode. (Same fix was applied to Online in the prior session.) (2) **Solo GameOverView landscape branch:** Wrapped `GameOverView.body` in `GameAdaptiveLayout`. Portrait branch is unchanged. Landscape branch: left panel (`Comic.containerBG`) = trophy header + winner subtitle + `ScoreSaveStatusRow` + Play Again / Game History / Quit buttons; right panel (`Comic.bg`) = scrollable standings `ForEach` with `GeometryReader` score bars. (`ComputerGameView.swift`) (3) **scoreSaveStatus stale between games:** Added `scoreSaveStatus = .idle` at the top of `recordGame()` in `LeaderboardService`, before `enqueue(pending)` and before `scoreSaveStatus = .saving`. `@MainActor` guarantees no visible flash between `.idle` and `.saving` since there is no `await` between them. Previously `.saved` from game N persisted into game N+1's `GameOverView` until the new save request completed. (`LeaderboardService.swift`)

- [2026-04-25] Fix BT leaderboard remaining defects (#5 BT + #6 BT) — (1) **#5 BT all-client submit:** `BluetoothGameViewModel` now generates a `gameSessionId` (10-char lowercase alphanumeric UUID fragment) in `startHosting()`. It is included in `buildGameStateDict()` and read in `applyGameState()` on all peers, so every client has the same stable session identifier. `saveBTGameHistory()` and `saveOnQuit()` pass it as `sessionCode` to `recordGame()`; the Cloud Function's existing transaction-based idempotency (first write wins) suppresses duplicate submissions from non-host clients. `saveBTGameHistory()` guard changed from `guard game.isHost` to none (all clients can save at `.gameOver`); `saveOnQuit()` guard changed from `guard game.isHost` to `if !game.isHost && game.phase != .gameOver { return }`. (`BluetoothGameViewModel.swift`, `BluetoothGameView.swift`) (2) **#6 BT partner-indices -1:** Removed `guard game.partner1Index >= 0, game.partner2Index >= 0` hard bail from `saveBTGameHistory()`. Primary path now uses `completedRounds` (populated in `applyGameState()` with -1→0 normalisation already applied). Synthetic-round fallback uses `max(0, partner1Index)` / `max(0, partner2Index)` so -1 indices never propagate to the Cloud Function. (`BluetoothGameView.swift`)

- [2026-04-25] Fix host-crash leaderboard loss (#5) — Option C: all-client submission + server idempotency. **Problem:** `saveOnlineGameHistory()` and `saveOnQuit()` both had `guard game.isHost else { return }`, so if the host crashed before calling `recordGame()`, all 6 players' stats were permanently lost. **Fix — iOS:** (1) `PendingGameRecord` gained a `sessionCode: String?` field; `deduplicationKey` uses it as the stable key for Online games. (2) `recordGame(sessionCode:)` parameter added (default `""`); passed through to `PendingGameRecord` init and included in the HTTP payload. (3) `saveOnlineGameHistory()`: removed `guard game.isHost` — all clients (including non-hosts) now submit independently. (4) `saveOnQuit()`: guard changed to `if !game.isHost && game.phase != .gameOver { return }` — non-hosts can only save at `.gameOver` (when they have full final state), not mid-game. Both calls pass `sessionCode: game.sessionCode`. **Fix — Cloud Function:** `sessionCode` extracted from payload (alphanumeric 1–10 chars). When present, the entire write runs inside a Firestore transaction: reads `game_log/{sessionCode}` first; if the doc already exists, returns 200 immediately (idempotent — second+ client submissions are silent no-ops, first write wins). If not found, `txn.set(logRef, logData)` + `txn.set(playerStatsRef, update, merge: true)` for each non-AI player. BT/Solo/P&P (no `sessionCode`) continue to use the original batch-write path. Deployed to `us-central1-shadyspade-d6b84`. (`LeaderboardService.swift`, `OnlineGameView.swift`, `functions/index.js`)

- [2026-04-25] Fix 2 low-priority leaderboard defects — (1) **P&P mode string (#12):** `ComputerGameView` now sends `"PassAndPlay"` to the Cloud Function for Pass-and-Play games instead of `"Multiplayer"`. All 3 mode-string sites (`GameOverView.onAppear`, X-button quit, `saveAndQuit()`) now use `game.isPassAndPlay ? "PassAndPlay" : (game._allPlayerNames.isEmpty ? "Solo" : "Multiplayer")`. (`ComputerGameView.swift`) (2) **`aiSeats` bounds check server-side (#13):** Cloud Function now filters `payload.aiSeats` to only include integers in [0, 5] before building the Set: `.filter(i => Number.isInteger(i) && i >= 0 && i < PLAYER_COUNT)`. Out-of-range values are silently dropped rather than accepted into the Set. Note: **#7 (leet-speak name)** was confirmed already fixed — `ProfanityFilter.swift` has an identical `normalise()` function and word list to the server's `normaliseName()`. No iOS change needed. **#14 (stale runningScores in saveOnQuit)** is intentional behavior — scores reflect the last completed round, not a partial round in progress. (`functions/index.js`)

- [2026-04-25] Fix 4 medium leaderboard defects — (1) **No HTTP timeout (#8):** Added `request.timeoutInterval = 10` to `URLRequest` in `sendRecord()`. Prevents each attempt blocking for up to 60s (URLSession.shared default), capping worst-case total save time to ~24s (3×10s + 2s+4s backoff). (`LeaderboardService.swift`) (2) **Unbounded pending queue (#9):** `enqueue()` now trims to the 100 most-recent entries after appending, preventing unlimited UserDefaults growth on offline-heavy devices. (`LeaderboardService.swift`) (3) **No deduplication in queue (#10):** Added `deduplicationKey` computed property to `PendingGameRecord` (gameMode|playerNames|roundCount|bid|winnerIndex). `enqueue()` skips append if an existing record with the same key is already queued, preventing double-submission from onChange retry races. (`LeaderboardService.swift`) (4) **`completedRounds` empty at game-over → `saveOnQuit()` silent skip (#11):** Both `OnlineGameView.saveOnQuit()` and `BluetoothGameView.saveOnQuit()` now fall back to a synthetic `HistoryRound` built from current game state when `completedRounds` is empty but `highBidderIndex >= 0`. Handles the Firestore/MC snapshot race where `.gameOver` arrives before the round-complete transition appended to `completedRounds`. (`OnlineGameView.swift`, `BluetoothGameView.swift`)

- [2026-04-25] Fix leaderboard record lost when app killed mid-send (#1) — `recordGame()` in `LeaderboardService` now enqueues the `PendingGameRecord` to `UserDefaults` **before** launching the HTTP attempt, then calls `removeFromQueue(id:)` on success or server rejection. Previously, the record was only enqueued in the `.networkFailure` branch — if the OS killed the process after `gameHistorySaved = true` was set but before the HTTP attempt completed, the record was permanently lost with no entry in the pending queue. Now the record always survives a process kill and is flushed on next launch. (`LeaderboardService.swift`)

- [2026-04-25] Fix 3 critical leaderboard silent-failure scenarios — (1) **BT game-over quit missing save (#2):** `BTGameOverView` quit closure now calls `saveOnQuit()` before `game.cleanup()`, matching Online and X-button patterns. Previously, tapping "Quit to Menu" on the BT game-over screen would kill the MC listener before the `onChange` partner-index retry could fire. (`BluetoothGameView.swift`) (2) **Auth failure → flush → 401 → permanent discard (#3):** Added `ensureAuthenticated()` private method to `LeaderboardService` that calls `Auth.auth().signInAnonymously()` (async) if `currentUser` is nil. Called at the top of `flushPendingRecords()` so that records queued during an offline session are not permanently discarded with a 401 when flushed later without a valid user. (`LeaderboardService.swift`) (3) **TOCTOU race in `flushPendingRecords` (#4):** Replaced stale-snapshot write pattern (`savePendingRecords(remaining)` at the end) with per-record `removeFromQueue(id:)` calls after each successful or rejected send. `removeFromQueue` does a fresh `loadPendingRecords()` → `removeAll { $0.id == id }` → `savePendingRecords()` with no `await`, making it atomic on `@MainActor`. Records enqueued during a flush are no longer overwritten. (`LeaderboardService.swift`)

- [2026-04-25] Fix leaderboard not updating after online multiplayer game — Three root causes fixed: (1) **Game-over "Quit to Menu" missing save**: `OnlineGameOverView`'s quit closure now calls `saveOnQuit()` before `game.cleanup()`, matching the existing pattern on the X-button and round-complete quit paths. Previously, tapping "Quit to Menu" on the game-over screen would call `game.cleanup()` before the `onChange` partner-index retry could fire, permanently skipping the leaderboard write. (`OnlineGameView.swift`) (2) **`aiSeats` never passed to `OnlineGameViewModel`**: `onGameReady` closure signature extended with a `[Int]` aiSeats parameter in `OnlineSessionView` (both `OnlineSessionView` struct and `SessionLobbyView`); call site passes `sessionVM.aiSeats`; `OnlineEntryView` in `ModeSelectionView` forwards the new param to `OnlineGameViewModel(aiSeats:)`. Previously `game.aiSeats` started as `[]` for the entire game, causing AI player names to be written to `player_stats` and the mode tag to be wrong when the save fired before the first Firestore snapshot. (`OnlineSessionView.swift`, `ModeSelectionView.swift`)

- [2026-04-25] Fix trump/called pill readability in GameInfoPillsRow — `suitColor(for:)` in `GameInfoPillsRow` was returning `Comic.textPrimary` (white in ClassicGreenTheme) for ♠/♣ suits, making them invisible on the trump pill's warm cream background and the called badge's white background. Changed default case to `Color(red: 0.08, green: 0.04, blue: 0.20)` (dark near-black). Also applied earlier style polish: called pill background darkened to deep purple `(0.231, 0.122, 0.431)`, "CALLED" label changed to soft lavender `(0.769, 0.714, 0.988)`, badge background set to `Color.white`, and badge parsing made Unicode-safe (suffix-match on known suit characters instead of `String.last`). (`Styles.swift`)

- [2026-04-23] Fix leaderboard not updating when user quits mid-game — **Solo:** X-button confirmation dialog now calls `saveGameHistory(finalScores: runningScores)` before `dismiss()` if `savedHistoryRounds` is non-empty (i.e. at least one round was completed). **Online/BT:** Added `saveOnQuit()` private function that guards on `completedRounds.isEmpty` rather than on `highBidderIndex/partnerIndex >= 0` (those can be -1 mid-round if bidding hasn't concluded for the new round). `saveOnQuit()` is now called before `game.cleanup() + dismiss()` in two paths per mode: (1) X-button confirmation dialog, (2) "Quit to Menu" from `RoundCompleteView`. The `gameHistorySaved` flag prevents double-saves. Games with zero completed rounds still produce no record. (`ComputerGameView.swift`, `OnlineGameView.swift`, `BluetoothGameView.swift`)

- [2026-04-23] Host-ended-game notification for Online/BT modes — when the host taps "Quit to Menu" (game over, round complete, or X-button mid-game), non-host players now see a "Game Ended — The host has ended the game." alert. Tapping OK runs `game.cleanup()` + `dismiss()` and navigates them to the mode selection screen. **Online:** `notifyHostEndedGame()` writes `gameState.hostEndedGame = true` to Firestore before `cleanup()`; `parseGameState()` sets `hostEndedGame = true` on non-host clients when it reads the flag; view watches via `.onChange(of: game.hostEndedGame)` and shows `.alert`. **BT:** `notifyHostEndedGame()` broadcasts `{"type": "hostEndedGame"}` via MC; `handleMessage` case sets `hostEndedGame = true` on clients; host waits 400ms before `cleanup()` to ensure message arrives before session disconnects; disconnect handler suppresses "X disconnected" error banner when `hostEndedGame = true`. All three quit paths covered in both modes: game over "Quit to Menu", round complete "Quit to Menu", mid-game X button. (`OnlineGameViewModel.swift`, `OnlineGameView.swift`, `BluetoothGameViewModel.swift`, `BluetoothGameView.swift`)

- [2026-04-23] Decouple Solo leaderboard save from 500-point threshold — Previously `nextRound()` called `saveGameHistory()` inside the `if updated.max() >= targetScore` branch, coupling the score gate to the save. Removed the save call from that branch (score check now only sets `isGameOver = true`). Added `@State private var soloGameSaved = false` flag. Save now fires from `GameOverView.onAppear` (guarded by `soloGameSaved`). All paths updated: X-button quit guards with `!soloGameSaved`; `saveAndQuit()` sets `soloGameSaved = true`; `playAgain()` resets `soloGameSaved = false`. The 500-point threshold has zero effect on when the leaderboard record is created. 21/21 tests pass. (`ComputerGameView.swift`)

## v1.7 Changelog
> Submitted to App Store April 23, 2026 — under review.

- [2026-04-23] Fix ForEach ID collision in RoundComplete — `offenseTeam` computed var in all 3 RoundComplete views (`ComputerGameView.swift`, `OnlineGameView.swift`, `BluetoothGameView.swift`) could produce duplicate player indices when both called cards are held by the same player (partner1Index == partner2Index). Changed from plain `compactMap`/`filter` to a `seen: Set<Int>` dedup pattern that preserves first-appearance order. This silences the "ID N occurs multiple times within the collection, this will give undefined results" SwiftUI warning.

- [2026-04-23] Fix bid-button animation gesture conflict — replaced `withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) { bidPulse = true }` in `.onAppear` with `.animation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true), value: bidPulse)` view modifier + bare `bidPulse = true` in `.onAppear`. Scoped animation avoids the whole `BiddingTwoColumnLayout` re-evaluating on every animation frame, which was racing with the slider gesture recognizer and producing "System gesture gate timed out" / "Message send exceeds rate-limit threshold" console spam. (`Styles.swift`)

- [2026-04-22] Test verification — 15-test Swift script (`/tmp/test_latest_bid_per_player.swift`) validates `latestBidPerPlayer` logic across: empty input, single entry, single-player raises, two-player ordering, 6-player full round, pass (amount=0), identical duplicates, non-contiguous indices, regression guard against the old keep-first bug, and bidding-war cascade. All 15 tests pass.

- [2026-04-23] Bid button pulses green on human's turn — `BiddingTwoColumnLayout` in `Styles.swift` gained `@State private var bidPulse`. On `.onAppear` of the bid button (which only renders when `isHumanTurn`), a `withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true))` animates `bidPulse` between false/true, driving the button background (yellow↔green) and a green glow shadow (opacity 0→0.65). Animation stops (`bidPulse = false`) as soon as the player taps Bid. Applies to all three game modes since they all use the shared `BiddingTwoColumnLayout`.

- [2026-04-23] Fix bid history not updating when players re-bid — `latestBidPerPlayer(_:)` helper added to all three VMs. Root cause: the old dedup kept the FIRST entry per playerIndex (using `Set.insert().inserted` filter), but players can bid multiple times across bidding rounds; the old logic silently dropped every raise after the first. New helper keeps one entry per player in first-appearance order but uses the latest amount. Fixed in: `ComputerGameViewModel.swift` (3 call sites in `startBiddingPhase`), `OnlineGameViewModel.swift` (`parseGameState`), `BluetoothGameViewModel.swift` (`applyGameState`, `processBid`, `processPass`).

- [2026-04-23] How to Play accuracy fixes — `SettingsView.swift`: (1) Scoring section corrected: BID FAILED now shows negative deltas (bidder −bid, each partner −ceil(bid/2)) instead of the previous "0 pts" which was factually wrong per `ScoringEngine.swift`; added note that scores can go negative. (2) Game Modes section: removed fictional AI character names ("Card Bot, Brain Bot, The Gambler, Foxy, Shell Boss, Volt") — AI bots actually use random names from `Comic.aiNamePool` with random emoji avatars from `Comic.comicCharacters`. (3) Avatars & Themes section: corrected avatar count from "12 emoji or 6 custom" to "24 character avatars" — the actual pool is `Comic.comicCharacters` which has 24 entries; removed incorrect two-tier distinction.

- [2026-04-22] Fix LB5 — Monthly leaderboard wipe permanently destroying all stats. `resetMonthlyLeaderboard` Cloud Function (scheduled `0 0 1 * *`) now archives before deleting: copies all `player_stats` and `game_log` documents to `monthly_snapshots/{YYYY-MM}/{col}/{docId}` (with `_archivedAt` + `_archiveLabel` fields) using 400-doc batch chunks before running deletes. Archive label is computed as the prior calendar month (e.g. reset on Feb 1 → label `2026-01`; Jan 1 → wraps to `2025-12`). Deletes only run after all archive batches succeed. Empty collections are skipped. (`functions/index.js`)

- [2026-04-22] Fix LB6 — Leaderboard Firestore listener guard preventing re-subscription after silent death. `startListening()` previously had `guard statsListener == nil else { return }` which blocked re-subscription if a listener silently died. Fix: removed the guard; `startListening()` always calls `stopListening()` first then `attachFirestoreListeners()`. Added `reattachListeners()` private helper called from both snapshot listener error closures — removes old registrations, waits 3s (`Task.sleep(nanoseconds: 3_000_000_000)`), then calls `attachFirestoreListeners()` again. (`LeaderboardService.swift`)

- [2026-04-22] Fix RC-B — BT pre-sleep race: when `processAITurnIfNeeded()` post-sleep guard fires and state has advanced to a human player's turn, the watchdog was not re-armed (relying solely on `applyGameState()` having done it during the sleep). Added defensive watchdog re-arm in the bail path: if `activePhases.contains(phase) && !aiSeats.contains(currentActionPlayer)`, calls `startTurnWatchdog(seat: currentActionPlayer, capturedPhase: phase)` to ensure the human's turn is always protected. The AI re-trigger path is unchanged. (`BluetoothGameViewModel.swift`)

- [2026-04-22] Fix RC-C — Solo `resolveAiCalling()` missing `gameLoopCancelled` guard after 1s sleep. Added `guard !gameLoopCancelled else { return }` immediately after `Task.sleep(nanoseconds: 1_000_000_000)` in `resolveAiCalling()`. If the game was quit or a new round started during the sleep, the function now exits cleanly before any state mutations. Previously it continued into `resolvePartners()` + `startPlayingPhase()` (which guarded at its own entry, making the cascade benign but wasteful). (`ComputerGameViewModel.swift`)

- [2026-04-22] iPad adaptive layout — playing phase now uses the multi-column landscape layout on iPad (`.regular` horizontalSizeClass) regardless of physical orientation. Changed `let isLandscape = geo.size.width > geo.size.height` to `let isLandscape = geo.size.width > geo.size.height || hSizeClass == .regular` in `PlayingPhaseView` (`ComputerGameView.swift`), `OnlinePlayingView` (`OnlineGameView.swift`), and `BTPlayingView` (`BluetoothGameView.swift`). Added `@Environment(\.horizontalSizeClass) private var hSizeClass` to `OnlinePlayingView` and `BTPlayingView` (was already present in `PlayingPhaseView`). Session lobbies (`SessionLobbyView`, `BTHostLobbyView`) already used `hSizeClass` for 3-column grid on iPad. All 26 tests pass.

- [2026-04-22] Fix Issue #9 — Per-turn action timeout (all networked modes). Added `private var turnWatchdogTask: Task<Void, Never>?` to both `OnlineGameViewModel` and `BluetoothGameViewModel`. Added `startTurnWatchdog(seat:capturedPhase:)` and `cancelTurnWatchdog()` helpers to both VMs. Watchdog starts whenever a human player's turn begins in an active phase (.bidding, .calling, .playing); fires after 60s of inactivity; checks `currentActionPlayer == seat && phase == capturedPhase && !aiSeats.contains(seat)` before acting; on expiry adds the seat to `aiSeats`, sets message "\(name) is taking too long. AI took over.", and triggers AI. Online: watchdog also writes `gameState.aiSeats` + `gameState.message` to Firestore so all clients sync. BT: calls `broadcastGameState()` + `processAITurnIfNeeded()`. Watchdog is hooked into `parseGameState()` (Online) and `applyGameState()` (BT) so it resets automatically on every state change. Cancelled in `cleanup()` on both VMs. 47/47 tests pass. (`OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`)

- [2026-04-22] Smarter AI players — all 4 phases implemented across all 3 game modes (`ComputerGameViewModel`, `OnlineGameViewModel`, `BluetoothGameViewModel`). No cheating — all logic uses only information visible to a real player:
  - **Phase 1 — Bidding intelligence:** `aiBidAmount`/`aiComputeBid` now uses (a) position-aware partner bonus (0.25 early-position → 0.42 late-position vs. flat 0.30 before), (b) suit-clustering bonus (+4/card when 2+ cards in same suit are Queen or higher — rewards A+K, A+Q holdings), (c) shortness penalty (-8 per suit beyond 2 singleton/void suits — penalises scattered low hands).
  - **Phase 2 — Calling intelligence:** `resolveAiCalling`/`aiComputeCalling` now uses (a) tier-based trump selection (score = points + tier×15 + count×2, where tier: Ace=3 King=2 Queen=1 else=0 — avoids declaring trump in low-card suits), (b) void-feeding called cards (prefer calling high cards in void/short suits so partners can feed that suit; diversify c1 and c2 across different suits).
  - **Phase 3 — Deficit tracking in card play:** `aiPlayCard`/`aiComputeCard` now checks if offense needs >60% of remaining points (urgent mode). Urgent offense leads highest-value non-trump immediately; all modes skip trump conservation and trump in even on 0-point tricks when urgent.
  - **Phase 4 — Void memory:** Card-play lead decision now builds `knownVoids` from `completedTricks` (any player who didn't follow led suit is marked void). Lead scoring penalises suits where opponents are known void (-4 per void opponent), steering leads toward suits opponents must follow.
  - Bidder lead logic also now checks `bidSecured` before pulling trump on late tricks — if bid is already won, conserve high trump for defensive control.

- [2026-04-21] Fix 5 additional AI-stuck causes in the playing phase (second pass):
  - **Fix A (Off-by-one next player)** — Changed `trickOrder[min(pos + 1, 5)]` to `trickOrder[(pos + 1) % 6]` in the trick-in-progress path of both `OnlineGameViewModel.processPendingAction` and `BluetoothGameViewModel.processPlayCard`. The `min()` form returned `trickOrder[5]` when `pos=5` (same player) and if `firstIndex` returned nil (default 0), silently picked `trickOrder[1]` (wrong player). Modulo is always correct. (`OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`)
  - **Fix B (No guard after empty-hand retry sleep)** — The `.playing` empty-hand path slept 1s then recursed without checking if state changed during the sleep. Added `guard currentActionPlayer == seat, phase == .playing` post-sleep; on failure, re-triggers for any AI still needing to act. (`OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`)
  - **Fix C (6th-card show-state write failure, Online)** — Online's show-state `criticalWrite` for the 6th card had no return-value capture. Added `let showOk =`; on failure, applies `currentTrick`, `partner1Index`, `partner2Index`, `currentActionPlayer = -1` locally so host display is consistent during the 1s pause before resolution. (`OnlineGameViewModel.swift`)
  - **Fix D (isProcessingAI lock stuck on invalid card)** — The invalid-card guard in both `processPendingAction` (Online) and `processPlayCard` (BT) called `processAITurnIfNeeded()` without first resetting `isProcessingAI = false`. A sleeping AI task may hold the flag, causing the re-trigger to bail silently and freeze the game. Now resets flag before re-triggering, guarded by `aiSeats.contains(currentActionPlayer)`. (`OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`)

- [2026-04-21] Fix 7 issues causing AI bots to freeze during playing-hands phase across all 3 game modes:
  - **Fix 1 (Empty hand / phantom card)** — `aiComputeCard(seat:)` in `OnlineGameViewModel` and `BluetoothGameViewModel` changed return type from `String` to `String?`; returns `nil` with error log instead of `"A♠"` sentinel when hand is empty. `processAITurnIfNeeded` in both files handles `nil` with a 1s retry. In `ComputerGameViewModel.startPlayingPhase()`, added `guard !hands[playerIndex].isEmpty else { continue }` before `aiPlayCard()` call. (`OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`, `ComputerGameViewModel.swift`)
  - **Fix 2 (Concurrent AI tasks / double-play)** — Added `private var isProcessingAI = false` to both `OnlineGameViewModel` and `BluetoothGameViewModel`. `processAITurnIfNeeded()` gates entry with `guard !isProcessingAI`, sets flag to `true`, then resets to `false` before recursive re-triggers and before the switch statement so `processPlayCard`'s internal chain calls proceed normally. (`OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`)
  - **Fix 3 (Trick resolution write failure)** — `criticalWrite()` calls for trick-advance and round-complete in `OnlineGameViewModel.processPendingAction` now capture the `Bool` return. On all-retries-fail, state is applied locally on the host (`currentActionPlayer`, `currentTrick`, `trickNumber`, `wonPointsPerPlayer`, etc.) and `processAITurnIfNeeded()` is re-triggered so the game advances despite the network failure. (`OnlineGameViewModel.swift`)
  - **Fix 4 (Disconnect mid-trick race)** — BT disconnect handler (`session(_:peer:didChange:)`) no longer gates `processAITurnIfNeeded()` on `currentActionPlayer == playerIdx`. Always re-triggers unconditionally after adding the disconnected seat to `aiSeats`; `processAITurnIfNeeded` bails immediately if no AI turn is needed. (`BluetoothGameViewModel.swift`)
  - **Fix 5 (Solo: no `gameLoopCancelled` guard after sleeps)** — Added `guard !gameLoopCancelled else { return }` immediately after the AI-turn `Task.sleep(600ms)` and after the post-trick `Task.sleep(400ms/1s)` in `ComputerGameViewModel.startPlayingPhase()`. (`ComputerGameViewModel.swift`)
  - **Fix 6 (BT host AI no re-trigger after playing card)** — Resolved by Fix 2: resetting `isProcessingAI = false` before the switch allows `processPlayCard`'s internal `await processAITurnIfNeeded()` calls to proceed, maintaining the turn chain without needing an extra explicit call. (`BluetoothGameViewModel.swift`)
  - **Fix 7 (Firestore listener dying mid-game)** — `attachListener()` changed from discarding the error parameter (`_`) to handling it: on any Firestore listener error, waits 3s then calls `reattachListener()` (new private helper that removes the old listener and calls `attachListener()` again). (`OnlineGameViewModel.swift`)

- [2026-04-21] Fix RC-A — Online AI calling turn permanently lost when `refetchAndSyncHands()` fails. `processAITurnIfNeeded()` gained a `retriesRemaining: Int = 2` parameter. The bare `return` after the `allHands[seat].count == 8` guard now triggers a bounded retry: if `retriesRemaining > 0`, waits 1s (`Task.sleep(nanoseconds: 1_000_000_000)`) and recursively calls `processAITurnIfNeeded(retriesRemaining: retriesRemaining - 1)`; if `retriesRemaining == 0`, logs an error and gives up. The post-sleep state-change recovery call also threads `retriesRemaining` through so counters stay consistent across a mid-sleep seat change. No infinite loop possible: counter decrements to 0 after at most 2 retries. Verified with 27-test Swift script. (`OnlineGameViewModel.swift`)

- [2026-04-20] Bug fix #1 — Leaked `CheckedContinuation` (Solo + P&P game loop freeze). Added `private var gameLoopCancelled = false` flag and `cancelAllContinuationsIfNeeded()` to `ComputerGameViewModel`. The method sets `gameLoopCancelled = true` and resumes all 5 pending continuations (`viewCardsContinuation`, `bidContinuation`, `bidWinnerContinuation`, `cardContinuation`, `nextHandContinuation`) with dummy/sentinel values. Added `guard !gameLoopCancelled else { return }` after every blocking await in `startBiddingPhase()`, `startPlayingPhase()`, and `waitForNextHand()`, plus entry guards at the top of `startBiddingPhase()` and `startPlayingPhase()`. `deal()` calls `cancelAllContinuationsIfNeeded()` then resets `gameLoopCancelled = false`. Root view `.onDisappear` calls `cancelAllContinuationsIfNeeded()` (replaces former `cancelDevicePassIfNeeded()` call). Verified with 20-test Swift script covering: flag semantics, per-continuation unblocking, guard bail paths, normal completion, double-cancel safety, and the old-game-cancelled / new-game-clean scenario. (`ComputerGameViewModel.swift`, `ComputerGameView.swift`)

- [2026-04-20] Bug fix #3 — P&P `confirmDeviceContinuation` deadlock. Added `cancelDevicePassIfNeeded()` to `ComputerGameViewModel` — resumes any pending device-pass continuation and resets `isPassingDevice = false`. Called from `deal()` (handles new-round case where a continuation might be pending from a prior aborted pass) and from `.onDisappear` on the root `ComputerGameView` body (handles quit/navigation-away case). Previously, if the game was quit or any non-button path cleared the overlay, the `withCheckedContinuation` await would block the async game loop forever. (`ComputerGameViewModel.swift`, `ComputerGameView.swift`)

- [2026-04-20] Landscape for SplashPage — wrapped the main `VStack` inside `SplashPage` (`SplashView.swift`) in `GameAdaptiveLayout`. Portrait branch is the existing `VStack` unchanged (spade, title, subtitle, rules card, creator credit, Let's Play CTA). Landscape branch is a two-panel `HStack`: left panel (`Comic.containerBG.opacity(0.85)` background, `Comic.containerBorder` 1pt divider) shows brand identity (52pt spade, title, subtitle, creator credit); right panel shows `rulesCard` + Let's Play CTA with `.padding(.horizontal, 14)` / `.padding(.vertical, 14)`. Background layers (`Comic.bg`, `ThemedBackground()`, floating particles, radial gradient aura) remain on the `ZStack` root, unchanged.

- [2026-04-20] Landscape for GameOver phase — applied `GameAdaptiveLayout` to `OnlineGameOverView` (`OnlineGameView.swift`) and `BTGameOverView` (`BluetoothGameView.swift`). Landscape left panel (`Comic.containerBG`): trophy + "Game Over!" header + winner subtitle + `Spacer()` + `Divider` + "Quit to Menu" button pinned at bottom. Landscape right panel (`Comic.bg`): scrollable final standings `ForEach` (medal/rank, avatar circle, name, score, `Divider`). BT portrait body preserves `ScoreSaveStatusRow`; Online portrait body unchanged. Portrait bodies unchanged in both files.

- [2026-04-20] Landscape for RoundComplete phase — applied `GameAdaptiveLayout` to `RoundCompleteView` (`ComputerGameView.swift`), `OnlineRoundCompleteView` (`OnlineGameView.swift`), and `BTRoundCompleteView` (`BluetoothGameView.swift`). Landscape left panel (`Comic.containerBG`): result banner (`BID MADE!`/`SET!`) + `ScoreSaveStatusRow` (Online/BT only) + award pills row + `Spacer()` + `Divider` + action buttons (`Next Round` / `Quit to Menu`) pinned at bottom. Online/BT left panel buttons preserve full host/non-host branch (greyed row + "Waiting for host…" text for non-host). Landscape right panel (`Comic.bg`): scrollable per-player list + `PlayerScoreBarChart`. Portrait bodies unchanged in all three files.

- [2026-04-20] Playing phase landscape hand — 2-per-row grid. The right column (~26% width) was too narrow for a single-row 8-card `HStack`. Added `yourHandBoxLandscape(rightW:)` / `onlineYourHandBoxLandscape(rightW:)` / `btYourHandBoxLandscape(rightW:)` to each playing view; these use `LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())])` with `cardW = (rightW - 16 - 8) / 2`. Each landscape layout now calls the grid version; portrait single-row `HStack` hand boxes are unchanged.

- [2026-04-19] Landscape for CallingCards/Calling phase — applied `GameAdaptiveLayout` to `CallingCardsView` (`ComputerGameView.swift`), `OnlineCallingView` (`OnlineGameView.swift`), and `BTCallingView` (`BluetoothGameView.swift`). In Solo: landscape left panel (`Comic.containerBG`) = mini header + trump 4-button grid + Confirm button (sticky at bottom via `Spacer()`); landscape right panel (`Comic.bg`) = `ScrollView` with callCardRow ×2 + error label + `HandCardView` hand reference. In Online/BT: the `isMyCall = true` branch wraps identically; the `!isMyCall` waiting branch (blinking text + hand reference) stays portrait-only. Confirm action: Solo = `game.humanConfirmCalling()`, Online = `Task { await game.confirmCalling() }`, BT = `Task { await game.callTrumpAndCards() }`.

- [2026-04-19] Landscape for ViewingCards/LookingAtCards — added `GameAdaptiveLayout<Portrait, Landscape>` to `Styles.swift`: full-screen orientation switcher for gameplay phases (no branding panel, no split fraction — just portrait vs landscape full-screen). Applied to `ViewingCardsView` (`ComputerGameView.swift`), `OnlineLookingAtCardsView` (`OnlineGameView.swift`), and `BTLookingAtCardsView` (`BluetoothGameView.swift`). Landscape layout: left panel (`maxWidth: .infinity`, `Comic.containerBG`) shows round number + dealer + hand-points pill; 1pt `Comic.containerBorder` divider; right panel (`maxWidth: .infinity`, `Comic.bg`) shows full 8-card `HandCardView` row in GeometryReader + CTA button. Portrait body unchanged in all three files.

- [2026-04-18] iPad + landscape layout — replaced `LandscapeModeSelectionLayout` (single-purpose) with three reusable layout primitives in `Styles.swift`: `LandscapeSplitLayout<Left, Right>` (two-column split with configurable left fraction + divider), `AdaptiveLayout<Portrait, LandscapeLeft, LandscapeRight>` (GeometryReader wrapper that picks portrait or landscape split; uses 28% left on wide screens >700pt, 34% on narrow), `BrandingPanel` (self-sizing left-column panel: spade icon, title, subtitle, optional trophy/settings buttons; scales all sizes based on available width). `ModeSelectionView` now uses `AdaptiveLayout`: portrait renders unchanged `portraitBody` (full ZStack with existing top bar + portrait card list); landscape left renders `BrandingPanel`, landscape right renders 2×2 `LazyVGrid` of mode cards. All `.sheet`, `.fullScreenCover`, `.onChange` modifiers moved to `AdaptiveLayout` call. Verified on iPhone 15 Pro Max (34/66 split) and iPad Pro 12.9" (28/72 split) — portrait unchanged. (`Styles.swift`, `ModeSelectionView.swift`)

- [2026-04-17] Remove all themes except Casino Night — deleted SunsetSocialTheme, ComicBookTheme, MinimalDarkTheme, MinimalLightTheme from `Themes.swift` (kept only ClassicGreenTheme); emptied `PremiumThemes.swift` (MidnightNoir, RoyalCrimson, DiamondClub, BaroqueGold, NeonUnderground) and `CasinoRoyaleTheme.swift`. `ThemeManager.availableThemes` now contains only `ClassicGreenTheme()`, default and fallback both point to it. Removed APPEARANCE (theme picker) and DISPLAY MODE sections from `SettingsView` — both were useless with a single fixed-dark theme. Updated How To Play "Avatars & Themes" text to mention Casino Night only. (`Themes.swift`, `PremiumThemes.swift`, `CasinoRoyaleTheme.swift`, `ThemeManager.swift`, `SettingsView.swift`)
- [2026-04-17] Bug fix #2 — `waitForNextHand()` branched on `humanPlayerIndices.count > 1` at runtime; if a solo game ever had multiple entries (init bug), it would auto-advance after 5s instead of waiting for the "Next Hand" tap — `humanReadyForNextHand()` would never fire. Added `var isPassAndPlay: Bool = false` to `ComputerGameViewModel`; the P&P init (`init(humanSeats:...)`) sets it to `humanSeats.count > 1`. Replaced both runtime `humanPlayerIndices.count > 1` checks (sleep duration + next-hand branch) with `isPassAndPlay`. Also removed stale debug `print` statements from `waitForNextHand`. (`ComputerGameViewModel.swift`)
- [2026-04-17] Bug fix #7 — BT `isMyTurn` had `&& phase == .playing`, making it always `false` during `.bidding` and `.calling`; BT views that gate bid/call controls on `game.isMyTurn` never rendered those controls for the current action player. Removed the phase restriction — `isMyTurn` now matches Online: `myPlayerIndex == currentActionPlayer`. (`BluetoothGameViewModel.swift:131`)
- [2026-04-18] Bug fix #8 — `try?` swallowing write failures (Online + BT). Online: added `criticalWrite(_:)` private helper to `OnlineGameViewModel` — retries up to 3× (2s then 4s backoff), sets `errorMessage` after all retries fail. Replaced all 13 critical `try? await ref.updateData(...)` calls (client action writes: `placeBid`, `pass`, `confirmCalling`, `playCard`; host state-advancing writes: `startBidding`, `concludeBidding`, bid/pass continuation, `callCards`, all `playCard` resolve paths, `startNextRound`). Also removed now-unused `ref` locals and dropped the `ref:` parameter from `concludeBidding`. BT: replaced `try? session.send(...)` in `sendToAll` and `send` with `do/catch` + `aiLog.error` — MC `.reliable` errors mean the session is broken; the existing `didChange/notConnected` delegate handles recovery, so logging is the right fix rather than retry. (`OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`)
- [2026-04-18] Bug fix #6 — BT `sendToHost` silent drop. When `playerIndexToPeer[0]` was nil (host peer not yet mapped, session teardown, or reconnect race), all client actions were silently dropped — no retry, no error shown. Fix: `sendToHost` now queues the action in `pendingHostAction` and starts an async retry task (up to 3 attempts, 500ms apart). Only one retry chain runs at a time; a newer action replaces the queued one. After 3 failed retries, sets `errorMessage` and logs. `isReconnecting: Bool` (observable) is set during the retry window; `BluetoothGameView` shows a yellow "Reconnecting to host…" capsule banner at the top while it's `true`. `cleanup()` cancels the retry task. (`BluetoothGameViewModel.swift`, `BluetoothGameView.swift`)
- [2026-04-17] Bug fix #5 — Online: stale `allHands` during AI calling. `aiComputeCalling(seat:)` could read a previous round's hand data if the `startGame()` Firestore write failed silently (`try?`) and a later snapshot re-synced `allHands` from stale Firestore state. Fix: validate `allHands[seat].count == 8` before calling `aiComputeCalling`; if stale, call new `refetchAndSyncHands()` (one-shot `getDocument()` to re-sync all 6 hands). If count is still wrong after the fetch, abort with an error log instead of corrupting partner resolution. Added `OSLog` import and `ogVMLog` logger to `OnlineGameViewModel.swift`. (`OnlineGameViewModel.swift`)
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

## Setup Screen Architecture (Pre-Game Flows)

Every mode goes through `NamePromptSheet` first (avatar + name entry), then branches:

### NamePromptSheet (shared, all 4 modes)
- Presented as `.sheet(.large)` from `ModeSelectionView` on any mode tap
- UI: large `AvatarPickerCard` preview · name `TextField` (profanity-validated) · horizontal avatar picker (`Comic.comicCharacters` emoji cards) · "Start Game" button
- On confirm → dismisses → `onDismiss` sets `showingSolo` / `showingOnline` / `showingBluetooth` / `showingJoinGame`
- No landscape handling

### Solo (vs AI)
`NamePromptSheet` → `.fullScreenCover` → `ComputerGameView` directly (no lobby)

### Multiplayer / Online — Host side
`NamePromptSheet` → `OnlineEntryView` → `OnlineSessionView` → `CreateOrJoinView` (host/join picker) → Firestore session created → `SessionLobbyView`

**`CreateOrJoinView`:** Player identity display (avatar circle + name) · "Host a Game" (gold) · "Join a Game" (dark, opens `JoinByCodeView` sheet) · No landscape handling

**`SessionLobbyView`:** "Game Lobby" title · room code display (large monospaced gold chars) · Share / Copy / QR buttons · `LazyVGrid` player slots (2-col portrait, 3-col on `.regular` hSizeClass) · "Start Game" button (host only) · "Waiting for host…" state for non-hosts · Partial landscape: hSizeClass changes grid columns only, no full layout branch

### Join a Game (direct shortcut — online join side)
`NamePromptSheet` → `OnlineEntryView(autoShowJoin: true)` → `JoinByCodeView` sheet (skips `CreateOrJoinView`)

**`JoinByCodeView`:** "Enter Room Code" title · 6-box OTP-style input (invisible `TextField` + visual overlay) · "Join Game" button · "Scan QR Code" → `QRScannerView` sheet · No landscape handling

### Local / Bluetooth — Host side
`NamePromptSheet` → `BTEntryView` → `BluetoothSessionView` → `BTModePickerView`

**`BTModePickerView`:** "Local / Bluetooth" title · player identity display · "Host a Game" (gold, starts MCNearbyServiceAdvertiser) · "Join a Game" (dark, starts MCNearbyServiceBrowser) · No landscape handling

**`BTHostLobbyView`:** "Hosting Game" + LiveDot · player count (X/6) · optional TV Dashboard QR + URL · `LazyVGrid` 6× `BTPlayerSlotCard` (2-col compact, 3-col regular) · "Start Game" button · Partial landscape: hSizeClass changes grid columns only

**`BTClientLobbyView`:** "Find a Game" + LiveDot · browsing: `ProgressView` + found sessions list (`BTFoundSessionRow` with "Join" button) · connected: "Connected!" + "Waiting for host…" + player list · No landscape handling

### First-Launch Onboarding (`SplashView`) — one-time only
3 pages: `SplashPage` (rules card, "Let's Play") → `PlayerSetupPage` (6× name TextFields in VStack, per-field profanity validation) → `DeckAndDealPage` (circular 6-seat layout via `cos/sin` GeometryReader, `DeckPhase` enum: `.ready` → `.shuffling` → `.shuffled` → `.dealing` → `.dealt`)

---

## Gameplay UI Architecture

### Phase Enums

**Solo/P&P** (`ComputerGamePhase` in `ComputerGameViewModel.swift:43`):
```
viewingCards → bidding/humanBidding → aiCalling/callingCards → playing/humanPlaying → roundComplete
```
- `bidding` = AI's turn to bid; `humanBidding` = human's turn
- `playing` = AI's turn; `humanPlaying` = human's turn

**Online + BT** (same `OnlineGamePhase` in `OnlineGameViewModel.swift:10`):
```
dealing → lookingAtCards → bidding → calling → playing → roundComplete → gameOver
```
BT uses identical enum (`var phase: OnlineGamePhase = .dealing` in `BluetoothGameViewModel`).

### Root View Structure (all 3 game files)
All three root views (`ComputerGameView`, `OnlineGameView`, `BluetoothGameView`) use the same pattern:
```
ZStack {
    background
    switch game.phase { ... }         // one full-screen view per phase
    BidWinnerBanner (zIndex 100)      // floats above all phases
}
.overlay { RoundResultBanner }        // bid-made/set flash
.overlay { PassDeviceView }           // P&P only
.overlay(topTrailing) { X quit btn }
```

### Per-Phase UI Regions

| Phase | Outermost | Key regions |
|---|---|---|
| viewingCards / lookingAtCards | `VStack` | Round/dealer header · `HandCardView` ×8 row (GeometryReader spacing) · hand-points pill · "Ready to Bid" CTA · **No landscape** |
| bidding / humanBidding | `VStack` | "Bidding/Round N" header · `BiddingTwoColumnLayout` (handles landscape internally) |
| aiCalling | centered `VStack` | ProgressView + "X is calling trump…" — no interaction |
| callingCards / calling | `ScrollView` + sticky bottom | Trump 4-button grid · 2× callCard rows (rank `Menu` + suit buttons) · `HandCardView` hand reference · "Confirm" sticky button · **No landscape** · Non-bidder (Online/BT only): blinking wait text + hand reference |
| playing / humanPlaying | `GeometryReader` | Portrait + landscape branch — see below |
| roundComplete | `ScrollView` | "BID MADE!" / "SET!" · `AwardPill` ×3 · per-player list (`AvatarRoleCard` + ±score) · `PlayerScoreBarChart` · Next Round / Quit |
| gameOver (Online/BT only) | `ScrollView` | Final standings + `ScoreSaveStatusRow` + Quit |

### Playing Phase — Portrait (`ScrollView > VStack`)
1. `AvatarRoleCard` ×6 strip — GeometryReader `chipW = (width-32)/6`, green border + `TurnArrow` on active player
2. Waiting banner (when not human's turn)
3. `GameInfoPillsRow` — trump badge · called cards · offense score / bid target
4. Current trick box — `PlayingCardView` per played card, `.currentHandStage()` styling
5. `LastHandView` — previous completed trick strip
6. Message text + trick history clock button
7. Your hand — `HandCardView` with `.shimmer()` on valid cards, `BouncyButton`

### Playing Phase — Landscape (`HStack(spacing: 0)`)
- **Left 22%:** `LandscapePlayerRow` ×6 in `ScrollView` · `Comic.containerBG.opacity(0.4)` background
- **Center ~52%:** `GameInfoPillsRow` · waiting/`LiveDot` indicator · current trick box · message · trick history button
- **Right 26%:** your hand column (`HandCardView` with shimmer)

**Landscape detection** (playing phase only, all 3 files):
```swift
let isLandscape = geo.size.width > geo.size.height   // in GeometryReader
```
**All other phases have no landscape branch** — they render portrait-only regardless of orientation.

### BT vs Online Playing Differences
| Aspect | Online | Bluetooth |
|---|---|---|
| Avatar strip spacing | GeometryReader `chipW = (width-32)/6` | `HStack(spacing: 5)` — fixed, not width-constrained |
| Remove player | Long-press avatar → `removePlayerMidGame` | Not present |
| Reconnect banner | Not present | Yellow "Reconnecting to host…" capsule at `.overlay(alignment: .top)` |
| Local banner variants | `OnlineRoundResultBanner`, `OnlinePartnerRevealBanner`, `OnlineTrickHistoryView`, `OnlineAwardPill` | `BTRoundResultBanner`, `BTPartnerRevealBanner`, `BTTrickHistoryView`, `BTAwardPill` |

### Styles.swift Components Used in All 3 Game Files
`HandCardView` · `PlayingCardView` · `AvatarRoleCard` · `GameInfoPillsRow` · `LandscapePlayerRow` · `BiddingTwoColumnLayout` · `TurnArrow` · `LastHandView` · `BidWinnerBanner` · `.shimmer(isActive:)` · `.currentHandStage()` · `ScoreSaveStatusRow` · `PlayerScoreBarChart` · `CardDealAnimationView` · `LiveDot` · `SectionHeader` · `ComicButtonStyle` · `BouncyButton` · `.glassmorphic()` · `.comicContainer()`

Solo-only (from Styles.swift): `AwardPill` · `PartnerRevealBanner` · `TrickHistoryView` · `PassDeviceView`
Online/BT define their own local equivalents for those four.

---

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
