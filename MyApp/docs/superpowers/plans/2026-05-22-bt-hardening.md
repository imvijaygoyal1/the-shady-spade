# BT Game Mode Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement 7 targeted hardening changes to the Bluetooth multiplayer game mode — host migration, broadcast reliability with client resync, unified send-failure handling, back-to-back action serialisation, AI empty-hand recovery, crash-safe gameSessionId persistence, and full-state resync for reconnecting clients.

**Architecture:** All changes are confined to `BluetoothGameViewModel.swift` and `BluetoothGameView.swift`. Tasks 1–2 lay a shared property/helper foundation; Tasks 3–8 implement one or two issues each in dependency order (simple issues first, host migration last). No Online, Solo, or P&P code paths are affected. MC creates a full mesh session, so all remaining clients stay connected to each other — migration requires only a single broadcast, not a session teardown.

**Tech Stack:** Swift 5.9, SwiftUI, MultipeerConnectivity, UserDefaults, `@Observable`/`@MainActor`

---

### Task 1: Foundation — new ViewModel properties + cleanup() updates

**Files:**
- Modify: `MyApp/MyApp/BluetoothGameViewModel.swift`

These 8 properties are required by Tasks 3–7. Add them and update `cleanup()` before writing any logic that depends on them.

- [ ] **Step 1: Add new properties after `bidWinnerDismissTask` (line 152)**

Locate:
```swift
    private var bidWinnerDismissTask: Task<Void, Never>?
```

Add immediately after:
```swift
    // MARK: - Host Migration (Issue 1)
    var isMigrating: Bool = false
    private var migrationTimeoutTask: Task<Void, Never>?

    // MARK: - Broadcast Reliability (Issue 2)
    private var pendingResyncPeers: Set<MCPeerID> = []
    private var lastStateReceivedAt: Date = .distantPast
    private var staleStateCheckTask: Task<Void, Never>?

    // MARK: - Action Serialisation (Issue 4)
    private var isProcessingAction = false
    private var pendingActions: [[String: Any]] = []
```

- [ ] **Step 2: Replace the body of cleanup() to cancel/reset all new state**

Find `func cleanup()` (line ~470). Replace its entire body with:

```swift
    func cleanup() {
        turnWatchdogTask?.cancel()
        turnWatchdogTask = nil
        partnerRevealTask?.cancel()
        partnerRevealTask = nil
        bidWinnerDismissTask?.cancel()
        bidWinnerDismissTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        migrationTimeoutTask?.cancel()
        migrationTimeoutTask = nil
        staleStateCheckTask?.cancel()
        staleStateCheckTask = nil
        pendingHostAction = nil
        isReconnecting = false
        isMigrating = false
        isProcessingAction = false
        pendingActions = []
        pendingResyncPeers = []
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        session?.disconnect()
        session = nil
        peerToPlayerIndex = [:]
        playerIndexToPeer = [:]
        sessionState = .idle
        foundSessions = []
        localServer?.stop()
        localServer = nil
        localServerURL = ""
        UserDefaults.standard.removeObject(forKey: "bt_active_game_session_id")
        gameHistorySaved = false
    }
```

- [ ] **Step 3: Build to verify no compile errors**

```bash
cd /Users/vijaygoyal/MyiOSApp && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
cd /Users/vijaygoyal/MyiOSApp && git add MyApp/MyApp/BluetoothGameViewModel.swift && git commit -m "feat(bt): add foundation properties and cleanup() updates for 7 hardening issues"
```

---

### Task 2: Unicast helpers — sendGameState(to:) and sendHand(_:to:)

**Files:**
- Modify: `MyApp/MyApp/BluetoothGameViewModel.swift`

These two helpers are used by Issues 2, 5, and 7. Add them in the `// MARK: - MC Send Helpers` section immediately after the closing `}` of the existing `send(_:to:)` helper (~line 1047).

- [ ] **Step 1: Add sendGameState(to:) and sendHand(_:to:) after send(_:to:)**

Locate the line:
```swift
    private func send(_ dict: [String: Any], to peer: MCPeerID) {
```

After that method's closing `}`, add:

```swift
    private func sendGameState(to peer: MCPeerID) {
        let gs = buildGameStateDict()
        send(["type": "gameState", "state": gs], to: peer)
    }

    private func sendHand(_ hand: [Card], to peer: MCPeerID) {
        let cards = hand.map { ["rank": $0.rank, "suit": $0.suit] as [String: Any] }
        send(["type": "hand", "cards": cards], to: peer)
    }
```

- [ ] **Step 2: Build**

```bash
cd /Users/vijaygoyal/MyiOSApp && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
cd /Users/vijaygoyal/MyiOSApp && git add MyApp/MyApp/BluetoothGameViewModel.swift && git commit -m "feat(bt): add sendGameState(to:) and sendHand(_:to:) unicast helpers"
```

---

### Task 3: Issues 6 + 7 — gameSessionId persistence + reconnect resync

**Files:**
- Modify: `MyApp/MyApp/BluetoothGameViewModel.swift`

**Issue 6:** Write `gameSessionId` to `UserDefaults["bt_active_game_session_id"]` immediately after it is generated in `startHosting()`, so it survives an app crash between `.gameOver` and the Cloud Function HTTP call completing. `cleanup()` already clears it (added in Task 1).

**Issue 7:** When the host's `session(_:peer:didChange:)` fires `.connected` during `.playing`, re-send the full game state plus the peer's hand so they re-sync immediately on reconnect.

- [ ] **Step 1: Persist gameSessionId in startHosting()**

Locate in `startHosting()` (~line 219):
```swift
        gameSessionId = UUID().uuidString
            .filter { $0.isLetter || $0.isNumber }
            .prefix(10)
            .lowercased()
```

Add immediately after:
```swift
        UserDefaults.standard.set(gameSessionId, forKey: "bt_active_game_session_id")
```

- [ ] **Step 2: Resync reconnecting peer in session(_:peer:didChange:) .connected**

In the `.connected` case of `session(_:peer:didChange:)`, find the host path that ends with:
```swift
                    self.send(assignMsg, to: peerID)

                    // Broadcast updated lobby to all
```

Add between the `send(assignMsg…)` call and the lobby broadcast comment:

```swift
                    // Issue 7: mid-game reconnect — send full state + hand immediately
                    if self.sessionState == .playing {
                        self.sendGameState(to: peerID)
                        if nextSlot < self.allHands.count {
                            self.sendHand(self.allHands[nextSlot], to: peerID)
                        }
                    }

```

- [ ] **Step 3: Build**

```bash
cd /Users/vijaygoyal/MyiOSApp && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
cd /Users/vijaygoyal/MyiOSApp && git add MyApp/MyApp/BluetoothGameViewModel.swift && git commit -m "feat(bt): persist gameSessionId to UserDefaults; resync full state on peer reconnect"
```

---

### Task 4: Issues 2 + 3 — broadcast reliability + sendToHost failure

**Files:**
- Modify: `MyApp/MyApp/BluetoothGameViewModel.swift`

**Issue 2 (host side):** `sendToAll` now sends per-peer with one immediate retry; repeat failures land in `pendingResyncPeers` and receive a direct unicast at the start of the next `broadcastGameState` call. **Issue 2 (client side):** non-host clients start a 15-second stale-state check loop when the game begins; if no broadcast was received in 15 seconds they ask the host for a full resync. **Issue 3:** `sendToHost` now uses do/catch on the actual `session.send` call so MC throw errors route to the same retry path as the nil-peer case.

- [ ] **Step 1: Rewrite sendToAll() for per-peer retry and pendingResyncPeers**

Replace the entire body of `sendToAll(_:)`:

```swift
    @discardableResult
    private func sendToAll(_ dict: [String: Any]) -> Bool {
        guard let session, !session.connectedPeers.isEmpty else { return false }
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return false }
        var allSucceeded = true
        for peer in session.connectedPeers {
            do {
                try session.send(data, toPeers: [peer], with: .reliable)
            } catch {
                // Retry once immediately
                do {
                    try session.send(data, toPeers: [peer], with: .reliable)
                } catch {
                    aiLog.error("[sendToAll] retry failed for \(peer.displayName) — queued for next broadcast")
                    pendingResyncPeers.insert(peer)
                    allSucceeded = false
                }
            }
        }
        return allSucceeded
    }
```

- [ ] **Step 2: Drain pendingResyncPeers at the start of broadcastGameState()**

Replace the entire body of `broadcastGameState()`:

```swift
    private func broadcastGameState() {
        guard isHost else { return }
        let gs = buildGameStateDict()
        // Drain peers that missed the previous broadcast
        if !pendingResyncPeers.isEmpty {
            let resyncMsg: [String: Any] = ["type": "gameState", "state": gs]
            for peer in pendingResyncPeers {
                send(resyncMsg, to: peer)
            }
            pendingResyncPeers.removeAll()
        }
        let msg: [String: Any] = ["type": "gameState", "state": gs]
        if !sendToAll(msg) {
            aiLog.warning("[broadcastGameState] send failed for one or more peers — queued for resync")
        }
        applyGameState(gs)
        pushToLocalServer(gs)
    }
```

- [ ] **Step 3: Update lastStateReceivedAt at the start of applyGameState()**

Find the opening of `applyGameState(_ gs:)`:
```swift
    func applyGameState(_ gs: [String: Any]) {
        func i(_ key: String) -> Int {
```

Add `lastStateReceivedAt = Date()` as the very first line of the body, before the `func i` helper:

```swift
    func applyGameState(_ gs: [String: Any]) {
        lastStateReceivedAt = Date()
        func i(_ key: String) -> Int {
```

- [ ] **Step 4: Start 15-second stale check when non-host game begins**

Find where `sessionState = .playing` is set in `applyGameState` (~line 887):
```swift
            if activePhases.contains(newPhase) {
                sessionState = .playing
            }
```

Replace with:
```swift
            if activePhases.contains(newPhase) {
                sessionState = .playing
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
            }
```

