# Online Multiplayer Bug Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 6 confirmed bugs in Online multiplayer mode: silent Firestore write failures in `startGame()`, no host-crash detection for non-host clients, stale player names after AI replacement, missing `aiSeats` in round-start game state writes, a TOCTOU race in mid-game player removal, and a non-cancellation-aware sleep in the AI empty-hand retry path.

**Architecture:** All changes are in `OnlineGameViewModel.swift` (logic) and `OnlineGameView.swift` (one new call site). No new files. No structural refactoring. Each task is independent — a build failure in one task does not affect the others. Bug 5 (session VM not writing `gameState.aiSeats`) is resolved as a side-effect of Task 4 and needs no separate task.

**Tech Stack:** Swift, SwiftUI, Firebase Firestore (`@Observable @MainActor`), Swift Concurrency (`Task`, `async/await`)

**Project path:** `/Users/vijaygoyal/MyiOSApp/MyApp`

**Build command (use for every Step "Build and verify"):**
```bash
xcodebuild -quiet -project MyApp.xcodeproj -scheme MyApp -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO build 2>&1 | tail -4
```
Expected: `** BUILD SUCCEEDED **`

**Install + launch (use for final Task 7 verification):**
```bash
xcrun simctl install DA97985A-F7CC-44F6-8281-9DD24C22B978 \
  /Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Build/Products/Debug-iphonesimulator/MyApp.app \
  && xcrun simctl launch DA97985A-F7CC-44F6-8281-9DD24C22B978 com.vijaygoyal.theshadyspade
```

---

## File Map

| File | Change |
|---|---|
| `MyApp/OnlineGameViewModel.swift` | Tasks 1–6: all logic changes |
| `MyApp/OnlineGameView.swift` | Task 2 only: one new call site in `.task` block |

No new files. No other files touched.

---

### Task 1: Fix `startGame()` silent Firestore write failures (Bug 1)

**Files:** Modify `MyApp/OnlineGameViewModel.swift` — `startGame()` function (~line 247)

**Root cause:** Both writes in `startGame()` use `try?`, silently discarding failures. If the hands+gameState write fails, all clients receive the dealing animation then freeze permanently — no error shown, no retry, no recovery.

- [ ] **Step 1: Replace the dealing animation write with a logged `do/catch`**

The animation write is non-critical (a missed animation is acceptable). Change from silent `try?` to a logged warning. In `startGame()`, find:

```swift
let dealingGs: [String: Any] = ["phase": OnlineGamePhase.dealing.rawValue]
try? await ref.updateData(["gameState": dealingGs])
```

Replace with:

```swift
let dealingGs: [String: Any] = ["phase": OnlineGamePhase.dealing.rawValue]
do {
    try await ref.updateData(["gameState": dealingGs])
} catch {
    ogVMLog.warning("[startGame] dealing animation write failed (non-critical): \(error.localizedDescription)")
}
```

- [ ] **Step 2: Replace the hands+gameState write with `criticalWrite`**

The main write is critical — it distributes hands and sets `.lookingAtCards`. Find:

```swift
try? await ref.updateData([
    "gameState": gs,
    "hands": handsDict,
    "pendingAction": [:] as [String: Any]
])
```

Replace with:

```swift
let startOk = await criticalWrite([
    "gameState": gs,
    "hands": handsDict,
    "pendingAction": [:] as [String: Any]
])
if !startOk {
    ogVMLog.error("[startGame] failed to write initial game state after all retries — players will see an error banner")
}
```

`criticalWrite` retries 3× (2s then 4s backoff) and sets `errorMessage` on total failure, giving players visible feedback.

- [ ] **Step 3: Build and verify**

Run the build command above. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MyApp/OnlineGameViewModel.swift
git commit -m "$(cat <<'EOF'
Fix: replace try? writes in startGame() with criticalWrite + do/catch

Silent try? on the hands+gameState write permanently froze all clients on
network failure with no error or retry path. criticalWrite retries 3x and
shows errorMessage on total failure. Animation write gets a logged warning.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Add host-crash detection for non-host clients (Bug 2)

