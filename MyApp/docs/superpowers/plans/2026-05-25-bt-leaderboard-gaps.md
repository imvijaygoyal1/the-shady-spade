# BT Leaderboard Robustness — 14-Gap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 14 root-cause gaps that cause BT game mode leaderboard records to be silently lost or corrupted, covering both the iOS client and Cloud Function validation layer.

**Architecture:** Three-layer fix — (1) MC reliability: drain `pendingResyncPeers` before farewell notification and extend cleanup delay; (2) State completeness: serialize `completedRounds` in game-state broadcast so reconnecting non-hosts always have full history; (3) Resilience: pre-enqueue records to disk before HTTP attempt and improve stale-watchdog host-exit detection.

**Tech Stack:** Swift/SwiftUI, MultipeerConnectivity, Firebase/Firestore, LeaderboardService offline queue.

---

## File Map

| File | Changes |
|---|---|
| `BluetoothGameViewModel.swift` | `notifyHostEndedGame()`, `buildGameStateDict()`, `applyGameState()`, `becomeNewHost()`, `startMigrationTimeout()`, `cleanup()`, new `consecutiveStaleRequests` property, new `migrationFailureCount` property |
| `BluetoothGameView.swift` | Three 400ms→2000ms timeouts, `saveOnQuit()` guard |
| `LeaderboardService.swift` | `enqueue()` replace-on-duplicate, new `preEnqueue()` public method |
| `AUDIT_REPORT.md` | Append BT-GAP-01 through BT-GAP-14 |
| `CLAUDE.md` | Document all changes |

---

### Task 1: Update AUDIT_REPORT.md

**Files:**
- Modify: `AUDIT_REPORT.md` (append at end)

- [ ] **Step 1: Append BT-GAP section**

Add after the last `---` line:

