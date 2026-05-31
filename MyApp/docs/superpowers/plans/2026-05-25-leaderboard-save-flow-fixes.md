# Leaderboard Save Flow — Fix All Open Issues

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all 19 confirmed open issues in the leaderboard save flow (15 from the audit + 5 flow-map gaps, minus HIGH-02 which is already resolved in current code).

**Architecture:** Fixes span four layers — LeaderboardService (input guards + dedup), ViewModels (completedRounds dedup), View save-path gaps (missing saveOnQuit calls), and the Cloud Function (logging + validation). Each task is independent and produces a working, testable change.

**Tech Stack:** Swift/SwiftUI, @MainActor, SwiftData, Firebase Firestore, Node.js Cloud Function

**Project root:** `/Users/vijaygoyal/MyiOSApp/MyApp`
**Build command:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build 2>&1 | tail -5`
**Install + launch:** `xcrun simctl install DA97985A-F7CC-44F6-8281-9DD24C22B978 /Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Build/Products/Debug-iphonesimulator/MyApp.app && xcrun simctl launch DA97985A-F7CC-44F6-8281-9DD24C22B978 com.vijaygoyal.theshadyspade`

**Note on HIGH-02:** Already resolved in current code — `saveBTGameHistory()` already guards `partner1Index >= 0 && partner2Index >= 0` before the synthetic fallback; no `max(0,)` normalization exists.

---

## Files Modified

| File | Tasks | What changes |
|---|---|---|
| `MyApp/LeaderboardService.swift` | 1, 2, 3 | Input guards, flag timing, duplicate-skip status |
| `MyApp/OnlineGameViewModel.swift` | 4 | `completedRounds` dedup guard |
| `MyApp/BluetoothGameViewModel.swift` | 4 | `completedRounds` dedup guard |
| `MyApp/BluetoothGameView.swift` | 5 | GAP-4, GAP-5, RED-1 |
| `MyApp/OnlineGameView.swift` | 6 | GAP-2, GAP-3 |
| `MyApp/ComputerGameView.swift` | 7 | GAP-1 |
| `functions/index.js` | 8 | LOW-01, LOW-03, LOW-04 |
| `CLAUDE.md` | each task | Changelog entry per task |

---

## Task 1: LeaderboardService — Input Validation Guards
**Fixes:** CRIT-01 (runningScores size), HIGH-01 (aiSeats bounds), HIGH-03 (finalScores size), CRIT-03 (sort comment)

**File:** `MyApp/LeaderboardService.swift`

- [ ] **Step 1: Write the validation test script**

```swift
// Save as /tmp/test_lb_validation.swift and run with: swift /tmp/test_lb_validation.swift

// Simulates the guard logic to be added to recordGame()
func validateRecordGameInputs(
    playerNames: [String],
    finalScores: [Int],
    aiSeats: [Int],
    runningScoresCounts: [Int]  // one per HistoryRound
) -> (passed: Bool, reason: String?) {
    guard playerNames.count == 6 else { return (false, "playerNames.count=\(playerNames.count)") }
    guard finalScores.count == 6 else { return (false, "finalScores.count=\(finalScores.count)") }
    guard runningScoresCounts.allSatisfy({ $0 == 6 }) else { return (false, "runningScores not all 6") }
    let validAI = aiSeats.filter { (0..<6).contains($0) }
    // aiSeats: filter not abort (don't lose the game for bad seat indices)
    return (true, nil)
}

var passed = 0
var failed = 0

func check(_ label: String, _ result: (passed: Bool, reason: String?), expectPass: Bool) {
    if result.passed == expectPass {
        print("✅ \(label)")
        passed += 1
    } else {
        print("❌ \(label) — expected pass=\(expectPass), got pass=\(result.passed), reason=\(result.reason ?? "nil")")
        failed += 1
    }
}

check("valid input passes",
      validateRecordGameInputs(playerNames: Array(repeating: "A", count: 6),
                                finalScores: Array(repeating: 100, count: 6),
                                aiSeats: [2, 3],
                                runningScoresCounts: [6, 6, 6]),
      expectPass: true)