- [ ] **Step 5: Add requestFullState case in handleMessage()**

In `handleMessage(_:from:)`, after the `case "lobbyUpdate":` block, before the closing `default:` (or after any other cases you've added), add:

```swift
        case "requestFullState":
            guard isHost else { return }
            sendGameState(to: peer)
```

- [ ] **Step 6: Rewrite sendToHost() for unified failure handling**

Replace the entire body of `sendToHost(_:)` (lines ~1049–1081):

```swift
    private func sendToHost(_ dict: [String: Any]) {
        // Attempt direct send if host peer is mapped and session is live
        if let hostPeer = playerIndexToPeer[0], let session {
            guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
            do {
                try session.send(data, toPeers: [hostPeer], with: .reliable)
                return
            } catch {
                aiLog.error("[sendToHost] send threw: \(error.localizedDescription) — falling through to retry")
            }
        }
        // Nil peer OR send failure — queue and retry up to 3× at 500ms intervals
        guard reconnectTask == nil else { return }
        pendingHostAction = dict
        isReconnecting = true
        reconnectTask = Task { @MainActor in
            for attempt in 1...3 {
                do { try await Task.sleep(nanoseconds: 500_000_000) } catch { break }
                guard !Task.isCancelled else { break }
                if let hostPeer = self.playerIndexToPeer[0],
                   let action = self.pendingHostAction,
                   let session = self.session,
                   let data = try? JSONSerialization.data(withJSONObject: action) {
                    if (try? session.send(data, toPeers: [hostPeer], with: .reliable)) != nil {
                        self.pendingHostAction = nil
                        self.isReconnecting = false
                        self.reconnectTask = nil
                        return
                    }
                }
                if attempt == 3 {
                    aiLog.error("[sendToHost] host still unreachable after 3 retries — action dropped")
                    self.errorMessage = "Lost connection to host. Please rejoin the game."
                    self.pendingHostAction = nil
                    self.isReconnecting = false
                    self.reconnectTask = nil
                }
            }
        }
    }
```

- [ ] **Step 7: Write stale-check interval test**

```bash
cat > /tmp/test_bt_stale_check.swift << 'EOF'
import Foundation

let now = Date()
let recentish = now.addingTimeInterval(-10)
let stale = now.addingTimeInterval(-20)

assert(now.timeIntervalSince(recentish) < 15, "10s ago should not be stale")
assert(now.timeIntervalSince(stale) > 15, "20s ago should be stale")
assert(now.timeIntervalSince(.distantPast) > 15, "distantPast should be stale")
print("✅ stale threshold tests passed")

// Default lastStateReceivedAt = .distantPast should trigger self-heal immediately
let lastReceived = Date.distantPast
assert(Date().timeIntervalSince(lastReceived) > 15, "distantPast triggers self-heal")
print("✅ default lastStateReceivedAt triggers self-heal")

print("All stale-check tests passed.")
EOF
swift /tmp/test_bt_stale_check.swift
```

Expected: `All stale-check tests passed.`

- [ ] **Step 8: Build**

```bash
cd /Users/vijaygoyal/MyiOSApp && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 9: Commit**

```bash
cd /Users/vijaygoyal/MyiOSApp && git add MyApp/MyApp/BluetoothGameViewModel.swift && git commit -m "feat(bt): broadcast reliability, client 15s self-heal, sendToHost unified failure path"
```

---

### Task 5: Issue 4 — action serialisation queue

**Files:**
- Modify: `MyApp/MyApp/BluetoothGameViewModel.swift`

Replace the unguarded `Task { switch action { ... } }` in the `"action"` case with an `enqueueAction`/`drainActionQueue`/`processAction` serial queue. Back-to-back client messages are now processed one at a time, preventing concurrent mutations to the host's mutable game state.

- [ ] **Step 1: Add enqueueAction, drainActionQueue, processAction before // MARK: - Handle Incoming Messages**

Find the comment line:
```swift
    // MARK: - Handle Incoming Messages
```

Add three new private methods immediately before it:

```swift
    // MARK: - Action Queue (Issue 4)

    private func enqueueAction(_ dict: [String: Any]) {
        pendingActions.append(dict)
        drainActionQueue()
    }

    private func drainActionQueue() {
        guard !isProcessingAction, !pendingActions.isEmpty else { return }
        isProcessingAction = true
        let next = pendingActions.removeFirst()
        Task { @MainActor [weak self] in
            await self?.processAction(next)
            self?.isProcessingAction = false
            self?.drainActionQueue()
        }
    }

    private func processAction(_ dict: [String: Any]) async {
        guard let playerIndex = dict["_playerIndex"] as? Int else { return }
        let action = dict["action"] as? String ?? ""
        switch action {
        case "bid":
            let amount = (dict["amount"] as? Int) ?? (dict["amount"] as? Int64).map(Int.init) ?? 0
            guard amount >= 130 && amount <= 250 else { return }
            await processBid(playerIndex: playerIndex, amount: amount)
        case "pass":
            await processPass(playerIndex: playerIndex)
        case "callTrump":
            let suitStr = dict["suit"] as? String ?? TrumpSuit.spades.rawValue
            let suit = TrumpSuit(rawValue: suitStr) ?? .spades
            let c1 = dict["card1"] as? String ?? ""
            let c2 = dict["card2"] as? String ?? ""
            await processCallCards(playerIndex: playerIndex, trump: suit, c1: c1, c2: c2)
        case "playCard":
            let cardId = dict["cardId"] as? String ?? ""
            await processPlayCard(playerIndex: playerIndex, cardId: cardId)
        default:
            break
        }
    }

```

- [ ] **Step 2: Replace the "action" case in handleMessage to use enqueueAction**

Find the `case "action":` block in `handleMessage` (~line 1142). Replace the entire case (from `case "action":` through the closing `}` of the `Task { switch action { ... } }`) with:

```swift
        case "action":
            guard isHost else { return }
            guard let playerIndex = peerToPlayerIndex[peer] else { return }
            let actionId = dict["actionId"] as? String ?? ""
            guard actionId != lastProcessedActionId, !actionId.isEmpty else { return }
            lastProcessedActionId = actionId
            var enriched = dict
            enriched["_playerIndex"] = playerIndex
            enqueueAction(enriched)