```markdown
---

## BT Leaderboard Gap Audit — 2026-05-25

14 gaps identified via end-to-end analysis of the BT leaderboard save flow
(MultipeerConnectivity → BluetoothGameViewModel → LeaderboardService →
Cloud Function). Root cause: most failures trace to pendingResyncPeers not
being drained before the host farewell notification, causing non-host clients
to miss both the .gameOver state and the hostEndedGame message.

### BT-GAP-01 — pendingResyncPeers not drained before farewell
- **File:** `BluetoothGameViewModel.swift` — `notifyHostEndedGame()` (line ~596)
- **Issue:** `notifyHostEndedGame()` calls bare `sendToAll(["type": "hostEndedGame"])`. If a peer failed the `.gameOver` broadcast and is in `pendingResyncPeers`, it never receives either the game state OR the farewell. It sees a raw MC disconnect on slot 0, triggers host migration, and never saves.
- **Status:** ✅ Fixed (2026-05-25) — drain `pendingResyncPeers` with current game state before sending hostEndedGame.

### BT-GAP-02 — Host cleanup delay insufficient for MC delivery
- **File:** `BluetoothGameView.swift` (3 locations, line ~49, ~64, ~97)
- **Issue:** Host waits only 400ms before `cleanup()` → `session.disconnect()`. MC `.reliable` delivery can take >400ms on congested Wi-Fi / BT. Peers that need the farewell message or a resync miss it.
- **Status:** ✅ Fixed (2026-05-25) — delay increased to 2000ms in all three quit paths.

### BT-GAP-03 — Save intent not persisted until async Task fires
- **File:** `LeaderboardService.swift` — `enqueue()`, new `preEnqueue()`; `BluetoothGameViewModel.swift` — `applyGameState()`
- **Issue:** `enqueue()` is called inside the async `recordGame()`, which is called from a SwiftUI `.task(id: game.phase)`. The tiny window between `applyGameState()` setting `.gameOver` and the Task body executing is enough to lose the record if the OS suspends the process.
- **Status:** ✅ Fixed (2026-05-25) — `preEnqueue()` called synchronously from `applyGameState()` at `.gameOver`; `enqueue()` now replaces duplicates so the correct id is used for removal.

### BT-GAP-04 — 400ms delay in `notifyHostEndedGame` call sites
- **File:** `BluetoothGameView.swift`
- **Issue:** Same as BT-GAP-02 — three identical call sites.
- **Status:** ✅ Fixed (2026-05-25) — consolidated with BT-GAP-02 fix.

### BT-GAP-05 — Stale-state watchdog doesn't infer host exit
- **File:** `BluetoothGameViewModel.swift` — stale-state watchdog (line ~991)
- **Issue:** If the host process is killed without sending `hostEndedGame`, non-host clients wait 15s, send `requestFullState`, get no response, then wait another 15s, forever. They never save and never navigate away — they're stuck.
- **Status:** ✅ Fixed (2026-05-25) — `consecutiveStaleRequests` counter; after 2 consecutive misses (30s total) → `hostEndedGame = true`.

### BT-GAP-06 — `completedRounds` absent from `buildGameStateDict()`
- **File:** `BluetoothGameViewModel.swift` — `buildGameStateDict()` (line ~870)
- **Issue:** Game state broadcasts don't carry `completedRounds`. Reconnecting non-host clients start with an empty array. Their first-write-wins Firestore submission has `roundCount: 1` (synthetic), corrupting the canonical record that the host cannot correct (Firestore dedup suppresses the host's later write).
- **Status:** ✅ Fixed (2026-05-25) — serialize `completedRounds` to JSON in `buildGameStateDict()`; merge on reception in `applyGameState()`.

### BT-GAP-07 — `saveOnQuit()` guard blocks non-host mid-game saves
- **File:** `BluetoothGameView.swift` — `saveOnQuit()` (line ~234)
- **Issue:** Guard `if !game.isHost && game.phase != .gameOver { return }` prevents a non-host from saving accumulated `completedRounds` when they quit mid-game (e.g. after 3 of 5 rounds). Valid historical data is discarded.
- **Status:** ✅ Fixed (2026-05-25) — guard changed to `if !game.isHost && game.phase != .gameOver && game.completedRounds.isEmpty { return }`.

### BT-GAP-08 — Partner index -1 normalized to 0 in completedRounds
- **File:** `BluetoothGameViewModel.swift` — `applyGameState()` (line ~1114)
- **Issue:** `partner1Index >= 0 ? partner1Index : 0` silently maps slot -1 to Player 0, injecting Player 0 as a partner in a round where partners were not yet resolved. This inflates Player 0's stats.
- **Status:** ✅ Fixed (2026-05-25) — guard `partner1Index >= 0 && partner2Index >= 0` before append; host-synced `completedRounds` (GAP-06 fix) provides the correction for reconnecting clients.

### BT-GAP-09 — Reconnecting clients get stale `completedRounds`
- **File:** `BluetoothGameViewModel.swift` — `applyGameState()`, `buildGameStateDict()`
- **Issue:** Same root cause as BT-GAP-06; the merge path in `applyGameState()` was also missing.
- **Status:** ✅ Fixed (2026-05-25) — consolidated with BT-GAP-06 fix.

### BT-GAP-10 — `consecutiveStaleRequests` not reset on state receipt
- **File:** `BluetoothGameViewModel.swift` — `applyGameState()` (line ~902)
- **Issue:** Without resetting the counter, a peer that recovers after one missed tick still triggers the host-exit path on the second tick.
- **Status:** ✅ Fixed (2026-05-25) — reset `consecutiveStaleRequests = 0` at the top of `applyGameState()` alongside `lastStateReceivedAt`.

### BT-GAP-11 — `becomeNewHost()` doesn't reset `hasInitializedCalling`
- **File:** `BluetoothGameViewModel.swift` — `becomeNewHost()` (line ~511)
- **Issue:** If a migration happens during the calling phase, the newly elected host has `hasInitializedCalling = true` from its non-host perspective. When `applyGameState()` fires, the smart-calling-defaults block is skipped and the host calls with wrong defaults.
- **Status:** ✅ Fixed (2026-05-25) — `hasInitializedCalling = false` added at top of `becomeNewHost()`.

### BT-GAP-12 — Host migration never times out permanently
- **File:** `BluetoothGameViewModel.swift` — `startMigrationTimeout()` (line ~529)
- **Issue:** `startMigrationTimeout` re-elects and restarts itself indefinitely when no viable host exists. If all real players disconnect, the game is stuck in `isMigrating = true` and never saves.
- **Status:** ✅ Fixed (2026-05-25) — `migrationFailureCount` property; after 3 consecutive failures → `hostEndedGame = true`; reset in `cleanup()`.

### BT-GAP-13 — `migrationFailureCount` not reset in `cleanup()`
- **File:** `BluetoothGameViewModel.swift` — `cleanup()` (line ~556)
- **Issue:** Without a reset, the count bleeds into the next game session and causes premature `hostEndedGame` after only 1 migration attempt.
- **Status:** ✅ Fixed (2026-05-25) — consolidated with BT-GAP-12 fix; `migrationFailureCount = 0` added to `cleanup()`.

### BT-GAP-14 — `enqueue()` keeps old record on duplicate (wrong id for removeFromQueue)
- **File:** `LeaderboardService.swift` — `enqueue()` (line ~417)
- **Issue:** When `preEnqueue()` stores a record and then `recordGame()` calls `enqueue()` with a new record for the same game, the duplicate guard keeps the OLD record's UUID but `removeFromQueue(id: pending.id)` in `recordGame()` uses the NEW UUID. The pre-enqueued record is never removed and gets sent again on next flush — double-write for games without sessionCode.
- **Status:** ✅ Fixed (2026-05-25) — `enqueue()` now replaces the existing record rather than skipping the new one.
```

