# App Store Review Prompts — Design Spec
**Date:** 2026-06-12

---

## Goal

Request an App Store review after the player has completed enough rounds to form a genuine opinion of the game.

---

## Trigger Rule

- Fire `requestReview()` when `completedRoundCount` transitions to exactly **3**
- Counts completed rounds across **all modes** (Solo, Online, Bluetooth, Pass & Play)
- Guided first-game rounds do **not** count
- Apple's own rate-limiting (max 3 prompts/year per device) governs all subsequent calls — from the app's side, we fire once at round 3 only

---

## Section 1 — Tracking

`@AppStorage("completedRoundCount") var completedRoundCount: Int = 0`

- Persisted in `UserDefaults` under key `"completedRoundCount"`
- `@AppStorage` is shared automatically across all views reading the same key — no singleton or manager needed
- Incremented once per completed round at the round-end call site in each game view
- Never decremented or reset

---

## Section 2 — Integration

### Each of the three game views adds:
```swift
@Environment(\.requestReview) private var requestReview
@AppStorage("completedRoundCount") private var completedRoundCount = 0
```

### At each round-end call site, after the leaderboard save call:
```swift
completedRoundCount += 1
if completedRoundCount == 3 {
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(1))
        requestReview()
    }
}
```

The 1-second delay allows the Round Complete screen to render fully before the system dialog appears.

### Call sites

| File | Location |
|---|---|
| `ComputerGameView.swift` | `finishAfterCompletedRound()` — after `saveRoundToLeaderboardIfNeeded` |
| `OnlineGameView.swift` | Round Complete state transition — fires for **all** players (host and non-host), not tied to the leaderboard save path |
| `BluetoothGameView.swift` | Round Complete state transition — fires for **all** players (host and non-host), not tied to the leaderboard save path |

**Note on Online/Bluetooth:** The leaderboard save is host-only, but the review counter should increment for every player who completes a round regardless of role. Find the point where the Round Complete screen first appears (state change to round-complete phase) in each view and place the increment + trigger there, guarded so it only fires once per round (not on view re-renders).

### Guided first-game exclusion
The existing `guard !guidedFirstGame else { return }` already gates the leaderboard save path. Wrap the counter increment inside the same guard (or place it immediately after the guard passes) so guided rounds are excluded.

---

## Unchanged

- No new files needed
- No changes to `LeaderboardService`, game logic, scoring, or history
- StoreKit is already available (iOS 17 deployment target); no new package dependency needed

---

## Files Changed

| File | Change |
|---|---|
| `ComputerGameView.swift` | Add `@Environment(\.requestReview)`, `@AppStorage("completedRoundCount")`, increment + trigger in `finishAfterCompletedRound()` |
| `OnlineGameView.swift` | Same — at host-side round-end save call site |
| `BluetoothGameView.swift` | Same — at host-side round-end save call site |

---

## Success Criteria

- After completing exactly 3 rounds (any mode, any session), the system review dialog appears ~1 second after the Round Complete screen
- Guided first-game rounds do not count toward the trigger
- Subsequent rounds do not re-trigger the prompt from the app side (Apple handles recurrence)
- No crash or hang if `requestReview()` is called while the app is backgrounded