```

- [ ] **Step 3: Write serial-drain test**

```bash
cat > /tmp/test_bt_action_queue.swift << 'EOF'
import Foundation

var log: [Int] = []
var isProcessingAction = false
var pendingActions: [Int] = []

func enqueue(_ n: Int) { pendingActions.append(n); drain() }
func drain() {
    guard !isProcessingAction, !pendingActions.isEmpty else { return }
    isProcessingAction = true
    let next = pendingActions.removeFirst()
    log.append(next)
    isProcessingAction = false
    drain()
}

// 3 actions enqueued sequentially — all processed in order
enqueue(1); enqueue(2); enqueue(3)
assert(log == [1, 2, 3], "Expected [1,2,3] got \(log)")
assert(pendingActions.isEmpty, "Queue should be empty after drain")
print("✅ serial drain order test passed")

// Enqueue while processing — deferred until current action completes
log = []; pendingActions = []; isProcessingAction = true
enqueue(10); enqueue(20)
assert(log == [], "Nothing should run while isProcessingAction=true")
assert(pendingActions == [10, 20], "Both should be queued")
isProcessingAction = false; drain()
assert(log == [10, 20], "Expected [10,20] after deferred drain, got \(log)")
print("✅ deferred-when-busy test passed")

print("All action queue tests passed.")
EOF
swift /tmp/test_bt_action_queue.swift
```

Expected: `All action queue tests passed.`

- [ ] **Step 4: Build**

```bash
cd /Users/vijaygoyal/MyiOSApp && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
cd /Users/vijaygoyal/MyiOSApp && git add MyApp/MyApp/BluetoothGameViewModel.swift && git commit -m "feat(bt): serial action queue prevents concurrent host state mutations"
```

---

### Task 6: Issue 5 — AI empty-hand resync

**Files:**
- Modify: `MyApp/MyApp/BluetoothGameViewModel.swift`

When `aiComputeCard` returns `nil` (empty hand) for the third consecutive retry, the host re-broadcasts all 6 hands via `resyncAllHands()`, waits 500ms, and retries once more. The `handResyncAttempted` flag prevents an infinite resync loop.

- [ ] **Step 1: Add resyncAllHands() in // MARK: - Card & Game Helpers**

Find the `// MARK: - Card & Game Helpers` section (~line 1367). Add `resyncAllHands()` before `trickWinnerIndex(trick:)`:

```swift
    private func resyncAllHands() {
        guard isHost else { return }
        for slot in 0..<6 {
            guard !aiSeats.contains(slot),
                  let peer = playerIndexToPeer[slot],
                  slot < allHands.count else { continue }
            sendHand(allHands[slot], to: peer)
        }
    }

```

- [ ] **Step 2: Add retriesRemaining and handResyncAttempted parameters to processAITurnIfNeeded**

Find:
```swift
    private func processAITurnIfNeeded() async {
```

Replace with:
```swift
    private func processAITurnIfNeeded(retriesRemaining: Int = 3, handResyncAttempted: Bool = false) async {
```

- [ ] **Step 3: Replace the empty-hand retry block in case .playing:**

Find the empty-hand guard in the `.playing` case (~line 1310):
```swift
            guard let cardId = aiComputeCard(seat: seat) else {
                aiLog.error("seat=\(seat) aiComputeCard returned nil (empty hand) — retrying in 1s")
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                // Fix 2: state may have changed during the 1s sleep — only recurse if
                // this seat is still the current action player in the playing phase.
                // If a different AI now needs to act, the recovery re-triggers for them.
                guard currentActionPlayer == seat, phase == .playing else {
                    if aiSeats.contains(currentActionPlayer) && phase == .playing {
                        await processAITurnIfNeeded()
                    }
                    return
                }
                await processAITurnIfNeeded()
                return
            }
```

Replace with:
```swift
            guard let cardId = aiComputeCard(seat: seat) else {
                aiLog.error("seat=\(seat) aiComputeCard nil — retriesRemaining=\(retriesRemaining) handResyncAttempted=\(handResyncAttempted)")
                if retriesRemaining > 0 {
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                    guard currentActionPlayer == seat, phase == .playing else {
                        if aiSeats.contains(currentActionPlayer) && phase == .playing {
                            await processAITurnIfNeeded()
                        }
                        return
                    }
                    await processAITurnIfNeeded(retriesRemaining: retriesRemaining - 1, handResyncAttempted: handResyncAttempted)
                } else if !handResyncAttempted {
                    aiLog.warning("[AI] seat=\(seat) empty hand after 3 retries — resyncing all hands")
                    resyncAllHands()
                    do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
                    await processAITurnIfNeeded(handResyncAttempted: true)
                } else {
                    aiLog.error("[AI] seat=\(seat) empty hand persists after resync — giving up to prevent freeze")
                }
                return
            }
```

- [ ] **Step 4: Write retry-countdown test**

```bash
cat > /tmp/test_bt_ai_resync.swift << 'EOF'
import Foundation

var log: [String] = []

func processAITurn(retriesRemaining: Int = 3, handResyncAttempted: Bool = false) {
    let hasCard = false  // simulate persistently empty hand
    guard hasCard else {
        if retriesRemaining > 0 {
            log.append("retry\(retriesRemaining)")
            processAITurn(retriesRemaining: retriesRemaining - 1, handResyncAttempted: handResyncAttempted)
        } else if !handResyncAttempted {
            log.append("resync")
            processAITurn(handResyncAttempted: true)
        } else {
            log.append("gaveUp")
        }
        return
    }
}

processAITurn()
assert(log == ["retry3", "retry2", "retry1", "resync", "gaveUp"], "Expected retry→resync→gaveUp, got \(log)")
print("✅ retry countdown → resync → giveUp test passed")

// Resync succeeds: hand is available on the post-resync call
var log2: [String] = []
func processAITurnWithSuccess(retriesRemaining: Int = 3, handResyncAttempted: Bool = false) {
    let hasCard = handResyncAttempted
    guard !hasCard else { log2.append("played"); return }
    if retriesRemaining > 0 {
        log2.append("retry\(retriesRemaining)")
        processAITurnWithSuccess(retriesRemaining: retriesRemaining - 1, handResyncAttempted: handResyncAttempted)
    } else if !handResyncAttempted {
        log2.append("resync")
        processAITurnWithSuccess(handResyncAttempted: true)
    } else {
        log2.append("gaveUp")
    }
}

processAITurnWithSuccess()
assert(log2 == ["retry3", "retry2", "retry1", "resync", "played"], "Expected resync then play, got \(log2)")
print("✅ resync recovery → plays card test passed")

print("All AI empty-hand resync tests passed.")
EOF
swift /tmp/test_bt_ai_resync.swift
```

Expected: `All AI empty-hand resync tests passed.`

- [ ] **Step 5: Build**

```bash
cd /Users/vijaygoyal/MyiOSApp && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
cd /Users/vijaygoyal/MyiOSApp && git add MyApp/MyApp/BluetoothGameViewModel.swift && git commit -m "feat(bt): AI empty-hand resync — rebroadcast all hands after 3 retries"
```

---

### Task 7: Issue 1 — Host migration protocol

**Files:**
- Modify: `MyApp/MyApp/BluetoothGameViewModel.swift`

When the host crashes, each non-host client independently computes the same new host (lowest non-AI connected slot). The elected client calls `becomeNewHost`, broadcasts `hostMigration` + full game state, and slot 0 becomes AI. All receiving clients remap `playerIndexToPeer[0]` to the new host's MCPeerID — `sendToHost()` call sites need zero changes.

- [ ] **Step 1: Add triggerHostMigration, becomeNewHost, startMigrationTimeout**

Find `// MARK: - Cleanup`. Add a new section immediately before it:

```swift
    // MARK: - Host Migration (Issue 1)

    private func triggerHostMigration() {
        isMigrating = true
        // Remove the disconnected host from peer mappings
        if let hostPeer = playerIndexToPeer[0] {
            peerToPlayerIndex.removeValue(forKey: hostPeer)
            playerIndexToPeer.removeValue(forKey: 0)
        }
        // Slot 0 becomes AI
        if !aiSeats.contains(0) { aiSeats.append(0); aiSeats.sort() }
        // Elect new host: lowest non-AI slot whose peer is still connected
        let connectedSlots = Set(
            (session?.connectedPeers ?? []).compactMap { peerToPlayerIndex[$0] }
        )
        let newHostSlot = (1...5).first { !aiSeats.contains($0) && connectedSlots.contains($0) } ?? -1
        guard newHostSlot >= 0 else {
            aiLog.error("[hostMigration] no viable host — all remaining slots are AI or disconnected")
            isMigrating = false
            return
        }
        if myPlayerIndex == newHostSlot {
            becomeNewHost(newHostSlot: newHostSlot)
        } else {
            startMigrationTimeout(electedSlot: newHostSlot)
        }
    }

    private func becomeNewHost(newHostSlot: Int) {
        isHost = true
        let gs = buildGameStateDict()
        let migrationMsg: [String: Any] = [
            "type": "hostMigration",
            "newHostSlot": newHostSlot,
            "gameState": gs
        ]
        sendToAll(migrationMsg)
        isMigrating = false
        migrationTimeoutTask?.cancel()
        migrationTimeoutTask = nil
        message = "\(playerName(newHostSlot)) is now the host."
        if aiSeats.contains(currentActionPlayer) {
            Task { await processAITurnIfNeeded() }
        }
    }

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

- [ ] **Step 2: Add hostMigration message handler in handleMessage()**

In `handleMessage(_:from:)`, after the `case "requestFullState":` case added in Task 4, add:

```swift
        case "hostMigration":
            // Accept from any peer — old host is gone, standard host-peer verification is skipped
            guard !isHost,
                  let newHostSlot = (dict["newHostSlot"] as? Int) ?? (dict["newHostSlot"] as? Int64).map(Int.init),
                  let gs = dict["gameState"] as? [String: Any] else { return }
            // Remap slot 0 → new host's MCPeerID so sendToHost() needs no changes at call sites
            if let newHostPeer = playerIndexToPeer[newHostSlot] {
                playerIndexToPeer[0] = newHostPeer
                peerToPlayerIndex[newHostPeer] = 0
            }
            if !aiSeats.contains(0) { aiSeats.append(0); aiSeats.sort() }
            applyGameState(gs)
            isMigrating = false
            migrationTimeoutTask?.cancel()
            migrationTimeoutTask = nil
            message = "\(playerName(newHostSlot)) is now the host."
```

- [ ] **Step 3: Trigger migration in session(_:peer:didChange:) .notConnected**

Find the entire `case .notConnected:` block (~lines 1480–1512). Replace it completely:

```swift
            case .notConnected:
                self.pendingPeerInfo.removeValue(forKey: peerID)
                if let playerIdx = self.peerToPlayerIndex[peerID] {
                    // Non-host client detecting host crash: trigger migration instead of error banner
                    if !self.isHost && playerIdx == 0 && self.sessionState == .playing {
                        self.triggerHostMigration()
                    } else {
                        if (self.sessionState == .playing || self.phase != .dealing)
                            && !self.hostEndedGame {
                            self.errorMessage = "\(self.playerName(playerIdx)) disconnected."
                        }
                        if self.isHost {
                            self.peerToPlayerIndex.removeValue(forKey: peerID)
                            self.playerIndexToPeer.removeValue(forKey: playerIdx)
                            // If a human disconnects mid-game, replace with AI so game can continue.
                            if self.phase == .playing || self.phase == .bidding ||
                               self.phase == .calling || self.phase == .lookingAtCards {
                                if !self.aiSeats.contains(playerIdx) {
                                    self.aiSeats.append(playerIdx)
                                    self.aiSeats.sort()
                                    self.broadcastGameState()
                                    // Fix 4: always re-trigger — don't gate on currentActionPlayer == playerIdx.
                                    Task { await self.processAITurnIfNeeded() }
                                }
                            }
                        }
                    }
                }
```

- [ ] **Step 4: Write election determinism test**

```bash
cat > /tmp/test_bt_migration_election.swift << 'EOF'
import Foundation

func electNewHost(aiSeats: [Int], connectedSlots: Set<Int>, excludingSlot: Int? = nil) -> Int {
    return (1...5).first {
        !aiSeats.contains($0) &&
        connectedSlots.contains($0) &&
        $0 != (excludingSlot ?? -1)
    } ?? -1
}

// Basic: lowest non-AI connected slot
assert(electNewHost(aiSeats: [0, 3], connectedSlots: [1, 2, 4, 5]) == 1, "Expected slot 1")
print("✅ basic election → slot 1")

// Slot 1 disconnected: slot 2 becomes host
assert(electNewHost(aiSeats: [0, 3], connectedSlots: [2, 4, 5]) == 2, "Expected slot 2")
print("✅ slot 1 gone → slot 2")

// Re-election after elected slot 1 also crashes — excluding 1
assert(electNewHost(aiSeats: [0, 3], connectedSlots: [2, 4, 5], excludingSlot: 1) == 2, "Expected slot 2 after re-election")
print("✅ re-election excluding crashed elected slot")

// No viable host (all non-zero slots are AI or disconnected)
assert(electNewHost(aiSeats: [0, 2, 3, 4, 5], connectedSlots: []) == -1, "Expected -1")
print("✅ no viable host returns -1")

// Only one human left — they become host
assert(electNewHost(aiSeats: [0, 2, 3, 4, 5], connectedSlots: [1]) == 1, "Expected slot 1 as last human")
print("✅ last human becomes host")

// AI seats never elected
assert(electNewHost(aiSeats: [0, 1, 2, 3], connectedSlots: [1, 2, 4, 5]) == 4, "Expected slot 4 skipping AI slots")
print("✅ AI slots skipped in election")

print("All migration election tests passed.")
EOF
swift /tmp/test_bt_migration_election.swift
```

Expected: `All migration election tests passed.`

- [ ] **Step 5: Build**

```bash
cd /Users/vijaygoyal/MyiOSApp && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
cd /Users/vijaygoyal/MyiOSApp && git add MyApp/MyApp/BluetoothGameViewModel.swift && git commit -m "feat(bt): host migration — deterministic election, full game state transfer, slot 0 becomes AI"
```

---

### Task 8: View — isMigrating overlay + UserDefaults fallback

**Files:**
- Modify: `MyApp/MyApp/BluetoothGameView.swift`

Two view-layer changes: (1) full-screen dim overlay with spinner shown when `game.isMigrating`; (2) UserDefaults fallback in both save paths so a crash between `.gameOver` and the Cloud Function call can still recover the `sessionCode`.

- [ ] **Step 1: Add isMigrating overlay in BluetoothGameView**

Find the existing `isReconnecting` overlay and its animation modifier (~lines 144–157):

```swift
        .overlay(alignment: .top) {
            if game.isReconnecting {
                ...
            }
        }
        .animation(.easeInOut(duration: 0.25), value: game.isReconnecting)
```

Add immediately after `.animation(.easeInOut(duration: 0.25), value: game.isReconnecting)`:

```swift
        .overlay {
            if game.isMigrating {
                Color.black.opacity(0.72)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(1.6)
                            Text("Reconnecting…")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: game.isMigrating)
```

- [ ] **Step 2: Add UserDefaults fallback in saveOnQuit()**

Find in `saveOnQuit()` (~line 254):
```swift
        let capturedCode = game.gameSessionId
```

Replace with:
```swift
        let capturedCode = game.gameSessionId.isEmpty
            ? (UserDefaults.standard.string(forKey: "bt_active_game_session_id") ?? "")
            : game.gameSessionId
```

- [ ] **Step 3: Add UserDefaults fallback in saveBTGameHistory()**

Find in `saveBTGameHistory()` (~line 318):
```swift
        let capturedCode = game.gameSessionId
```

Replace with:
```swift
        let capturedCode = game.gameSessionId.isEmpty
            ? (UserDefaults.standard.string(forKey: "bt_active_game_session_id") ?? "")
            : game.gameSessionId
```

- [ ] **Step 4: Build**

```bash
cd /Users/vijaygoyal/MyiOSApp && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
cd /Users/vijaygoyal/MyiOSApp && git add MyApp/MyApp/BluetoothGameView.swift && git commit -m "feat(bt): isMigrating overlay; UserDefaults fallback for gameSessionId in save paths"
```

---

### Task 9: CLAUDE.md update + final verification

**Files:**
- Modify: `MyApp/CLAUDE.md`

- [ ] **Step 1: Full clean build**

```bash
cd /Users/vijaygoyal/MyiOSApp && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MyApp -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Install and launch on simulator**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl install DA97985A-F7CC-44F6-8281-9DD24C22B978 /Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Build/Products/Debug-iphonesimulator/MyApp.app && xcrun simctl launch DA97985A-F7CC-44F6-8281-9DD24C22B978 com.vijaygoyal.theshadyspade
```

Expected: App launches without crash.

- [ ] **Step 3: Update CLAUDE.md v1.9 changelog**

Add to `v1.9 Changelog` in `/Users/vijaygoyal/MyiOSApp/MyApp/CLAUDE.md`:

```
- [2026-05-22] BT game mode hardening (7 issues) — (1) **Host migration (Issue 1):** when host crashes mid-game, non-host clients detect `.notConnected` for slot 0, each independently elects the lowest non-AI connected slot as new host via `triggerHostMigration()`; elected client calls `becomeNewHost()` which broadcasts `hostMigration` + full game state; all clients remap `playerIndexToPeer[0]` to the new host's MCPeerID (`sendToHost()` call sites unchanged); slot 0 becomes AI; `isMigrating` full-screen overlay shown during 2s election window; 2-second `startMigrationTimeout` handles elected-client-also-crashes case. (2) **Broadcast reliability (Issue 2):** `sendToAll` sends per-peer with one immediate retry; repeat failures land in `pendingResyncPeers` and get a unicast at the start of the next `broadcastGameState` cycle; non-host clients start a 15s stale-state `Task` loop when game begins — if no broadcast received in 15s they send `requestFullState` to host; host handles it with `sendGameState(to:)`. (3) **sendToHost failure (Issue 3):** unified do/catch path — MC `session.send` throws and nil-peer both queue the action in `pendingHostAction` and start the existing 3-attempt 500ms retry. (4) **Action serialisation (Issue 4):** `enqueueAction`/`drainActionQueue`/`processAction` replaces the unguarded `Task { switch }` in `handleMessage "action"` case; back-to-back actions are processed one at a time via `isProcessingAction`/`pendingActions` queue. (5) **AI empty-hand resync (Issue 5):** `processAITurnIfNeeded` gains `retriesRemaining: Int = 3` and `handResyncAttempted: Bool = false` params; after 3 failed retries host calls `resyncAllHands()` (re-sends all 6 hands via `sendHand(_:to:)`), waits 500ms, retries once more; `handResyncAttempted` prevents infinite recursion. (6) **gameSessionId persistence (Issue 6):** written to `UserDefaults["bt_active_game_session_id"]` immediately in `startHosting()`; cleared in `cleanup()`; `saveBTGameHistory()` and `saveOnQuit()` fall back to UserDefaults when `gameSessionId` is empty. (7) **Reconnect resync (Issue 7):** host's `.connected` handler sends `sendGameState(to:)` + `sendHand(_:to:)` to any peer that reconnects during `.playing`. (`BluetoothGameViewModel.swift`, `BluetoothGameView.swift`)
```

- [ ] **Step 4: Commit**

```bash
cd /Users/vijaygoyal/MyiOSApp && git add MyApp/CLAUDE.md && git commit -m "docs: update CLAUDE.md with BT hardening 7-issue changelog"
```

- [ ] **Step 5: Push**

```bash
cd /Users/vijaygoyal/MyiOSApp && git push
```

---

## Self-Review

### Spec coverage

| Issue | Spec requirement | Task(s) |
|---|---|---|
| 1 — Host migration | Detection, election, protocol, `isMigrating` UI, edge case (elected crashes) | 1, 7, 8 |
| 2 — Broadcast reliability | Per-peer retry, `pendingResyncPeers`, client 15s self-heal, `requestFullState` | 1, 4 |
| 3 — Action send failure | `sendToHost` do/catch → unified retry path | 4 |
| 4 — Action serialisation | `enqueueAction`/`drainActionQueue`/`processAction` | 1, 5 |
| 5 — AI empty-hand resync | `resyncAllHands()`, `retriesRemaining`, `handResyncAttempted` | 2, 6 |
| 6 — gameSessionId persistence | UserDefaults write/clear, view fallback | 1, 3, 8 |
| 7 — Reconnect resync | `sendGameState(to:)` + `sendHand(_:to:)` in `.connected` | 2, 3 |
| 8 — Rate limiter (dropped) | Not implemented per spec | — |

### Placeholder scan

No TBD, TODO, "fill in", or "similar to task N" patterns. All code blocks are complete and self-contained.

### Type consistency

- `sendGameState(to: MCPeerID)` — defined Task 2; called in Task 3 (reconnect), Task 4 (`requestFullState` handler)
- `sendHand(_ hand: [Card], to: MCPeerID)` — defined Task 2; called in Task 3 (reconnect), Task 6 (`resyncAllHands`)
- `resyncAllHands()` — defined Task 6; called from `processAITurnIfNeeded` in Task 6
- `triggerHostMigration()` — defined Task 7; called from `.notConnected` in Task 7
- `becomeNewHost(newHostSlot: Int)` — defined Task 7; called from `triggerHostMigration` and `startMigrationTimeout`
- `startMigrationTimeout(electedSlot: Int)` — defined Task 7; called from `triggerHostMigration` and recursively
- `isMigrating: Bool` — defined Task 1; set in Task 7 migration methods; cleared in Task 1 `cleanup()`; overlaid in Task 8
- `migrationTimeoutTask` — defined Task 1; used in Task 7; cancelled in Task 1 `cleanup()`
- `pendingResyncPeers: Set<MCPeerID>` — defined Task 1; written in Task 4 `sendToAll`; drained in Task 4 `broadcastGameState`; cleared in Task 1 `cleanup()`
- `isProcessingAction`, `pendingActions` — defined Task 1; used in Task 5; reset in Task 1 `cleanup()`
- `staleStateCheckTask` — defined Task 1; started in Task 4 `applyGameState`; cancelled in Task 1 `cleanup()`
- `lastStateReceivedAt: Date` — defined Task 1; updated in Task 4 `applyGameState`
- `processAITurnIfNeeded(retriesRemaining:handResyncAttempted:)` — signature changed Task 6; all existing call sites use default params, no call site changes needed

### Spec-specific checks

- **"Toast displayed via existing `message` property"** — `message = "\(playerName(newHostSlot)) is now the host."` set in `becomeNewHost` and `hostMigration` handler ✅
- **"`isMigrating` dismissed on `cleanup()`"** — `cleanup()` in Task 1 sets `isMigrating = false` ✅
- **"New host calls `processAITurnIfNeeded()` if slot 0's AI turn"** — `becomeNewHost` calls `Task { await processAITurnIfNeeded() }` when `aiSeats.contains(currentActionPlayer)` ✅
- **"`sendToHost()` call sites — zero changes"** — `playerIndexToPeer[0]` remapping in `hostMigration` handler makes this transparent ✅
- **"`applyGameState()` called by `hostMigration` handler exactly as today"** — Task 7 Step 2 calls `applyGameState(gs)` ✅
- **"No changes to BluetoothSessionView.swift"** — not modified in any task ✅
