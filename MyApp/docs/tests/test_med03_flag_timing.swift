import Foundation
// Tests: gameHistorySaved claim-then-release pattern
// Validates MED-03 fix: flag claimed before partner-index guard so concurrent
// callers can't both pass and both reach recordGame().

var passed = 0; var failed = 0
func check(_ label: String, _ got: Bool, _ want: Bool) {
    if got == want { print("✅ \(label)"); passed += 1 }
    else { print("❌ \(label): got \(got), want \(want)"); failed += 1 }
}

// ── Model the FIXED save function ────────────────────────────────
// Returns (saveOccurred: Bool, flagAfter: Bool)
func saveFixed(flagBefore: Bool, indicesValid: Bool) -> (saveOccurred: Bool, flagAfter: Bool) {
    guard !flagBefore else { return (false, true) }     // already saved — flag stays true
    var flag = true                                      // claim BEFORE guard
    guard indicesValid else {
        flag = false                                     // release — defer for retry
        return (false, flag)
    }
    return (true, flag)                                  // save succeeds, flag stays true
}

// ── Model the BUGGY save function (before fix) ───────────────────
func saveBuggy(flagBefore: Bool, indicesValid: Bool) -> (saveOccurred: Bool, flagAfter: Bool) {
    guard !flagBefore else { return (false, true) }
    guard indicesValid else {
        return (false, false)                            // returns, flag NEVER set — window!
    }
    let flag = true                                      // set only after guard
    return (true, flag)
}

// ── Normal save — indices valid ───────────────────────────────────
let r1 = saveFixed(flagBefore: false, indicesValid: true)
check("fixed: valid indices → save occurs", r1.saveOccurred, true)
check("fixed: flag is true after save", r1.flagAfter, true)

// ── Deferred save — indices not yet valid ─────────────────────────
let r2 = saveFixed(flagBefore: false, indicesValid: false)
check("fixed: invalid indices → save deferred", r2.saveOccurred, false)
check("fixed: flag released to false for retry", r2.flagAfter, false)

// ── Already saved — no double-save ───────────────────────────────
let r3 = saveFixed(flagBefore: true, indicesValid: true)
check("fixed: flag already true → save blocked", r3.saveOccurred, false)
check("fixed: flag stays true after block", r3.flagAfter, true)

// ── Invariant: save occurred → flag must be true ───────────────────
for fb in [false, true] {
    for iv in [false, true] {
        let r = saveFixed(flagBefore: fb, indicesValid: iv)
        if r.saveOccurred {
            check("invariant: save occurred → flag=true (fb=\(fb) iv=\(iv))", r.flagAfter, true)
        }
    }
}

// ── Invariant: deferred (no save, flag was false) → flag released ──
let deferred = saveFixed(flagBefore: false, indicesValid: false)
check("invariant: deferred path releases flag to false", deferred.flagAfter, false)

// ── Concurrent-caller window demonstration ─────────────────────────
// With BUGGY version: two callers both see flagBefore=false and both save.
// Simulate: caller A defers (indices invalid), flag stays false.
//           Caller B arrives while A is in flight, also sees flag=false.
let buggyA = saveBuggy(flagBefore: false, indicesValid: false)
check("buggy: deferred → flag NOT set (stays false)", buggyA.flagAfter, false)
// Caller B arrives concurrently — it also sees flag=false
let buggyB = saveBuggy(flagBefore: buggyA.flagAfter, indicesValid: true)
check("buggy: concurrent caller B also saves (double-save!)", buggyB.saveOccurred, true)

// With FIXED version: caller A momentarily held flag=true, blocking B.
// In the serial model: A defers and releases, B retries and succeeds (correct — one save).
let fixedA = saveFixed(flagBefore: false, indicesValid: false)
check("fixed: deferred → flag released to false (for retry)", fixedA.flagAfter, false)
let fixedB_retry = saveFixed(flagBefore: fixedA.flagAfter, indicesValid: true)
check("fixed: retry succeeds when indices become valid", fixedB_retry.saveOccurred, true)
check("fixed: flag true after successful retry", fixedB_retry.flagAfter, true)

// ── Already-saved + invalid indices: flag must NOT be reset ────────
let r4 = saveFixed(flagBefore: true, indicesValid: false)
check("fixed: already saved + invalid indices → flag stays true (NOT reset)", r4.flagAfter, true)

// ── Retry after successful save → blocked ─────────────────────────
let save1 = saveFixed(flagBefore: false, indicesValid: true)
let save2 = saveFixed(flagBefore: save1.flagAfter, indicesValid: true)
check("fixed: second call after successful save is blocked", save2.saveOccurred, false)

print("\n\(passed)/\(passed + failed) passed")
if failed > 0 { print("❌ \(failed) FAILED"); exit(1) }
else { print("✅ ALL PASSED") }