- [ ] **Step 2: Commit**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp
git add AUDIT_REPORT.md
git commit -m "docs: append 14 BT leaderboard gap findings to AUDIT_REPORT.md"
```

---

### Task 2: Fix LeaderboardService.swift

**Files:**
- Modify: `MyApp/MyApp/LeaderboardService.swift` (~line 417 enqueue, new preEnqueue)

- [ ] **Step 1: Change `enqueue()` to replace on duplicate**

Find:
```swift
private func enqueue(_ record: PendingGameRecord) {
    var records = loadPendingRecords()
    // #10: skip exact duplicates (e.g. onChange retry race before gameHistorySaved is set)
    guard !records.contains(where: { $0.deduplicationKey == record.deduplicationKey }) else {
        lbLog.warning("enqueue: duplicate skipped id=\(record.id)")
        // LOW-02: treat a duplicate as already-queued so the UI doesn't stay on .saving
        scoreSaveStatus = .saved
        return
    }
    records.append(record)
    // #9: cap queue to prevent unbounded UserDefaults growth; evict oldest
    if records.count > 100 { records = Array(records.suffix(100)) }
    savePendingRecords(records)
}
```

Replace with:
```swift
private func enqueue(_ record: PendingGameRecord) {
    var records = loadPendingRecords()
    if let existingIdx = records.firstIndex(where: { $0.deduplicationKey == record.deduplicationKey }) {
        // Replace with newer record so the caller's id matches what is stored;
        // this is required for removeFromQueue(id:) to work correctly when a
        // preEnqueue() call stored an earlier version of the same record.
        lbLog.info("enqueue: replacing existing record id=\(records[existingIdx].id) → \(record.id)")
        records[existingIdx] = record
        savePendingRecords(records)
        return
    }
    records.append(record)
    if records.count > 100 { records = Array(records.suffix(100)) }
    savePendingRecords(records)
}
```

- [ ] **Step 2: Add `preEnqueue()` public method**

Insert after the `enqueue()` method:
```swift
/// Persists a game record to the offline queue WITHOUT triggering an HTTP send.
/// Call this from synchronous game-state handlers (e.g. applyGameState at .gameOver)
/// so the record survives a process kill before the normal async recordGame() path runs.
/// When recordGame() is subsequently called, enqueue() replaces this record (same
/// deduplicationKey) so removeFromQueue(id:) uses the correct UUID.
func preEnqueue(
    sessionCode: String,
    gameMode: String,
    playerNames: [String],
    finalScores: [Int],
    winnerIndex: Int,
    aiSeats: [Int] = [],
    rounds: [HistoryRound]
) {
    guard playerNames.count == 6, finalScores.count == 6 else { return }
    guard rounds.allSatisfy({ $0.runningScores.count == 6 }), let lastRound = rounds.last else { return }
    let validAISeats = aiSeats.filter { (0..<6).contains($0) }
    let totalDefensePts = rounds.reduce(0) { $0 + $1.defensePointsCaught }
    let sanitizedNames = playerNames.enumerated().map { (i, name) in
        ProfanityFilter.isProfane(name) ? "Guest \(i + 1)" : name
    }
    let pending = PendingGameRecord(
        sessionCode: sessionCode.isEmpty ? nil : sessionCode,
        gameMode: gameMode,
        playerNames: sanitizedNames,
        finalScores: finalScores.map { Int($0) },
        winnerIndex: Int(winnerIndex),
        aiSeats: validAISeats.map { Int($0) },
        bid: Int(lastRound.bidAmount),
        bidMade: !lastRound.isSet,
        bidderIndex: Int(lastRound.bidderIndex),
        partner1Index: Int(lastRound.partner1Index),
        partner2Index: Int(lastRound.partner2Index),
        defensePointsCaught: Int(totalDefensePts),
        roundCount: Int(rounds.count)
    )
    enqueue(pending)
    lbLog.info("preEnqueue: persisted to disk — \(gameMode) sessionCode=\(sessionCode.isEmpty ? "none" : sessionCode) rounds=\(rounds.count)")
}
```

- [ ] **Step 3: Build to verify no compile errors**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp \
  -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' \
  -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```
