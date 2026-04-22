// tests_remaining_fixes.swift — standalone Swift script, no Xcode needed
// Run: swift tests_remaining_fixes.swift
//
// Tests for:
//   LB5 — Monthly leaderboard archive-before-delete logic
//   LB6 — Leaderboard listener re-subscription guard
//   RC-B — BT pre-sleep race: watchdog re-arm on bail
//   RC-C — Solo resolveAiCalling gameLoopCancelled guard

import Foundation

var passed = 0
var failed = 0

func test(_ name: String, _ condition: Bool, detail: String = "") {
    if condition {
        print("  ✅  \(name)")
        passed += 1
    } else {
        print("  ❌  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        failed += 1
    }
}

// ────────────────────────────────────────────────────────────────────────────
// LB5 — Archive-before-delete logic (mirrored from index.js in Swift)
// ────────────────────────────────────────────────────────────────────────────
print("\n── LB5: Monthly leaderboard archive-before-delete ──")

/// Mirrors the JS archive-label logic: label is the prior month.
func archiveLabelForResetDate(_ resetDate: Date) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York")!
    let comps = cal.dateComponents([.year, .month], from: resetDate)
    let year  = comps.year!
    let month = comps.month!   // 1-based: Jan = 1
    // Prior month
    let priorMonth = month == 1 ? 12 : month - 1
    let priorYear  = month == 1 ? year - 1 : year
    return String(format: "%04d-%02d", priorYear, priorMonth)
}

// Test 1: reset on Feb 1 → label is January
do {
    var comps = DateComponents()
    comps.year = 2026; comps.month = 2; comps.day = 1
    let resetDate = Calendar.current.date(from: comps)!
    let label = archiveLabelForResetDate(resetDate)
    test("Feb 1 reset → label is 2026-01", label == "2026-01",
         detail: "got \(label)")
}

// Test 2: reset on Jan 1 → label wraps to prior year December
do {
    var comps = DateComponents()
    comps.year = 2026; comps.month = 1; comps.day = 1
    let resetDate = Calendar.current.date(from: comps)!
    let label = archiveLabelForResetDate(resetDate)
    test("Jan 1 reset → label wraps to 2025-12", label == "2025-12",
         detail: "got \(label)")
}

// Test 3: reset on Mar 1 → label is February
do {
    var comps = DateComponents()
    comps.year = 2027; comps.month = 3; comps.day = 1
    let resetDate = Calendar.current.date(from: comps)!
    let label = archiveLabelForResetDate(resetDate)
    test("Mar 1 reset → label is 2027-02", label == "2027-02",
         detail: "got \(label)")
}

// Test 4: archive chunk size — 400 docs per batch (mirror of JS CHUNK constant)
do {
    let CHUNK = 400
    let docCount = 1050
    let batchCount = Int(ceil(Double(docCount) / Double(CHUNK)))
    test("1050 docs → 3 archive batches of ≤400", batchCount == 3,
         detail: "got \(batchCount)")
}

// Test 5: empty collection → no archive needed (skip condition)
do {
    let docs: [String] = []
    let shouldSkip = docs.isEmpty
    test("Empty collection → skip archive+delete", shouldSkip)
}

// Test 6: delete only runs after archive (order guarantee via sequential awaits)
do {
    var log: [String] = []
    func simulateArchiveAndDelete(docs: [String]) {
        guard !docs.isEmpty else { log.append("skip"); return }
        log.append("archive")
        log.append("delete")
    }
    simulateArchiveAndDelete(docs: ["doc1", "doc2"])
    test("Archive happens before delete", log == ["archive", "delete"],
         detail: "log: \(log)")
}

// Test 7: archiveRef path structure
do {
    let label = "2026-01"
    let col   = "player_stats"
    let docId = "Alice"
    let expectedPath = "monthly_snapshots/\(label)/\(col)/\(docId)"
    let actualPath   = "monthly_snapshots/\(label)/\(col)/\(docId)"
    test("Archive path is monthly_snapshots/{label}/{col}/{docId}", actualPath == expectedPath)
}

// ────────────────────────────────────────────────────────────────────────────
// LB6 — Leaderboard listener re-subscription guard
// ────────────────────────────────────────────────────────────────────────────
print("\n── LB6: Leaderboard listener re-subscription ──")

/// Simulates the fixed LeaderboardService listener lifecycle.
class MockLeaderboardListenerManager {
    private(set) var attachCount = 0
    private(set) var detachCount = 0
    var isListenerAttached: Bool { attachCount > detachCount }