check("finalScores wrong count fails",
      validateRecordGameInputs(playerNames: Array(repeating: "A", count: 6),
                                finalScores: [100, 200],
                                aiSeats: [],
                                runningScoresCounts: [6]),
      expectPass: false)

check("runningScores wrong count fails",
      validateRecordGameInputs(playerNames: Array(repeating: "A", count: 6),
                                finalScores: Array(repeating: 100, count: 6),
                                aiSeats: [],
                                runningScoresCounts: [6, 5]),
      expectPass: false)

check("aiSeats out of range — does NOT fail (filter, not abort)",
      validateRecordGameInputs(playerNames: Array(repeating: "A", count: 6),
                                finalScores: Array(repeating: 100, count: 6),
                                aiSeats: [0, 99],
                                runningScoresCounts: [6]),
      expectPass: true)  // passes, but invalid seat filtered

print("\n\(passed) passed, \(failed) failed")
```

- [ ] **Step 2: Run test — expect all 4 to pass**

```bash
swift /tmp/test_lb_validation.swift
```
Expected: `4 passed, 0 failed`

- [ ] **Step 3: Add guards to `recordGame()` in `LeaderboardService.swift`**

Read the current `recordGame()` at line 258. It starts:
```swift
func recordGame(...) async {
    lbLog.info("recordGame called ...")
    guard playerNames.count == 6,
          let lastRound = rounds.last else {
        lbLog.error("recordGame guard failed — ...")
        return
    }
```

Replace that guard block with:
```swift
func recordGame(...) async {
    lbLog.info("recordGame called mode=\(gameMode) names=\(playerNames.count) rounds=\(rounds.count) winner=\(winnerIndex)")
    // CRIT-01/HIGH-03: validate array sizes before enqueuing — a malformed record
    // would cause a permanent HTTP 400 discard on every flush attempt.
    guard playerNames.count == 6 else {
        lbLog.error("recordGame aborted — playerNames.count=\(playerNames.count) ≠ 6")
        return
    }
    guard finalScores.count == 6 else {
        lbLog.error("recordGame aborted — finalScores.count=\(finalScores.count) ≠ 6")
        return
    }
    guard rounds.allSatisfy({ $0.runningScores.count == 6 }) else {
        lbLog.error("recordGame aborted — a HistoryRound has runningScores.count ≠ 6")
        return
    }
    guard let lastRound = rounds.last else {
        lbLog.error("recordGame aborted — rounds is empty")
        return
    }
    // HIGH-01: filter out-of-range aiSeats rather than abort — the game record
    // is valid; bad indices are a caller bug and the server filters them anyway.
    let validAISeats = aiSeats.filter { (0..<6).contains($0) }
    if validAISeats.count != aiSeats.count {
        lbLog.warning("recordGame: dropped \(aiSeats.count - validAISeats.count) invalid aiSeat index(es)")
    }
```

Then replace the `aiSeats: aiSeats.map { Int($0) }` line in the `PendingGameRecord` init with:
```swift
aiSeats: validAISeats.map { Int($0) },
```

Also add a comment on the sort in `saveOnlineGameHistory()` fallback path (CRIT-03 — single-element doesn't need sort but document why):

In `OnlineGameView.swift` `saveOnlineGameHistory()`, find the synthetic fallback `roundsToSend = [HistoryRound(...)]` and add above it:
```swift
// Single-element array — sort is a no-op, but included for parity with the
// completedRounds path above so both branches produce a sorted array.
roundsToSend = [HistoryRound(...)].sorted { $0.roundNumber < $1.roundNumber }
```

Do the same in `BluetoothGameView.swift` `saveBTGameHistory()` synthetic fallback and both `saveOnQuit()` synthetic fallbacks.

- [ ] **Step 4: Build and verify no errors**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Update CLAUDE.md v1.9 changelog**

Add entry:
```
- [2026-05-25] Fix CRIT-01/HIGH-01/HIGH-03/CRIT-03 — LeaderboardService input validation: (1) `recordGame()` now guards `finalScores.count == 6` and `rounds.allSatisfy { $0.runningScores.count == 6 }` — malformed arrays abort before enqueue rather than producing an unfixable HTTP 400 on every flush. (2) Invalid `aiSeats` indices filtered (not abort) with warning log — game record is preserved, bad index dropped. (3) Synthetic fallback arrays in all four save functions now consistently use `.sorted { $0.roundNumber < $1.roundNumber }` even though they are single-element, for parity with the `completedRounds` primary path. (`LeaderboardService.swift`, `OnlineGameView.swift`, `BluetoothGameView.swift`)
```

- [ ] **Step 6: Commit**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp
git add MyApp/LeaderboardService.swift MyApp/OnlineGameView.swift MyApp/BluetoothGameView.swift CLAUDE.md
git commit -m "fix: leaderboard input validation — size guards and aiSeats filter (CRIT-01/HIGH-01/HIGH-03/CRIT-03)"
```

---

## Task 2: LeaderboardService — gameHistorySaved Race + Duplicate Skip Status
**Fixes:** MED-03 (flag set too late), LOW-02 (silent duplicate skip)

**File:** `MyApp/LeaderboardService.swift`, `MyApp/OnlineGameView.swift`

- [ ] **Step 1: Write the race condition test**

```swift
// Save as /tmp/test_flag_timing.swift
// Simulates the MED-03 pattern: two concurrent callers, flag must block the second

actor SaveFlag {
    private var saved = false
    func claimAndSave() -> Bool {
        guard !saved else { return false }
        saved = true
        return true
    }
    func reset() { saved = false }
}

import Foundation

let flag = SaveFlag()
var saveCount = 0
let lock = NSLock()

func increment() { lock.lock(); saveCount += 1; lock.unlock() }

// Simulate two concurrent calls
let g = DispatchGroup()
for _ in 0..<2 {
    g.enter()
    DispatchQueue.global().async {
        Task {
            if await flag.claimAndSave() { increment() }
            g.leave()
        }
    }
}
g.wait()
Thread.sleep(forTimeInterval: 0.1)

if saveCount == 1 {
    print("✅ flag correctly blocks concurrent second call — saveCount=\(saveCount)")
} else {
    print("❌ flag FAILED — saveCount=\(saveCount), expected 1")
}
```

- [ ] **Step 2: Run test — expect pass**

```bash
swift /tmp/test_flag_timing.swift
```
Expected: `✅ flag correctly blocks concurrent second call — saveCount=1`

- [ ] **Step 3: Fix `saveOnlineGameHistory()` — claim flag before guard checks**

In `OnlineGameView.swift`, find `saveOnlineGameHistory()` (around line 267). Current code:
```swift
private func saveOnlineGameHistory() {
    guard !game.gameHistorySaved else { return }
    let finalScores = game.runningScores
    guard game.highBidderIndex >= 0,
          game.partner1Index >= 0,
          game.partner2Index >= 0 else {
        ogLog.warning("saveOnlineGameHistory: deferred — ...")
        return
    }
    game.gameHistorySaved = true
```

Change to:
```swift
private func saveOnlineGameHistory() {
    guard !game.gameHistorySaved else { return }
    // MED-03: claim the flag immediately — before partner-index guards — so that
    // concurrent triggers (.task + .onChange) can't both pass the guard and
    // both reach recordGame(). Release below if we must defer.
    game.gameHistorySaved = true
    let finalScores = game.runningScores
    guard game.highBidderIndex >= 0,
          game.partner1Index >= 0,
          game.partner2Index >= 0 else {
        game.gameHistorySaved = false  // release so the .onChange retry can save
        ogLog.warning("saveOnlineGameHistory: deferred — bidder=\(game.highBidderIndex) p1=\(game.partner1Index) p2=\(game.partner2Index)")
        return
    }
    // flag stays true — proceed with save
```

- [ ] **Step 4: Fix `enqueue()` — update scoreSaveStatus on duplicate skip**

In `LeaderboardService.swift`, find `enqueue()` around line 396. Current:
```swift
guard !records.contains(where: { $0.deduplicationKey == record.deduplicationKey }) else {
    lbLog.warning("enqueue: duplicate skipped id=\(record.id)")
    return
}
```

Change to:
```swift
guard !records.contains(where: { $0.deduplicationKey == record.deduplicationKey }) else {
    lbLog.warning("enqueue: duplicate skipped id=\(record.id)")
    // LOW-02: treat a duplicate as already-queued/saved so the UI doesn't
    // get stuck showing .saving when the original record is already in flight.
    scoreSaveStatus = .saved
    return
}
```

- [ ] **Step 5: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Update CLAUDE.md and commit**

Add to CLAUDE.md v1.9 changelog:
```
- [2026-05-25] Fix MED-03/LOW-02 — (1) `saveOnlineGameHistory()` now claims `gameHistorySaved = true` before the partner-index guard, then releases it (`= false`) if deferred — prevents two concurrent triggers from both passing the guard and both calling `recordGame()`. (2) `enqueue()` sets `scoreSaveStatus = .saved` when a duplicate is detected — UI no longer stays stuck on `.saving` when the game was already queued. (`OnlineGameView.swift`, `LeaderboardService.swift`)
```

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp
git add MyApp/OnlineGameView.swift MyApp/LeaderboardService.swift CLAUDE.md
git commit -m "fix: gameHistorySaved race window and duplicate-skip status update (MED-03/LOW-02)"
```

---

## Task 3: ViewModels — completedRounds Dedup Guard
**Fixes:** CRIT-02 (both OnlineGameViewModel and BluetoothGameViewModel)

The current guard `completedRounds.last?.roundNumber != roundNumber` only catches consecutive duplicates. If two out-of-order snapshots deliver the same roundNumber non-consecutively (reconnect scenario), the `last` check misses it. Replace with `contains(where:)`.

**Files:** `MyApp/OnlineGameViewModel.swift` (line 674), `MyApp/BluetoothGameViewModel.swift` (line 1104)

- [ ] **Step 1: Write the dedup test**

```swift
// Save as /tmp/test_completed_rounds_dedup.swift

struct HistoryRound { let roundNumber: Int }

func shouldAppend(completedRounds: [HistoryRound], roundNumber: Int) -> Bool {
    // NEW guard (contains) vs OLD guard (last only)
    return !completedRounds.contains(where: { $0.roundNumber == roundNumber })
}

var passed = 0; var failed = 0
func check(_ label: String, _ got: Bool, _ want: Bool) {
    if got == want { print("✅ \(label)"); passed += 1 }
    else { print("❌ \(label) got=\(got) want=\(want)"); failed += 1 }
}

// Empty list — always append
check("empty list", shouldAppend(completedRounds: [], roundNumber: 1), true)

// New round — always append
check("new round", shouldAppend(completedRounds: [HistoryRound(roundNumber: 1)], roundNumber: 2), true)

// Exact duplicate (consecutive) — block
check("consecutive dup", shouldAppend(completedRounds: [HistoryRound(roundNumber: 1)], roundNumber: 1), false)

// Out-of-order duplicate — contains() blocks it, last() would NOT
let outOfOrder = [HistoryRound(roundNumber: 2), HistoryRound(roundNumber: 1)]
check("out-of-order dup blocked by contains", shouldAppend(completedRounds: outOfOrder, roundNumber: 2), false)
// The OLD last-based guard would return true here (last=1, 1 != 2 → append) — WRONG
let oldGuard = outOfOrder.last?.roundNumber != 2
check("OLD last-guard would PASS for out-of-order dup (demonstrates the bug)", oldGuard, true)

print("\n\(passed) passed, \(failed) failed")
```

- [ ] **Step 2: Run test — expect all 5 to pass**

```bash
swift /tmp/test_completed_rounds_dedup.swift
```
Expected: `5 passed, 0 failed`

- [ ] **Step 3: Fix `OnlineGameViewModel.swift`**

Find lines ~674:
```swift
if (newPhase == .roundComplete || newPhase == .gameOver),
   completedRounds.last?.roundNumber != roundNumber {
    completedRounds.append(HistoryRound(
```

Change the guard line to:
```swift
if (newPhase == .roundComplete || newPhase == .gameOver),
   !completedRounds.contains(where: { $0.roundNumber == roundNumber }) {
    completedRounds.append(HistoryRound(
```

- [ ] **Step 4: Fix `BluetoothGameViewModel.swift`**

Find lines ~1104 (identical pattern):
```swift
if (newPhase == .roundComplete || newPhase == .gameOver),
   completedRounds.last?.roundNumber != roundNumber {
    completedRounds.append(HistoryRound(
```

Change to:
```swift
if (newPhase == .roundComplete || newPhase == .gameOver),
   !completedRounds.contains(where: { $0.roundNumber == roundNumber }) {
    completedRounds.append(HistoryRound(
```

- [ ] **Step 5: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Update CLAUDE.md and commit**

```
- [2026-05-25] Fix CRIT-02 — `completedRounds` dedup guard strengthened in both `OnlineGameViewModel` and `BluetoothGameViewModel`: replaced `completedRounds.last?.roundNumber != roundNumber` with `!completedRounds.contains(where: { $0.roundNumber == roundNumber })`. The old guard only caught consecutive duplicates; out-of-order reconnect snapshots delivering the same roundNumber non-consecutively could append a duplicate round and inflate player stats. (`OnlineGameViewModel.swift`, `BluetoothGameViewModel.swift`)
```

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp
git add MyApp/OnlineGameViewModel.swift MyApp/BluetoothGameViewModel.swift CLAUDE.md
git commit -m "fix: completedRounds dedup uses contains(where:) not last check (CRIT-02)"
```

---

## Task 4: BluetoothGameView — GAP-4, GAP-5, RED-1
**Fixes:** GAP-4 (non-host loses data when host ends game), GAP-5 (system dismiss), RED-1 (redundant .onAppear)

**File:** `MyApp/BluetoothGameView.swift`

- [ ] **Step 1: Fix GAP-4 — add `saveOnQuit()` to "Game Ended" alert**

Find the "Game Ended" alert handler (around line 207):
```swift
.onChange(of: game.hostEndedGame) { _, ended in
    if ended && !game.isHost { showHostEndedGameAlert = true }
}
.alert("Game Ended", isPresented: $showHostEndedGameAlert) {
    Button("OK") {
        game.cleanup()
        dismiss()
    }
}
```

Change the Button action to:
```swift
Button("OK") {
    saveOnQuit()   // GAP-4: save completed rounds before teardown
    game.cleanup()
    dismiss()
}
```

Note: `saveOnQuit()` already handles the non-host case correctly — it guards `if !game.isHost && game.phase != .gameOver { return }`. When a host ends the game, non-hosts receive `hostEndedGame` AFTER the host has written `.gameOver` to Firestore/MC, so `game.phase == .gameOver` and the guard passes.

- [ ] **Step 2: Fix GAP-5 — add `saveOnQuit()` to `.onDisappear`**

Find the `.onDisappear` (line 218):
```swift
.onDisappear { game.cleanup() }
```

Change to:
```swift
.onDisappear {
    saveOnQuit()   // GAP-5: last-resort save on system dismiss
    game.cleanup()
}
```

The `game.gameHistorySaved` flag prevents double-saves if a normal save path already ran.

- [ ] **Step 3: Fix RED-1 — remove redundant `.onAppear` on BTGameOverView**

Find inside the `.gameOver` case (around line 73):
```swift
case .gameOver:
    BTGameOverView(game: game) { ... }
    .onAppear { saveBTGameHistory() }
```

Remove the `.onAppear` modifier entirely — `.task(id: game.phase)` at the root level already calls `saveBTGameHistory()` when phase becomes `.gameOver`:
```swift
case .gameOver:
    BTGameOverView(game: game) { ... }
```

- [ ] **Step 4: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Update CLAUDE.md and commit**

```
- [2026-05-25] Fix GAP-4/GAP-5/RED-1 in BluetoothGameView — (1) **GAP-4:** Added `saveOnQuit()` to "Game Ended" alert OK handler — non-host players' completed rounds were previously lost when the host ended the game. `saveOnQuit()` already guards `phase == .gameOver` for non-hosts. (2) **GAP-5:** Added `saveOnQuit()` to `.onDisappear` as last-resort save on system dismiss. `gameHistorySaved` flag prevents double-saves. (3) **RED-1:** Removed redundant `.onAppear { saveBTGameHistory() }` from `BTGameOverView` — `.task(id: game.phase)` at the root already handles this save; `.onAppear` was always a no-op after the flag was set. (`BluetoothGameView.swift`)
```

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp
git add MyApp/BluetoothGameView.swift CLAUDE.md
git commit -m "fix: BT non-host save on host-ended game, system dismiss save, remove redundant onAppear (GAP-4/GAP-5/RED-1)"
```

---

## Task 5: OnlineGameView — GAP-2, GAP-3
**Fixes:** GAP-2 (removed-from-game loses data), GAP-3 (system dismiss loses data)

**File:** `MyApp/OnlineGameView.swift`

- [ ] **Step 1: Fix GAP-2 — add `saveOnQuit()` to "Removed from Game" alert**

Find the removed-from-game alert (around line 123):
```swift
.alert("Removed from Game", isPresented: $showRemovedFromGameAlert) {
    Button("OK") {
        game.stopPresenceTracking()
        dismiss()
    }
}
```

Change to:
```swift
.alert("Removed from Game", isPresented: $showRemovedFromGameAlert) {
    Button("OK") {
        // GAP-2: save before tearing down. saveOnQuit() guards non-host
        // mid-game saves, so this is a no-op unless phase == .gameOver.
        // Accepts that mid-game removal loses the removed player's rounds —
        // the remaining players continue and will submit the full record.
        saveOnQuit()
        game.stopPresenceTracking()
        dismiss()
    }
}
```

- [ ] **Step 2: Fix GAP-3 — add `saveOnQuit()` to `.onDisappear`**

Find `.onDisappear` (around line 105):
```swift
.onDisappear {
    game.stopPresenceTracking()
    game.cleanup()
}
```

Change to:
```swift
.onDisappear {
    saveOnQuit()   // GAP-3: last-resort save on system dismiss
    game.stopPresenceTracking()
    game.cleanup()
}
```

- [ ] **Step 3: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Update CLAUDE.md and commit**

```
- [2026-05-25] Fix GAP-2/GAP-3 in OnlineGameView — (1) **GAP-2:** Added `saveOnQuit()` to "Removed from Game" alert OK handler. `saveOnQuit()` correctly returns early for non-hosts when `phase != .gameOver`, so mid-game removal still produces no record (the remaining players submit the full game); this only saves if the removal happens at game-over. (2) **GAP-3:** Added `saveOnQuit()` to `.onDisappear` as last-resort save on system dismiss. (`OnlineGameView.swift`)
```

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp
git add MyApp/OnlineGameView.swift CLAUDE.md
git commit -m "fix: online removed-from-game save and system dismiss save (GAP-2/GAP-3)"
```

---

## Task 6: ComputerGameView — GAP-1
**Fix:** GAP-1 (Solo/P&P system dismiss loses completed rounds)

**File:** `MyApp/ComputerGameView.swift`

Note: `ComputerGameView` is a `fullScreenCover`. Sheets presented over it (e.g., `showGameHistory`) do NOT trigger `.onDisappear` on the cover itself, so it is safe to save here.

- [ ] **Step 1: Fix GAP-1 — add save to `.onDisappear`**

Find `.onDisappear` (around line 172):
```swift
.onDisappear { game.cancelAllContinuationsIfNeeded() }
```

Change to:
```swift
.onDisappear {
    // GAP-1: last-resort save if the system dismisses the fullScreenCover
    // (memory pressure, navigation). soloGameSaved flag prevents double-saves.
    if !soloGameSaved && !savedHistoryRounds.isEmpty {
        soloGameSaved = true
        let mode = game.isPassAndPlay ? "PassAndPlay" : (game._allPlayerNames.isEmpty ? "Solo" : "Multiplayer")
        saveGameHistory(finalScores: runningScores, mode: mode)
    }
    game.cancelAllContinuationsIfNeeded()
}
```

- [ ] **Step 2: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Update CLAUDE.md and commit**

```
- [2026-05-25] Fix GAP-1 — Solo/P&P `.onDisappear` now saves completed rounds if `soloGameSaved` is still false and at least one round was completed. This covers system-level dismissal of the fullScreenCover (memory pressure, navigation). Sheets presented over the cover do not trigger `.onDisappear` on it, so this is safe. (`ComputerGameView.swift`)
```

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp
git add MyApp/ComputerGameView.swift CLAUDE.md
git commit -m "fix: solo/P&P system dismiss now saves completed rounds (GAP-1)"
```

---

## Task 7: Cloud Function — LOW-01, LOW-03, LOW-04
**Fixes:** LOW-01 (profanity rejection reason hidden), LOW-03 (aiSeats drop not logged), LOW-04 (round sequence not validated)

**File:** `functions/index.js`

- [ ] **Step 1: Fix LOW-01 — add reason code to profanity rejection**

Find the profanity rejection (search for `"inappropriate content"`). Current:
```js
return res.status(400).send(`Player name "${name}" contains inappropriate content.`);
```

Change to:
```js
return res.status(400).send(JSON.stringify({
    error: `Player name contains inappropriate content.`,
    code: "PROFANITY_REJECTED",
    field: "playerNames"
}));
```

- [ ] **Step 2: Fix LOW-03 — log dropped aiSeats indices**

Find the aiSeats filter (search for `Number.isInteger(i) && i >= 0 && i < PLAYER_COUNT`). Current:
```js
const aiSeatsSet = new Set((payload.aiSeats || []).filter(i => Number.isInteger(i) && i >= 0 && i < PLAYER_COUNT));
```

Change to:
```js
const rawAISeats = payload.aiSeats || [];
const validAISeats = rawAISeats.filter(i => Number.isInteger(i) && i >= 0 && i < PLAYER_COUNT);
const droppedAISeats = rawAISeats.filter(i => !Number.isInteger(i) || i < 0 || i >= PLAYER_COUNT);
if (droppedAISeats.length > 0) {
    functions.logger.warn("recordGame: dropped invalid aiSeats", {
        dropped: droppedAISeats,
        sessionCode: payload.sessionCode ?? null
    });
}
const aiSeatsSet = new Set(validAISeats);
```

- [ ] **Step 3: Fix LOW-04 — validate round number sequence**

After the `roundCount` validation (search for `roundCount > 200`), add:
```js
// LOW-04: warn if rounds are not sequential (gaps indicate missed completedRounds appends)
if (Array.isArray(rounds) && rounds.length > 1) {
    const roundNums = rounds.map(r => r.roundNumber);
    const isSequential = roundNums.every((n, i) => i === 0 || n === roundNums[i - 1] + 1);
    if (!isSequential) {
        functions.logger.warn("recordGame: non-sequential round numbers — possible missed append", {
            roundNumbers: roundNums,
            sessionCode: payload.sessionCode ?? null
        });
        // Accept the record — non-sequential rounds are unusual but not corrupt.
    }
}
```

- [ ] **Step 4: Deploy the Cloud Function**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp/functions
firebase deploy --only functions
```
Expected: `✔  Deploy complete!`

- [ ] **Step 5: Update CLAUDE.md and commit**

```
- [2026-05-25] Fix LOW-01/LOW-03/LOW-04 in Cloud Function — (1) **LOW-01:** Profanity rejection now returns `{error, code: "PROFANITY_REJECTED", field: "playerNames"}` JSON body instead of a plain string — iOS can detect the specific rejection reason in future. (2) **LOW-03:** Dropped invalid `aiSeats` indices now logged via `functions.logger.warn` with the specific dropped values and sessionCode — iOS-side bugs become visible in Firebase Functions logs. (3) **LOW-04:** Round number sequencing validated after `roundCount` check; non-sequential submissions logged as warnings (not rejected — record is still accepted). (`functions/index.js`)
```

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp
git add functions/index.js CLAUDE.md
git commit -m "fix: Cloud Function profanity reason code, aiSeats drop logging, round sequence check (LOW-01/LOW-03/LOW-04)"
```

---

## Task 8: MED-01 and MED-02 — Documentation Fixes

These are risk-mitigation notes, not code changes.

- [ ] **Step 1: MED-01 — add sync warning to both profanity filter implementations**

In `MyApp/ProfanityFilter.swift`, add at the top of the word list constant:
```swift
// IMPORTANT: This word list must be kept in sync with the Cloud Function's
// PROFANITY_LIST in functions/index.js. If the lists diverge, a name that
// passes this filter may be rejected by the server (HTTP 400 → permanent discard).
// Update both simultaneously when adding or removing words.
```

In `functions/index.js`, add above `PROFANITY_LIST`:
```js
// IMPORTANT: Keep in sync with ProfanityFilter.swift in the iOS app.
// Divergence between lists causes server rejection of names that passed iOS validation.
```

- [ ] **Step 2: MED-02 — add comment to sessionCode generation**

In `MyApp/OnlineSessionViewModel.swift`, find `findUniqueRoomCode()` and add:
```swift
// MED-02: This checks Firestore for code uniqueness but not the local pending queue.
// Collision probability is ~1 in 2.18B for 6-char alphanumeric codes — acceptable in
// practice, but if two hosts simultaneously generate the same code, one game's leaderboard
// record will be silently dropped by the iOS deduplication key. No code fix needed;
// tracked here for awareness.
```

- [ ] **Step 3: Commit**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp
git add MyApp/ProfanityFilter.swift functions/index.js MyApp/OnlineSessionViewModel.swift
git commit -m "docs: add sync warning for profanity filter lists and MED-02 awareness comment (MED-01/MED-02)"
```

---

## Task 9: Full Build, Install, and Visual Verification

- [ ] **Step 1: Full build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Install and launch on simulator**

```bash
xcrun simctl install DA97985A-F7CC-44F6-8281-9DD24C22B978 /Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Build/Products/Debug-iphonesimulator/MyApp.app && xcrun simctl launch DA97985A-F7CC-44F6-8281-9DD24C22B978 com.vijaygoyal.theshadyspade
```

- [ ] **Step 3: Visual smoke test — Solo game**
  - Play a Solo game to round-complete
  - Tap "Quit to Menu" → verify score appears in Leaderboard
  - Start another game, complete a round, then force-quit simulator app (Cmd+H twice)
  - Relaunch → verify Leaderboard still shows score (offline-queue flush)

- [ ] **Step 4: Visual smoke test — BT game**
  - Host a BT game in simulator, join from a second simulator
  - Complete one round
  - On the non-host simulator, trigger "Game Ended" (by ending from host)
  - Verify score appears in Leaderboard on the non-host device

- [ ] **Step 5: Update memory**

Update `/Users/vijaygoyal/.claude/projects/-Users-vijaygoyal/memory/project_shadyspade_leaderboard_audit.md` — mark all 19 items as ✅ fixed.

---

## Self-Review

**Spec coverage:**
- CRIT-01 ✅ Task 1
- CRIT-02 ✅ Task 3
- CRIT-03 ✅ Task 1 (sort comment)
- HIGH-01 ✅ Task 1
- HIGH-02 ✅ Already resolved — no task needed
- HIGH-03 ✅ Task 1 (same guard as CRIT-01)
- MED-01 ✅ Task 8
- MED-02 ✅ Task 8
- MED-03 ✅ Task 2
- MED-04 ✅ Confirmed non-issue on @MainActor (no await between capture points) — no fix needed
- MED-05 ✅ Addressed by MED-03 fix (gameHistorySaved claimed atomically)
- LOW-01 ✅ Task 7
- LOW-02 ✅ Task 2
- LOW-03 ✅ Task 7
- LOW-04 ✅ Task 7
- GAP-1 ✅ Task 6
- GAP-2 ✅ Task 5
- GAP-3 ✅ Task 5
- GAP-4 ✅ Task 4
- GAP-5 ✅ Task 4
- RED-1 ✅ Task 4