Expected: `Build succeeded`

- [ ] **Step 4: Commit**

```bash
git add MyApp/LeaderboardService.swift
git commit -m "fix(BT-GAP-03/14): preEnqueue for process-kill resilience; enqueue replaces on duplicate"
```

---

### Task 3: Fix BluetoothGameViewModel.swift — Properties + notifyHostEndedGame + buildGameStateDict

**Files:**
- Modify: `MyApp/MyApp/BluetoothGameViewModel.swift`

- [ ] **Step 1: Add new properties**

After `private var staleStateCheckTask: Task<Void, Never>?` (line ~161), add:
```swift
private var consecutiveStaleRequests: Int = 0
private var migrationFailureCount: Int = 0
```

- [ ] **Step 2: Fix `notifyHostEndedGame()`**

Find:
```swift
func notifyHostEndedGame() {
    sendToAll(["type": "hostEndedGame"])
}
```

Replace with:
```swift
func notifyHostEndedGame() {
    // Drain peers that missed the .gameOver broadcast before sending farewell.
    // Without this, a peer in pendingResyncPeers sees a raw MC disconnect on
    // slot 0, triggers host migration, and never saves its leaderboard record.
    if !pendingResyncPeers.isEmpty {
        let gs = buildGameStateDict()
        let connected = Set(session?.connectedPeers ?? [])
        let resyncMsg: [String: Any] = ["type": "gameState", "state": gs]
        for peer in pendingResyncPeers where connected.contains(peer) {
            send(resyncMsg, to: peer)
        }
        pendingResyncPeers.removeAll()
    }
    sendToAll(["type": "hostEndedGame"])
}
```