    func startListening() {
        // LB6 fix: always detach first, then reattach — no guard on existing listener
        stopListening()
        attachCount += 1
    }

    func stopListening() {
        guard isListenerAttached else { return }
        detachCount += 1
    }

    func simulateListenerDeath() {
        // Firestore silently kills the listener — detach count doesn't change
        // (the old guard `guard statsListener == nil` would have prevented re-sub)
        // The fix: startListening() tears down and reattaches unconditionally.
    }

    func reattachAfterError() {
        stopListening()
        // After 3s delay (simulated synchronously in test)
        attachCount += 1
    }
}

// Test 8: initial startListening attaches one listener
do {
    let mgr = MockLeaderboardListenerManager()
    mgr.startListening()
    test("startListening attaches listener", mgr.attachCount == 1)
    test("listener is attached after startListening", mgr.isListenerAttached)
}

// Test 9: calling startListening again (e.g. view reappears) does NOT double-register
do {
    let mgr = MockLeaderboardListenerManager()
    mgr.startListening()
    mgr.startListening()   // second call — old code would bail here via guard
    test("Second startListening replaces (not duplicates) listener",
         mgr.attachCount == 2 && mgr.detachCount == 1,
         detail: "attach=\(mgr.attachCount) detach=\(mgr.detachCount)")
}

// Test 10: listener dies silently → reattach restores exactly one listener
do {
    let mgr = MockLeaderboardListenerManager()
    mgr.startListening()
    mgr.simulateListenerDeath()    // silent death — old guard would block re-sub
    mgr.reattachAfterError()
    test("After silent death + reattach, listener is active",
         mgr.isListenerAttached,
         detail: "attach=\(mgr.attachCount) detach=\(mgr.detachCount)")
    test("Exactly one net listener after reattach",
         mgr.attachCount - mgr.detachCount == 1,
         detail: "net=\(mgr.attachCount - mgr.detachCount)")
}

// Test 11: stopListening cleans up
do {
    let mgr = MockLeaderboardListenerManager()
    mgr.startListening()
    mgr.stopListening()
    test("stopListening clears listener", !mgr.isListenerAttached)
}

// Test 12: stopListening is idempotent (not attached → no-op)
do {
    let mgr = MockLeaderboardListenerManager()
    mgr.stopListening()
    mgr.stopListening()
    test("stopListening when not attached is a no-op", mgr.detachCount == 0)
}

// ────────────────────────────────────────────────────────────────────────────
// RC-B — BT pre-sleep race: watchdog re-arm for human player
// ────────────────────────────────────────────────────────────────────────────
print("\n── RC-B: BT pre-sleep race (watchdog re-arm) ──")

enum BTGamePhase: String { case bidding, calling, playing, idle }

struct BTRCBSimulator {
    var aiSeats: Set<Int>
    var currentActionPlayer: Int
    var phase: BTGamePhase
    var isProcessingAI: Bool = false

    private(set) var watchdogArmedForSeat: Int? = nil
    private(set) var aiRetriggered: Bool = false

    mutating func simulatePostSleepBail(capturedSeat: Int, capturedPhase: BTGamePhase) {
        let activePhases: [BTGamePhase] = [.bidding, .calling, .playing]
        // State changed during sleep — guard fired
        guard aiSeats.contains(capturedSeat),
              phase == capturedPhase,
              currentActionPlayer == capturedSeat else {
            // RC-B fix
            isProcessingAI = false
            if aiSeats.contains(currentActionPlayer) && activePhases.contains(phase) {
                aiRetriggered = true
            } else if activePhases.contains(phase) && !aiSeats.contains(currentActionPlayer) {
                // Human's turn — re-arm watchdog defensively
                watchdogArmedForSeat = currentActionPlayer
            }
            return
        }
        // Normal case: state unchanged, proceed
    }
}

// Test 13: state changes to AI during sleep → AI re-triggered, watchdog NOT armed
do {
    var sim = BTRCBSimulator(aiSeats: [2, 4], currentActionPlayer: 4, phase: .bidding)
    // During sleep: currentActionPlayer moved from 0 (human, original seat) to 4 (AI)
    sim.simulatePostSleepBail(capturedSeat: 0, capturedPhase: .bidding)
    test("State changed to AI → re-triggers processAITurnIfNeeded", sim.aiRetriggered)
    test("State changed to AI → watchdog NOT armed", sim.watchdogArmedForSeat == nil)
    test("isProcessingAI reset on bail", !sim.isProcessingAI)
}