**Files:**
- Modify: `MyApp/OnlineGameViewModel.swift` — `startPresenceTracking()`, `stopPresenceTracking()`, new `startHostPresenceMonitoring()`, new property
- Modify: `MyApp/OnlineGameView.swift` — `.task` block (~line 115)

**Root cause:** `startPresenceTracking()` has `guard !isHost else { return }` so the host never writes a heartbeat. Non-host clients have no mechanism to detect a host crash. If the host process-kills without calling `notifyHostEndedGame()`, non-host clients freeze forever.

**Fix:** Remove the host guard (host now writes heartbeat too). Add `startHostPresenceMonitoring()` for non-hosts — polls every 30s, sets `hostEndedGame = true` if host's heartbeat is >60s stale. The 60s threshold avoids false positives during normal gameplay pauses (the longest expected pause is ~7s for a criticalWrite with all retries).

- [ ] **Step 1: Add `hostPresenceMonitoringTimer` property**

In `OnlineGameViewModel`, in the `// MARK: Presence tracking` block (~line 101), add the new property alongside the existing timers:

```swift
// MARK: Presence tracking
private var presenceTimer: Timer?
private var monitoringTimer: Timer?
private var hostPresenceMonitoringTimer: Timer?   // ← ADD
private var prevAISeats: Set<Int> = []
```

- [ ] **Step 2: Remove the `guard !isHost` from `startPresenceTracking()`**

Find:
```swift
func startPresenceTracking() {
    guard !isHost else { return }
    guard presenceTimer == nil else { return }
```

Replace with:
```swift
func startPresenceTracking() {
    guard presenceTimer == nil else { return }
```

Now both host and non-host write `presence.\(myPlayerIndex)` every 10 seconds. The host is always slot 0, so non-hosts can monitor `presence.0`.

- [ ] **Step 3: Invalidate `hostPresenceMonitoringTimer` in `stopPresenceTracking()`**

Find:
```swift
func stopPresenceTracking() {
    presenceTimer?.invalidate()
    presenceTimer = nil
    monitoringTimer?.invalidate()
    monitoringTimer = nil
}
```

Replace with:
```swift
func stopPresenceTracking() {
    presenceTimer?.invalidate()
    presenceTimer = nil
    monitoringTimer?.invalidate()
    monitoringTimer = nil
    hostPresenceMonitoringTimer?.invalidate()
    hostPresenceMonitoringTimer = nil
}
```

- [ ] **Step 4: Add `startHostPresenceMonitoring()` function**

Add this function directly after `stopPresenceTracking()` (before `removePlayerMidGame`):

```swift
/// Non-host clients call this to detect a silent host crash.
/// Polls Firestore every 30s; if the host's heartbeat (presence["0"]) is
/// older than 60s, sets hostEndedGame = true so the "Game Ended" alert fires.
/// 60s threshold: host writes every 10s, so 6 missed writes before triggering.
/// This is conservative enough to avoid false positives during the ~7s worst-case
/// criticalWrite backoff or the 3s dealing animation sleep.
func startHostPresenceMonitoring() {
    guard !isHost else { return }
    let ref = Firestore.firestore().collection("sessions").document(sessionCode)
    hostPresenceMonitoringTimer = Timer.scheduledTimer(
        withTimeInterval: 30, repeats: true
    ) { [weak self] _ in
        guard let self else { return }
        Task { @MainActor [weak self] in
            guard let self,
                  !self.hostEndedGame,
                  !self.wasRemovedFromGame else { return }
            guard let data = (try? await ref.getDocument())?.data(),
                  let presence = data["presence"] as? [String: Any] else { return }
            guard let lastSeen = (presence["0"] as? Timestamp)?.dateValue() else {
                // Host hasn't written presence yet (within first 30s window) — not a crash
                return
            }
            if Date().timeIntervalSince(lastSeen) > 60 {
                ogVMLog.warning("[hostPresence] host (slot 0) last seen \(Date().timeIntervalSince(lastSeen))s ago — treating as disconnected")
                self.hostEndedGame = true
            }
        }
    }
}
```

- [ ] **Step 5: Call `startHostPresenceMonitoring()` from `OnlineGameView`**

In `OnlineGameView.swift`, find the `.task` block:

```swift
.task {
    LeaderboardService.shared.resetScoreSaveStatus()
    game.attachListener()
    game.startPresenceTracking()
    game.monitorPresence()
    if game.isHost { await game.startGame() }
}
```

Replace with:

```swift
.task {
    LeaderboardService.shared.resetScoreSaveStatus()
    game.attachListener()
    game.startPresenceTracking()
    game.monitorPresence()
    game.startHostPresenceMonitoring()
    if game.isHost { await game.startGame() }
}
```

`startHostPresenceMonitoring()` guards `!isHost` internally, so calling it unconditionally is safe.

- [ ] **Step 6: Build and verify**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add MyApp/OnlineGameViewModel.swift MyApp/OnlineGameView.swift
git commit -m "$(cat <<'EOF'
Fix: host writes presence heartbeat; non-host monitors host for crash detection

Host was excluded from startPresenceTracking() so non-hosts had no way to
detect a silent crash. Now host writes presence.0 every 10s. startHostPresenceMonitoring()
polls presence.0 every 30s and sets hostEndedGame=true if >60s stale, triggering
the existing Game Ended alert on non-host clients.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Sync `playerNames`/`playerAvatars` when AI replaces a disconnected player (Bug 3)

**Files:** Modify `MyApp/OnlineGameViewModel.swift` — `handleSnapshot()` (~line 489)

**Root cause:** `playerNames` and `playerAvatars` are set at init and never updated. When `monitorPresence` replaces a disconnected player's slot with an AI bot name/avatar, `game.playerNames` still shows the old human's name everywhere (trick messages, avatar strip, leaderboard recording).

- [ ] **Step 1: Parse `playerSlots` in `handleSnapshot` and sync `playerNames`/`playerAvatars`**

In `handleSnapshot`, after the `aiSeats` sync block and before the `gameState` parse (~line 496), add:

```swift
// Sync player display names and avatars when presence monitoring replaces a
// disconnected human with an AI bot — playerSlots is the authoritative source.
// The != guard prevents unnecessary SwiftUI re-renders when nothing changed.
if let slotsData = data["playerSlots"] as? [[String: Any]], slotsData.count == 6 {
    let newNames = slotsData.map { $0["name"] as? String ?? "" }
    let newAvatars = slotsData.map { $0["avatar"] as? String ?? "🃏" }
    if newNames != playerNames { playerNames = newNames }
    if newAvatars != playerAvatars { playerAvatars = newAvatars }
}
```

- [ ] **Step 2: Build and verify**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add MyApp/OnlineGameViewModel.swift
git commit -m "$(cat <<'EOF'
Fix: sync playerNames/playerAvatars from playerSlots in handleSnapshot

playerNames was set once at init and never refreshed. When a disconnected
player was replaced by an AI bot via monitorPresence, the old human name
continued showing in trick messages, the avatar strip, and leaderboard records.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Add `aiSeats` to `startGame()` initial `gameState` write (Bug 4)

**Files:** Modify `MyApp/OnlineGameViewModel.swift` — `startGame()` function (~line 272)

**Root cause:** `startGame()` and `startNextRound()` build their `gameState` dict manually (bypassing `buildGS`). This dict omits `aiSeats`, so every round start writes a `gameState` without `aiSeats`, leaving `gameState` and root `aiSeats` inconsistent until `startBidding()` → `buildGS` restores it. **This also resolves Bug 5** (session VM not writing `gameState.aiSeats`) — by the time the game VM's `startGame()` runs, `self.aiSeats` is already populated from `init(aiSeats:)` (passed from session VM's `aiSeats` at game creation).

- [ ] **Step 1: Add `"aiSeats": aiSeats` to the `gs` dict in `startGame()`**

Find the `gs` dictionary in `startGame()` (currently ends with `"message": "Study your cards..."`):

```swift
let gs: [String: Any] = [
    ...
    "runningScores": runningScores,
    "message": "Study your cards, then the host will start bidding."
]
```

Add `"aiSeats": aiSeats` as the last key:

```swift
let gs: [String: Any] = [
    "phase": OnlineGamePhase.lookingAtCards.rawValue,
    "roundNumber": roundNumber,
    "dealerIndex": dealerIndex,
    "currentActionPlayer": firstBidder,
    "bids": Array(repeating: -1, count: 6),
    "highBid": 0,
    "highBidderIndex": -1,
    "playerHasPassed": Array(repeating: false, count: 6),
    "bidHistory": [] as [[String: Any]],
    "trumpSuit": TrumpSuit.spades.rawValue,
    "calledCard1": "",
    "calledCard2": "",
    "partner1Index": -1,
    "partner2Index": -1,
    "currentTrick": [] as [[String: Any]],
    "currentLeaderIndex": firstBidder,
    "trickNumber": 0,
    "wonPointsPerPlayer": Array(repeating: 0, count: 6),
    "runningScores": runningScores,
    "message": "Study your cards, then the host will start bidding.",
    "aiSeats": aiSeats   // keep gameState consistent with root aiSeats field
]
```

- [ ] **Step 2: Build and verify**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add MyApp/OnlineGameViewModel.swift
git commit -m "$(cat <<'EOF'
Fix: include aiSeats in startGame() gameState write (covers Bug 4 and Bug 5)

startGame() bypasses buildGS and omitted aiSeats, leaving gameState.aiSeats
absent in Firestore for the lookingAtCards window on every round start.
Adding it here also covers the session VM gap (Bug 5) since self.aiSeats is
pre-populated from init(aiSeats:) before startGame() executes.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Fix TOCTOU race in `removePlayerMidGame` with a Firestore transaction (Bug 6)

**Files:** Modify `MyApp/OnlineGameViewModel.swift` — `removePlayerMidGame()` (~line 370)

**Root cause:** The function reads `aiSeats` from Firestore, builds a new array, then calls `updateData`. A concurrent watchdog or `monitorPresence` firing between the read and write overwrites `aiSeats` with a stale snapshot. A Firestore transaction makes the read and write atomic, matching the pattern used by `joinSession`.

Note: Firestore transaction closures must be synchronous — no `async` ops inside. The `removedName` for the table message is read from `playerName(index)` after the transaction, which uses the local `playerNames` array (Task 3 keeps it up-to-date).

- [ ] **Step 1: Rewrite `removePlayerMidGame` with a transaction**

Replace the entire function body:

```swift
func removePlayerMidGame(atIndex index: Int) async {
    guard isHost, index != myPlayerIndex, !aiSeats.contains(index) else { return }
    let db = Firestore.firestore()
    let ref = db.collection("sessions").document(sessionCode)
    let aiNamePool = ["Drew", "Jamie", "Casey", "Morgan", "Riley"]

    do {
        try await db.runTransaction { transaction, errorPointer in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            guard snapshot.exists,
                  let data = snapshot.data(),
                  var slotsData = data["playerSlots"] as? [[String: Any]],
                  index < slotsData.count else {
                errorPointer?.pointee = NSError(
                    domain: "RemovePlayer", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Session or slot not found"])
                return nil
            }
            var currentAISeats = (data["aiSeats"] as? [Any] ?? []).compactMap {
                ($0 as? Int) ?? ($0 as? Int64).map(Int.init)
            }
            guard !currentAISeats.contains(index) else { return nil } // already AI — no-op
            let usedNames = slotsData.compactMap { $0["name"] as? String }
            let aiName = aiNamePool.first { !usedNames.contains($0) } ?? "Bot"
            let removedName = slotsData[safe: index]?["name"] as? String ?? "Player"
            slotsData[index] = ["uid": "AI-\(index)", "name": aiName, "avatar": "🤖", "joined": true]
            currentAISeats.append(index)
            currentAISeats.sort()
            transaction.updateData([
                "playerSlots": slotsData,
                "aiSeats": currentAISeats,
                "gameState.aiSeats": currentAISeats,
                "removedSlot": index,
                "gameState.message": "\(removedName) was removed. AI took over."
            ], forDocument: ref)
            return nil
        }
        let name = playerName(index)
        await publishSystemTableMessage("\(name) was removed. AI took over.")
    } catch {
        ogVMLog.error("[removePlayerMidGame] transaction failed for slot \(index): \(error.localizedDescription)")
    }
}
```

- [ ] **Step 2: Build and verify**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add MyApp/OnlineGameViewModel.swift
git commit -m "$(cat <<'EOF'
Fix: use Firestore transaction in removePlayerMidGame to prevent TOCTOU race

Read-modify-write on aiSeats without a transaction allowed concurrent watchdog
or monitorPresence writes to be silently overwritten. Transaction makes the
slot claim atomic, matching the pattern used by joinSession.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Fix non-cancellation-aware sleep in `processAITurnIfNeeded` (Bug 7)

**Files:** Modify `MyApp/OnlineGameViewModel.swift` — `processAITurnIfNeeded()` (~line 1420)

**Root cause:** When `aiComputeCard` returns nil (empty hand — stale sync lag), the 1s retry sleep uses `try?`, ignoring task cancellation. If `cleanup()` fires during this sleep, execution continues and calls `processAITurnIfNeeded` on a torn-down game. All other sleeps in the file use `do { try await Task.sleep } catch { return }`.

- [ ] **Step 1: Change the empty-hand retry sleep to cancellation-aware**

Find in `processAITurnIfNeeded` (inside `case .playing:`):

```swift
guard let cardId = aiComputeCard(seat: seat) else {
    ogVMLog.error("[AI Playing] seat \(seat) has empty hand — retrying in 1s")
    try? await Task.sleep(nanoseconds: 1_000_000_000)
```

Replace with:

```swift
guard let cardId = aiComputeCard(seat: seat) else {
    ogVMLog.error("[AI Playing] seat \(seat) has empty hand — retrying in 1s")
    do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
```

- [ ] **Step 2: Build and verify**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add MyApp/OnlineGameViewModel.swift
git commit -m "$(cat <<'EOF'
Fix: cancellation-aware sleep in processAITurnIfNeeded empty-hand retry

try? ignored task cancellation, allowing execution to continue after cleanup()
and attempt stale Firestore writes. Consistent with the do/catch pattern used
everywhere else in the file.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Final verification, CLAUDE.md update, and push

**Files:** Modify `MyApp/CLAUDE.md`

- [ ] **Step 1: Full build**

Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Boot simulator if needed and install + launch**

```bash
xcrun simctl boot DA97985A-F7CC-44F6-8281-9DD24C22B978 2>/dev/null; sleep 3 \
  && xcrun simctl install DA97985A-F7CC-44F6-8281-9DD24C22B978 \
     /Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Build/Products/Debug-iphonesimulator/MyApp.app \
  && xcrun simctl launch DA97985A-F7CC-44F6-8281-9DD24C22B978 com.vijaygoyal.theshadyspade
```

Record the PID returned.

- [ ] **Step 3: Add v2.0 Changelog entry to `CLAUDE.md`**

Add a single changelog entry at the top of the v2.0 Changelog section in `/Users/vijaygoyal/MyiOSApp/MyApp/CLAUDE.md` covering all 6 fixes with symptom, root cause, fix, reusable pattern, verification, and changed files. See existing v2.0 entries for the format.

- [ ] **Step 4: Commit CLAUDE.md and push**

```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
doc: update CLAUDE.md with Online multiplayer bug fix changelog

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Self-Review

**Spec coverage:**
- Bug 1 (startGame try?) → Task 1 ✓
- Bug 2 (no host-crash detection) → Task 2 ✓
- Bug 3 (playerNames stale) → Task 3 ✓
- Bug 4 (startGame missing aiSeats) → Task 4 ✓
- Bug 5 (session VM aiSeats) → Covered by Task 4 ✓ (self.aiSeats pre-populated from init)
- Bug 6 (TOCTOU race) → Task 5 ✓
- Bug 7 (try? sleep) → Task 6 ✓

**Placeholder scan:** No TBDs, no "similar to" references, all code shown in full. ✓

**Type consistency:**
- `hostPresenceMonitoringTimer: Timer?` defined in Task 2 Step 1, used in Task 2 Steps 4/3. ✓
- `startHostPresenceMonitoring()` defined in Task 2 Step 4, called in Task 2 Step 5. ✓
- `db.runTransaction` in Task 5 matches `joinSession` pattern in `OnlineSessionViewModel`. ✓
- `ogVMLog` used throughout — already defined at file top. ✓