- [ ] **Step 3: Add `completedRounds` to `buildGameStateDict()`**

Find in `buildGameStateDict()`:
```swift
            "aiSeats": aiSeats
        ]
    }
```

Replace with:
```swift
            "aiSeats": aiSeats,
            "completedRounds": completedRounds.map { r -> [String: Any] in
                [
                    "roundNumber":          r.roundNumber,
                    "dealerIndex":          r.dealerIndex,
                    "bidderIndex":          r.bidderIndex,
                    "bidAmount":            r.bidAmount,
                    "trumpSuit":            r.trumpSuitRaw,
                    "callCard1":            r.callCard1,
                    "callCard2":            r.callCard2,
                    "partner1Index":        r.partner1Index,
                    "partner2Index":        r.partner2Index,
                    "offensePointsCaught":  r.offensePointsCaught,
                    "defensePointsCaught":  r.defensePointsCaught,
                    "runningScores":        r.runningScores
                ]
            }
        ]
    }
```

- [ ] **Step 4: Build to verify**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp \
  -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' \
  -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 5: Commit**

```bash
git add MyApp/MyApp/BluetoothGameViewModel.swift
git commit -m "fix(BT-GAP-01/02/06): drain pendingResyncPeers in farewell; add completedRounds to gameStateDict"
```

---

### Task 4: Fix BluetoothGameViewModel.swift — applyGameState

**Files:**
- Modify: `MyApp/MyApp/BluetoothGameViewModel.swift` — `applyGameState()`

- [ ] **Step 1: Reset `consecutiveStaleRequests` on state receipt**

Find (line ~902):
```swift
    func applyGameState(_ gs: [String: Any]) {
        lastStateReceivedAt = Date()
```

Replace with:
```swift
    func applyGameState(_ gs: [String: Any]) {
        lastStateReceivedAt = Date()
        consecutiveStaleRequests = 0
```

- [ ] **Step 2: Update stale-state watchdog to detect host exit**

Find:
```swift
                if !isHost && staleStateCheckTask == nil {
                    staleStateCheckTask = Task { @MainActor [weak self] in
                        while !Task.isCancelled {
                            do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
                            guard let self, !Task.isCancelled else { return }
                            if Date().timeIntervalSince(self.lastStateReceivedAt) > 15 {
                                self.sendToHost(["type": "requestFullState"])
                            }
                        }
                    }
                }
```

Replace with:
```swift
                if !isHost && staleStateCheckTask == nil {
                    staleStateCheckTask = Task { @MainActor [weak self] in
                        while !Task.isCancelled {
                            do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
                            guard let self, !Task.isCancelled else { return }
                            if Date().timeIntervalSince(self.lastStateReceivedAt) > 15 {
                                self.consecutiveStaleRequests += 1
                                if self.consecutiveStaleRequests >= 2 {
                                    // Two consecutive missed responses (30s) — host has
                                    // likely exited without sending hostEndedGame.
                                    aiLog.warning("[staleWatchdog] 2 consecutive misses — treating as host exit")
                                    self.hostEndedGame = true
                                    return
                                }
                                self.sendToHost(["type": "requestFullState"])
                            }
                        }
                    }
                }
```

- [ ] **Step 3: Merge completedRounds from host state**

Find the block that starts with:
```swift
        // LB4: Accumulate a HistoryRound whenever a round ends so the leaderboard
        // receives stats for every round, not just the last one.
        if (newPhase == .roundComplete || newPhase == .gameOver) {
```

Insert the completedRounds sync block BEFORE that block:
```swift
        // BT-GAP-06/09: Merge completedRounds synced from host — allows reconnecting
        // non-host clients to recover full round history without re-playing rounds.
        if let rawRounds = gs["completedRounds"] as? [[String: Any]] {
            for rd in rawRounds {
                let rn = (rd["roundNumber"] as? Int) ?? -1
                guard rn >= 0 else { continue }
                guard !completedRounds.contains(where: { $0.roundNumber == rn }) else { continue }
                let rsRaw = rd["runningScores"] as? [Int] ?? Array(repeating: 0, count: 6)
                let runScores = rsRaw.count == 6 ? rsRaw : Array(repeating: 0, count: 6)
                let p1 = (rd["partner1Index"] as? Int) ?? -1
                let p2 = (rd["partner2Index"] as? Int) ?? -1
                guard p1 >= 0, p2 >= 0 else { continue }
                completedRounds.append(HistoryRound(
                    roundNumber: rn,
                    dealerIndex: (rd["dealerIndex"] as? Int) ?? 0,
                    bidderIndex: (rd["bidderIndex"] as? Int) ?? 0,
                    bidAmount:   (rd["bidAmount"] as? Int) ?? 130,
                    trumpSuit:   TrumpSuit(rawValue: rd["trumpSuit"] as? String ?? "") ?? .spades,
                    callCard1:   rd["callCard1"] as? String ?? "",
                    callCard2:   rd["callCard2"] as? String ?? "",
                    partner1Index:       p1,
                    partner2Index:       p2,
                    offensePointsCaught: (rd["offensePointsCaught"] as? Int) ?? 0,
                    defensePointsCaught: (rd["defensePointsCaught"] as? Int) ?? 0,
                    runningScores:       runScores
                ))
            }
        }

```

- [ ] **Step 4: Fix partner index guard in local append**

Find:
```swift
            if !completedRounds.contains(where: { $0.roundNumber == roundNumber }) {
                completedRounds.append(HistoryRound(
                    roundNumber: roundNumber,
                    dealerIndex: dealerIndex,
                    bidderIndex: highBidderIndex >= 0 ? highBidderIndex : 0,
                    bidAmount: highBid,
                    trumpSuit: trumpSuit,
                    callCard1: calledCard1,
                    callCard2: calledCard2,
                    partner1Index: partner1Index >= 0 ? partner1Index : 0,
                    partner2Index: partner2Index >= 0 ? partner2Index : 0,
                    offensePointsCaught: offensePoints,
                    defensePointsCaught: defensePoints,
                    runningScores: runningScores
                ))
```

Replace with:
```swift
            // Require valid partner indices: -1 means partners not yet resolved.
            // The host-synced completedRounds (above) provides the correct data
            // for reconnecting clients, so skipping here is safe.
            if !completedRounds.contains(where: { $0.roundNumber == roundNumber })
                && partner1Index >= 0 && partner2Index >= 0 {
                completedRounds.append(HistoryRound(
                    roundNumber: roundNumber,
                    dealerIndex: dealerIndex,
                    bidderIndex: highBidderIndex >= 0 ? highBidderIndex : 0,
                    bidAmount: highBid,
                    trumpSuit: trumpSuit,
                    callCard1: calledCard1,
                    callCard2: calledCard2,
                    partner1Index: partner1Index,
                    partner2Index: partner2Index,
                    offensePointsCaught: offensePoints,
                    defensePointsCaught: defensePoints,
                    runningScores: runningScores
                ))
```

- [ ] **Step 5: Add preEnqueue call at .gameOver**

After the completedRounds append block (after the closing `}` of the `if (newPhase == .roundComplete || newPhase == .gameOver)` block), add:
```swift
        // BT-GAP-03: Pre-persist the record to disk at .gameOver so it survives
        // any process suspension before the SwiftUI .task(id: game.phase) fires.
        if newPhase == .gameOver && !gameHistorySaved && !completedRounds.isEmpty {
            let finalScores = runningScores
            let winner = (0..<6).max(by: { finalScores[$0] < finalScores[$1] }) ?? 0
            let capturedCode = gameSessionId.isEmpty
                ? (UserDefaults.standard.string(forKey: "bt_active_game_session_id") ?? "")
                : gameSessionId
            LeaderboardService.shared.preEnqueue(
                sessionCode: capturedCode,
                gameMode:    "Bluetooth",
                playerNames: playerNames,
                finalScores: finalScores,
                winnerIndex: winner,
                aiSeats:     aiSeats,
                rounds:      completedRounds.sorted { $0.roundNumber < $1.roundNumber }
            )
        }
```

- [ ] **Step 6: Build to verify**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp \
  -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' \
  -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 7: Commit**

```bash
git add MyApp/MyApp/BluetoothGameViewModel.swift
git commit -m "fix(BT-GAP-03/05/08/09/10): stale watchdog host-exit; completedRounds merge; preEnqueue at gameOver; partner guard"
```

---

### Task 5: Fix BluetoothGameViewModel.swift — Migration + Cleanup

**Files:**
- Modify: `MyApp/MyApp/BluetoothGameViewModel.swift` — `becomeNewHost()`, `startMigrationTimeout()`, `cleanup()`

- [ ] **Step 1: Add `hasInitializedCalling = false` to `becomeNewHost()`**

Find:
```swift
    private func becomeNewHost(newHostSlot: Int) {
        isHost = true
        let gs = buildGameStateDict()
```

Replace with:
```swift
    private func becomeNewHost(newHostSlot: Int) {
        isHost = true
        hasInitializedCalling = false
        let gs = buildGameStateDict()
```

- [ ] **Step 2: Add failure count to `startMigrationTimeout()`**

Find:
```swift
    private func startMigrationTimeout(electedSlot: Int) {
        migrationTimeoutTask?.cancel()
        migrationTimeoutTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            guard let self, self.isMigrating else { return }
            // Elected client also crashed — re-elect excluding them
            let connectedSlots = Set(
                (self.session?.connectedPeers ?? []).compactMap { self.peerToPlayerIndex[$0] }
            )
            let newHostSlot = (1...5).first {
                !self.aiSeats.contains($0) && connectedSlots.contains($0) && $0 != electedSlot
            } ?? -1
            guard newHostSlot >= 0 else {
                aiLog.error("[hostMigration] timeout re-election: no viable host")
                self.isMigrating = false
                return
            }
            if self.myPlayerIndex == newHostSlot {
                self.becomeNewHost(newHostSlot: newHostSlot)
            } else {
                self.startMigrationTimeout(electedSlot: newHostSlot)
            }
        }
    }
```

Replace with:
```swift
    private func startMigrationTimeout(electedSlot: Int) {
        migrationTimeoutTask?.cancel()
        migrationTimeoutTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            guard let self, self.isMigrating else { return }
            self.migrationFailureCount += 1
            if self.migrationFailureCount >= 3 {
                aiLog.error("[hostMigration] \(self.migrationFailureCount) consecutive failures — treating as host exit")
                self.hostEndedGame = true
                self.isMigrating = false
                return
            }
            // Elected client also crashed — re-elect excluding them
            let connectedSlots = Set(
                (self.session?.connectedPeers ?? []).compactMap { self.peerToPlayerIndex[$0] }
            )
            let newHostSlot = (1...5).first {
                !self.aiSeats.contains($0) && connectedSlots.contains($0) && $0 != electedSlot
            } ?? -1
            guard newHostSlot >= 0 else {
                aiLog.error("[hostMigration] timeout re-election: no viable host")
                self.isMigrating = false
                return
            }
            if self.myPlayerIndex == newHostSlot {
                self.becomeNewHost(newHostSlot: newHostSlot)
            } else {
                self.startMigrationTimeout(electedSlot: newHostSlot)
            }
        }
    }
```

- [ ] **Step 3: Reset `migrationFailureCount` in `cleanup()`**

Find in `cleanup()`:
```swift
        isMigrating = false
        isProcessingAction = false
```

Replace with:
```swift
        isMigrating = false
        migrationFailureCount = 0
        isProcessingAction = false
```

