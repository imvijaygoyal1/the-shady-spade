import Foundation
// Tests: completedRounds dedup guard — contains(where:) vs last check
// Validates CRIT-02 fix: prevents out-of-order duplicate round appends

struct Round { let roundNumber: Int }

// NEW guard (the fix)
func shouldAppendNew(_ completedRounds: [Round], _ roundNumber: Int) -> Bool {
    return !completedRounds.contains(where: { $0.roundNumber == roundNumber })
}

// OLD guard (the bug)
func shouldAppendOld(_ completedRounds: [Round], _ roundNumber: Int) -> Bool {
    return completedRounds.last?.roundNumber != roundNumber
}

var passed = 0; var failed = 0
func check(_ label: String, _ got: Bool, _ want: Bool) {
    if got == want { print("✅ \(label)"); passed += 1 }
    else { print("❌ \(label): got \(got), want \(want)"); failed += 1 }
}

// ── Basic cases (both guards agree) ──────────────────────────────
check("empty list allows append",
    shouldAppendNew([], 1), true)

check("new round appended after existing",
    shouldAppendNew([Round(roundNumber: 1)], 2), true)

check("consecutive dup blocked by new guard",
    shouldAppendNew([Round(roundNumber: 1)], 1), false)

check("consecutive dup also blocked by old guard",
    shouldAppendOld([Round(roundNumber: 1)], 1), false)

// ── The bug: out-of-order duplicate ──────────────────────────────
// Scenario: rounds arrive as [1, 3] then round 1 replayed (reconnect)
let outOfOrder: [Round] = [Round(roundNumber: 1), Round(roundNumber: 3)]

check("NEW guard blocks out-of-order dup (round 1 re-delivered after round 3)",
    shouldAppendNew(outOfOrder, 1), false)

// Old guard: last=3, 3 != 1 → "append" — the bug
check("OLD guard INCORRECTLY allows out-of-order dup (the bug)",
    shouldAppendOld(outOfOrder, 1), true)

// ── Deeper history ────────────────────────────────────────────────
let rounds1to4: [Round] = [1, 2, 3, 4].map(Round.init)

check("NEW blocks re-delivery of round 2 when history is [1,2,3,4]",
    shouldAppendNew(rounds1to4, 2), false)

check("OLD allows re-delivery of round 2 when history is [1,2,3,4] (bug)",
    shouldAppendOld(rounds1to4, 2), true)

check("NEW allows legitimate round 5",
    shouldAppendNew(rounds1to4, 5), true)

check("OLD also allows round 5",
    shouldAppendOld(rounds1to4, 5), true)

// ── Multi-reconnect simulation ────────────────────────────────────
// Delivery sequence: [1, 1, 2, 1] — round 1 replayed twice
var newRounds: [Round] = []; var newCount = 0
var oldRounds: [Round] = []; var oldCount = 0

for rn in [1, 1, 2, 1] {
    if shouldAppendNew(newRounds, rn) { newRounds.append(Round(roundNumber: rn)); newCount += 1 }
    if shouldAppendOld(oldRounds, rn) { oldRounds.append(Round(roundNumber: rn)); oldCount += 1 }
}

check("NEW: delivery [1,1,2,1] → 2 unique rounds appended",
    newCount == 2, true)
check("NEW: final rounds are [1, 2]",
    newRounds.map(\.roundNumber) == [1, 2], true)
check("OLD: delivery [1,1,2,1] → 3 rounds appended (duplicates slip through)",
    oldCount == 3, true)
check("OLD: final rounds are [1, 2, 1] — duplicate present",
    oldRounds.map(\.roundNumber) == [1, 2, 1], true)

// ── First-element edge case ────────────────────────────────────────
check("NEW: single element, same round number — blocked",
    shouldAppendNew([Round(roundNumber: 7)], 7), false)
check("NEW: single element, different round — allowed",
    shouldAppendNew([Round(roundNumber: 7)], 8), true)
check("OLD: single element, same round number — blocked (agrees)",
    shouldAppendOld([Round(roundNumber: 7)], 7), false)

print("\n\(passed)/\(passed + failed) passed")
if failed > 0 { print("❌ \(failed) FAILED"); exit(1) }
else { print("✅ ALL PASSED") }
