# BT Game Mode Hardening — Design Spec
**Date:** 2026-05-22  
**Status:** Approved  
**Scope:** `BluetoothGameViewModel.swift`, `BluetoothGameView.swift`, `BluetoothSessionView.swift`

---

## Overview

Seven targeted hardening changes to the Bluetooth multiplayer game mode, anchored by full host-migration support. All changes are confined to the BT layer — no Online, Solo, or P&P paths are affected.

---

## 1. Host Migration (Issue 1)

### Goal
When the host's device crashes mid-game, the remaining players continue playing automatically. Slot 0 becomes an AI. A new host is elected in under 3 seconds.

### Key Insight
MC creates a full mesh session — all 5 remaining clients are already connected to each other. No session teardown or re-browsing is needed. Migration is a single broadcast round-trip.

### Detection
In `session(_:peer:didChange:)`, when a peer transitions to `.notConnected`:
- Check `playerIndexToPeer[0] == peer && sessionState == .playing`
- If true: trigger migration on this client

### Election
Each client independently computes the new host:
```
newHostSlot = (1...5).first { slot in
    !aiSeats.contains(slot) &&
    peerToPlayerIndex.values.contains(slot)  // peer still connected
}
```
All clients compute the same result deterministically from shared `aiSeats` + `peerToPlayerIndex` data. No coordination message needed.

### Migration Protocol

**Elected client (new host):**
1. Sets `isHost = true`
2. Adds slot 0 to `aiSeats`
3. Broadcasts:
```json
{
  "type": "hostMigration",
  "newHostSlot": N,
  "gameState": { /* full current game state */ }
}
```

**All clients (on receiving `hostMigration`):**
1. Remap `playerIndexToPeer[0]` to the new host's MCPeerID — `sendToHost()` requires zero changes
2. Apply the embedded full game state via existing `applyGameState()`
3. Set `isMigrating = false`
4. Display toast: "[PlayerName] is now the host." via existing `message` property

**New host additionally:**
- Calls `processAITurnIfNeeded()` if it is now slot 0's (AI) turn

### UI
- New `isMigrating: Bool` property on `BluetoothGameViewModel`
- When `true`: full-screen dim overlay + `ProgressView` spinner + "Reconnecting…" label, overlaid on existing game view
- Dismissed immediately on `hostMigration` message receipt or on `cleanup()`
- Toast displayed via existing `message` string (auto-clears after 3s)

### Edge Case — Elected Client Also Crashes
- Non-elected clients start a 2-second `Task.sleep` after detecting host disconnect
- If `hostMigration` is received before timeout: cancel the task, apply migration
- If timeout fires: recompute election excluding the failed elected slot, retry

### New ViewModel Properties
```swift
var isMigrating: Bool = false
private var migrationTimeoutTask: Task<Void, Never>?
```

### New Message Type
`"hostMigration"` — host-originated, carries `newHostSlot: Int` and embedded `gameState` dict. Accepted from any peer (since the old host is gone, host-peer verification is skipped for this message type only).

---

## 2. Broadcast Reliability + Client Resync (Issue 2)

### Goal
Failed `broadcastGameState()` sends no longer silently desync clients.

### Host-Side Retry
`sendToAll()` catches per-peer send throws. For each failed peer:
1. Retry once immediately (direct unicast)
2. If retry also fails: add to `pendingResyncPeers: Set<MCPeerID>`
3. On next `broadcastGameState()`, peers in `pendingResyncPeers` receive a direct unicast of full state before being removed from the set

### Client-Side Self-Healing
- New `lastStateReceivedAt: Date` property on clients, updated on every `applyGameState()` call
- A background `Task` checks every 15 seconds during active phases
- If `Date.now - lastStateReceivedAt > 15s`: sends `{"type": "requestFullState"}` to host
- Host handles `"requestFullState"` by unicasting current full game state to that peer

### New ViewModel Properties
```swift
private var pendingResyncPeers: Set<MCPeerID> = []
private var lastStateReceivedAt: Date = .distantPast
private var staleStateCheckTask: Task<Void, Never>?
```

`staleStateCheckTask` starts on non-host clients when `sessionState` transitions to `.playing`. Cancelled in `cleanup()`.

---

## 3. Action Send Failure Handling (Issue 3)

### Goal
`sendToHost()` catch all send failures, not just `playerIndexToPeer[0] == nil`.

### Change
Replace `try?` with `do/catch` in the send path of `sendToHost()`. Any thrown error routes the action dict into `pendingHostAction` and starts the existing 3-attempt retry task — identical to the nil-peer path. One unified failure handling path for all send errors.

```swift
// Before
try? session.send(data, toPeers: [hostPeer], with: .reliable)

// After
do {
    try session.send(data, toPeers: [hostPeer], with: .reliable)
} catch {
    pendingHostAction = dict
    startReconnectRetry()
}
```

---

## 4. Back-to-Back Action Serialisation (Issue 4)

### Goal
Prevent two concurrent client actions from racing on the host's mutable state.

### Design
Add a serial action queue on the host, mirroring the existing `isProcessingAI` pattern:

```swift
private var isProcessingAction = false
private var pendingActions: [[String: Any]] = []
```

`handleMessage` (the `"action"` case) enqueues the dict rather than dispatching immediately. A drain function pops and processes one action at a time:

```swift
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
```

`processAction()` is the extracted common body of the existing `processBid` / `processPass` / `processCallCards` / `processPlayCard` switch, called with the action dict and source peer. No behaviour change — just serialised execution.

---

## 5. AI Empty-Hand Resync (Issue 5)

### Goal
When an AI seat's hand is empty after 3 retries, recover instead of freezing.

### Design
After the third failed attempt in `processAITurnIfNeeded()`, before logging the error and returning:
1. Host re-broadcasts all 6 hands — one direct `hand` message per human peer (same format as initial deal), and re-populates `allHands[seat]` locally from its own authoritative copy
2. Waits 500ms
3. Calls `processAITurnIfNeeded()` once more with a `isHandResync: Bool = true` flag to prevent infinite recursion

The host always holds `allHands` authoritatively — this is purely re-sending data already in memory.

---

## 6. `gameSessionId` Persistence (Issue 6)

### Goal
Prevent stat double-write when app crashes after `.gameOver` but before the Cloud Function HTTP request completes.

### Design
- `UserDefaults` key: `"bt_active_game_session_id"`
- Write: immediately after generating `gameSessionId` in `startHosting()`
- Clear: unconditionally in `cleanup()` — `LeaderboardService`'s pending queue already holds the sessionCode inside `PendingGameRecord`, so clearing UserDefaults at cleanup time is safe
- Fallback: in `saveBTGameHistory()` and `saveOnQuit()`, if `game.gameSessionId.isEmpty`, read from `UserDefaults` before passing to `recordGame(sessionCode:)`

---

## 7. Full-State Resync for Reconnecting Clients (Issue 7)

### Goal
A client that was backgrounded or briefly disconnected gets back in sync immediately on reconnect.

### Design
In `session(_:peer:didChange:)` on the host, add a `.connected` case for active game phases:

```swift
if sessionState == .playing,
   let slot = peerToPlayerIndex[peer] {
    // Re-send full game state to reconnecting peer
    sendGameState(to: peer)
    // Re-send their hand
    sendHand(allHands[slot], to: peer)
}
```

`sendGameState(to:)` and `sendHand(_:to:)` are extracted helpers from existing broadcast/deal logic — unicast variants of the existing `sendToAll` / `session.send` calls.

---

## Issue 8 — Rate Limiter (Dropped)

`lastActionSentAt` reset on app relaunch is a non-issue: the MC session is dead after app termination, and the player must rejoin before taking any action. The rate limiter is always in a valid initial state at session start.

---

## New Message Types Summary

| Type | Direction | Purpose |
|---|---|---|
| `hostMigration` | any→all | Announces new host + carries full game state |
| `requestFullState` | client→host | Client requests full state resync |
| `fullState` | host→client | Host unicasts full state to one desynced peer |

---

## Files Changed

| File | Changes |
|---|---|
| `BluetoothGameViewModel.swift` | Migration protocol, action queue, broadcast retry, send failure catch, AI resync, gameSessionId persistence, reconnect resync |
| `BluetoothGameView.swift` | `isMigrating` overlay, gameSessionId UserDefaults fallback in save paths |

---

## What Does NOT Change

- `BluetoothSessionView.swift` — lobby flow unchanged
- Online, Solo, P&P game modes — zero changes
- Message types for `gameState`, `hand`, `assignSlot`, `action`, `hostEndedGame` — formats unchanged
- `sendToHost()` call sites — zero changes (remapping `playerIndexToPeer[0]` makes this transparent)
- `applyGameState()` — called by `hostMigration` handler exactly as today

---

## Success Criteria

- Host crash mid-game → remaining players continue within 3 seconds, slot 0 is AI, toast shown
- Failed broadcast → affected client resyncs on next snapshot or within 15s via self-heal
- Rapid back-to-back client actions → processed serially, no state corruption
- AI hand empty after 3 retries → hands resynced and AI plays successfully
- App crash after game over → leaderboard record not duplicated on relaunch
- Backgrounded client reconnects → receives full state + hand immediately