- [ ] **Step 4: Build to verify**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp \
  -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' \
  -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 5: Commit**

```bash
git add MyApp/MyApp/BluetoothGameViewModel.swift
git commit -m "fix(BT-GAP-11/12/13): hasInitializedCalling reset; migrationFailureCount limit; cleanup reset"
```

---

### Task 6: Fix BluetoothGameView.swift

**Files:**
- Modify: `MyApp/MyApp/BluetoothGameView.swift` — three 400ms timeouts, `saveOnQuit()` guard

- [ ] **Step 1: Change 400ms to 2000ms (all three locations)**

There are three occurrences of `try? await Task.sleep(nanoseconds: 400_000_000)` in host quit paths. Replace all with `do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch {}`.

- [ ] **Step 2: Update `saveOnQuit()` non-host guard**

Find:
```swift
        if !game.isHost && game.phase != .gameOver { return }
```

Replace with:
```swift
        if !game.isHost && game.phase != .gameOver && game.completedRounds.isEmpty { return }
```

- [ ] **Step 3: Build to verify**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp \
  -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' \
  -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 4: Commit**

```bash
git add MyApp/MyApp/BluetoothGameView.swift
git commit -m "fix(BT-GAP-02/07): 400ms→2000ms cleanup delay; non-host saveOnQuit allows mid-game completedRounds"
```

---

### Task 7: Update CLAUDE.md + Final Build + Push

**Files:**
- Modify: `CLAUDE.md` (v1.9 Changelog section)

- [ ] **Step 1: Add changelog entry**

Prepend to v1.9 Changelog:
```
- [2026-05-25] Fix 14 BT leaderboard robustness gaps (BT-GAP-01 through BT-GAP-14): (1) **BT-GAP-01:** `notifyHostEndedGame()` now drains `pendingResyncPeers` before sending farewell — peers that missed the `.gameOver` broadcast receive both the full game state and the notification. (2) **BT-GAP-02/04:** Host cleanup delay increased from 400ms → 2000ms in all three quit paths so MC has time to deliver farewell + resync. (3) **BT-GAP-03/14:** `LeaderboardService.preEnqueue()` added — called synchronously from `applyGameState()` at `.gameOver` to persist the record before the async Task fires; `enqueue()` now replaces-on-duplicate so `removeFromQueue(id:)` uses the correct UUID. (4) **BT-GAP-05/10:** Stale-state watchdog adds `consecutiveStaleRequests` counter; after 2 consecutive 15s misses (30s total) sets `hostEndedGame = true` — handles host process-kill without farewell. Counter resets on every `applyGameState()` call. (5) **BT-GAP-06/09:** `completedRounds` now serialized in `buildGameStateDict()` and merged in `applyGameState()` — reconnecting non-host clients recover full multi-round history from the next game state broadcast. (6) **BT-GAP-07:** `saveOnQuit()` guard relaxed for non-hosts: `if !game.isHost && game.phase != .gameOver && game.completedRounds.isEmpty` — allows non-hosts to save accumulated completed rounds even when quitting mid-game. (7) **BT-GAP-08:** Partner index normalization (-1→0) replaced with a guard: local `completedRounds.append` now skips if partner indices are -1; host-synced data provides the correction. (8) **BT-GAP-11:** `becomeNewHost()` now resets `hasInitializedCalling = false` — prevents wrong calling defaults after host migration during calling phase. (9) **BT-GAP-12/13:** `migrationFailureCount` added; after 3 consecutive migration timeouts → `hostEndedGame = true`; reset in `cleanup()`. (`BluetoothGameViewModel.swift`, `BluetoothGameView.swift`, `LeaderboardService.swift`, `AUDIT_REPORT.md`)
```

- [ ] **Step 2: Final build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp \
  -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' \
  -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```
Expected: `Build succeeded`

- [ ] **Step 3: Push to remote**

```bash
git push
```