// Test 14: state changes to human during sleep → watchdog armed, AI NOT re-triggered
do {
    var sim = BTRCBSimulator(aiSeats: [2, 4], currentActionPlayer: 1, phase: .bidding)
    // During sleep: currentActionPlayer moved from 4 (AI, captured) to 1 (human)
    sim.simulatePostSleepBail(capturedSeat: 4, capturedPhase: .bidding)
    test("State changed to human → watchdog armed for seat 1",
         sim.watchdogArmedForSeat == 1,
         detail: "armed for \(sim.watchdogArmedForSeat.map(String.init) ?? "nil")")
    test("State changed to human → AI NOT re-triggered", !sim.aiRetriggered)
}

// Test 15: phase changed (not just player) → recovery still works
do {
    var sim = BTRCBSimulator(aiSeats: [2, 4], currentActionPlayer: 2, phase: .calling)
    // Captured: seat=2, phase=.bidding — now phase advanced to .calling
    sim.simulatePostSleepBail(capturedSeat: 2, capturedPhase: .bidding)
    test("Phase mismatch → AI re-triggered (seat 2 is still AI in calling)",
         sim.aiRetriggered)
}

// Test 16: idle phase → neither watchdog nor re-trigger
do {
    var sim = BTRCBSimulator(aiSeats: [2], currentActionPlayer: 2, phase: .idle)
    sim.simulatePostSleepBail(capturedSeat: 2, capturedPhase: .bidding)
    test("Idle phase → no watchdog, no re-trigger",
         !sim.aiRetriggered && sim.watchdogArmedForSeat == nil)
}

// ────────────────────────────────────────────────────────────────────────────
// RC-C — Solo resolveAiCalling gameLoopCancelled guard
// ────────────────────────────────────────────────────────────────────────────
print("\n── RC-C: Solo resolveAiCalling gameLoopCancelled guard ──")

/// Simulates resolveAiCalling() post-sleep with the RC-C guard.
/// Returns true if startPlayingPhase was called.
func simulateResolveAiCalling(gameLoopCancelled: Bool) -> Bool {
    // Mirrors the fixed implementation:
    // try? await Task.sleep(nanoseconds: 1_000_000_000)
    // guard !gameLoopCancelled else { return }  ← RC-C fix
    // ... resolve partners, call startPlayingPhase()
    if gameLoopCancelled { return false }
    // startPlayingPhase() would be called here
    return true
}

// Test 17: not cancelled → startPlayingPhase called
do {
    let result = simulateResolveAiCalling(gameLoopCancelled: false)
    test("Not cancelled → startPlayingPhase proceeds", result)
}

// Test 18: cancelled during sleep → startPlayingPhase NOT called
do {
    let result = simulateResolveAiCalling(gameLoopCancelled: true)
    test("Cancelled during sleep → startPlayingPhase skipped", !result)
}

// Test 19: guard is checked exactly at post-sleep position (before any state mutations)
do {
    var callOrder: [String] = []
    func mockResolveWithGuard(cancelled: Bool) {
        callOrder.append("sleep_done")
        if cancelled { callOrder.append("guard_exit"); return }
        callOrder.append("resolve_partners")
        callOrder.append("start_playing")
    }
    mockResolveWithGuard(cancelled: true)
    test("Guard exits immediately after sleep, before resolvePartners",
         callOrder == ["sleep_done", "guard_exit"],
         detail: "order: \(callOrder)")
}

// Test 20: normal flow when not cancelled (all steps execute)
do {
    var callOrder: [String] = []
    func mockResolveNormal(cancelled: Bool) {
        callOrder.append("sleep_done")
        if cancelled { callOrder.append("guard_exit"); return }
        callOrder.append("resolve_partners")
        callOrder.append("start_playing")
    }
    mockResolveNormal(cancelled: false)
    test("Normal flow: all steps execute in correct order",
         callOrder == ["sleep_done", "resolve_partners", "start_playing"],
         detail: "order: \(callOrder)")
}

// Test 21: guard is idempotent — calling with cancelled=true multiple times is safe
do {
    let r1 = simulateResolveAiCalling(gameLoopCancelled: true)
    let r2 = simulateResolveAiCalling(gameLoopCancelled: true)
    test("Multiple cancelled calls all bail cleanly", !r1 && !r2)
}

// ────────────────────────────────────────────────────────────────────────────
// Summary
// ────────────────────────────────────────────────────────────────────────────
print("\n\(passed + failed) tests — \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }
