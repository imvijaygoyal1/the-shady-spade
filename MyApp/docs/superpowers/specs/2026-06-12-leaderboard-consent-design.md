# Leaderboard Consent Flow — Design Spec
**Date:** 2026-06-12  
**Trigger:** Apple rejection, Guideline 5.1.2 — app must obtain user consent prior to uploading scores to global leaderboard  
**Submission ID:** d7f08e68-21b1-4870-89ca-8c3a12d0edb5 (v1.10, reviewed on iPad Air 11-inch M3)

---

## Problem

`LeaderboardService.recordGame()` fires automatically at round end with no consent check. The `ScoreSaveStatusRow` disclosure text ("Completed rounds may upload avatar names…") is shown *after* the upload starts — Apple requires consent *before* any upload occurs.

---

## Goals

1. Obtain explicit user consent before any leaderboard data is uploaded.
2. Handle both new users (never seen a consent prompt) and existing users (already past onboarding).
3. Allow users to change their preference at any time via Settings.
4. Show a clear nudge in Round Complete when saving is disabled.

---

## Section 1 — Data Model

### `LeaderboardConsentState` enum
```swift
enum LeaderboardConsentState: String {
    case undecided  // default — no decision yet
    case granted    // user allowed uploads
    case denied     // user blocked uploads
}
```

Persisted as `String` via `UserDefaults` key `"leaderboardConsentState"`.

### `LeaderboardConsentManager` singleton
- `var state: LeaderboardConsentState` — reads/writes UserDefaults
- `var isGranted: Bool` — `state == .granted`
- `func grant()` — sets state to `.granted`
- `func deny()` — sets state to `.denied`

### `LeaderboardService.recordGame()` guard
Add at the top of `recordGame()`, before any queue or network logic:
```swift
guard LeaderboardConsentManager.shared.isGranted else {
    if LeaderboardConsentManager.shared.state == .denied {
        scoreSaveStatus = .disabled
    }
    lbLog.info("recordGame skipped — leaderboard consent not granted (state=\(LeaderboardConsentManager.shared.state.rawValue))")
    return
}
```
Setting `scoreSaveStatus = .disabled` when denied ensures `ScoreSaveStatusRow` shows the nudge pill. When state is `.undecided` (pre-save gate hasn't fired yet), the status stays `.idle` so no pill appears before the consent sheet is shown.

**Migration:** Existing users who completed setup will have `state == .undecided` automatically (the key doesn't exist in their UserDefaults). No migration step needed — the pre-save gate handles them.

---

## Section 2 — `LeaderboardConsentSheet` Component

A single reusable SwiftUI view used in all three consent entry points.

### Layout
- Presented as `.sheet` with `presentationDetents([.medium])`
- Works on both iPhone and iPad (iPad Air 11-inch is the review device)

### Contents
| Element | Detail |
|---|---|
| Header icon | `shield.fill` SF Symbol, themed accent color |
| Title | "Global Leaderboard" |
| Body | "When you complete a round, The Shady Spade can upload your player name, avatar, score, bid results, and game mode to the global leaderboard. No account is required and no other personal information is collected." |
| Privacy link | `Link("Privacy Policy", destination: URL("https://shadyspade.vijaygoyal.org/privacy")!)` |
| Allow button | Primary `ClayButtonStyle`, label "Allow", calls `LeaderboardConsentManager.shared.grant()` |
| Don't Allow button | Secondary/outlined style, label "Don't Allow", calls `LeaderboardConsentManager.shared.deny()` |

### Callbacks
```swift
LeaderboardConsentSheet(
    onAllow: { /* grant + optional immediate save */ },
    onDeny:  { /* deny + skip save */ }
)
```

Both buttons dismiss the sheet. The sheet accepts an `interactiveDismissDisabled: Bool` parameter (defaults to `false`):
- **SplashView**: pass `true` — user must make an explicit choice to proceed
- **Pre-save gate**: pass `false` — swipe-to-dismiss is allowed, but treated as **deny** (calls `deny()` via `onDismissWithoutChoice` callback), so the behaviour is identical to tapping "Don't Allow"

---

## Section 3 — Integration Points

### A) New users — SplashView
- Add a consent step at the end of the existing `SplashView` flow
- `LeaderboardConsentSheet` is shown as the final step before `hasCompletedSetup = true` is written
- Both buttons are the only exits — no skipping
- `.interactiveDismissDisabled(true)` prevents swipe-to-dismiss

### B) Existing users — pre-save gate (3 call sites)
Files: `ComputerGameView.swift`, `OnlineGameView.swift`, `BluetoothGameView.swift`

Each has a `saveRoundToLeaderboardIfNeeded(...)` function. Before calling it, add:

```swift
if LeaderboardConsentManager.shared.state == .undecided {
    pendingRoundForConsent = round     // store round to save after consent
    showingConsentSheet = true
    return
}
saveRoundToLeaderboardIfNeeded(round, mode: mode)
```

`LeaderboardConsentSheet` callbacks:
- `onAllow`: `grant()` → call `saveRoundToLeaderboardIfNeeded(pendingRound, mode:)`
- `onDeny`: `deny()` → skip save, show nudge state

### C) Settings toggle
New LEADERBOARD section in `SettingsView`:

```
LEADERBOARD
[Toggle] Save rounds to global leaderboard
```

- Toggle reads/writes `LeaderboardConsentManager.shared.state` (`.granted` ↔ `.denied`)
- No re-prompt when toggling on — being in Settings and reading the toggle label is sufficient
- If `state == .undecided`, toggle shows as OFF (treat undecided as off for display)

### D) Round Complete nudge
Add a `.disabled` case to `ScoreSaveStatus` enum:

```swift
case disabled  // consent denied
```

When `LeaderboardConsentManager.shared.state == .denied`, pass `.disabled` to `ScoreSaveStatusRow`.

`ScoreSaveStatusRow` renders `.disabled` as a muted pill:
- Icon: `hand.raised.slash.fill` SF Symbol
- Text: "Leaderboard saving is off · Enable in Settings"
- No upload disclosure text
- Muted secondary color (no tint border)

---

## Unchanged

- `LeaderboardService` queue, retry, offline sync, and Firestore write logic — untouched
- `ScoreSaveStatus` existing cases (`.saving`, `.saved`, `.pending`, `.failed`, `.handledByHost`, `.notSaved`) — untouched
- Online/Bluetooth host-only save logic — untouched (host's consent state governs)
- Leaderboard read/display path — untouched (viewing the leaderboard requires no consent)

---

## Files Changed

| File | Change |
|---|---|
| `LeaderboardConsentManager.swift` | New file — enum + singleton |
| `LeaderboardConsentSheet.swift` | New file — reusable consent sheet UI |
| `LeaderboardService.swift` | Add `isGranted` guard at top of `recordGame()` |
| `SplashView.swift` | Add consent step before completing setup |
| `ComputerGameView.swift` | Add pre-save consent gate |
| `OnlineGameView.swift` | Add pre-save consent gate |
| `BluetoothGameView.swift` | Add pre-save consent gate |
| `SettingsView.swift` | Add LEADERBOARD toggle section |
| `Styles.swift` | Add `.disabled` case to `ScoreSaveStatus` + render in `ScoreSaveStatusRow` |

---

## Success Criteria

- Apple reviewer on iPad Air M3 sees the consent sheet before any leaderboard upload fires
- Tapping "Allow" → round saves normally
- Tapping "Don't Allow" → round not saved, nudge shown, no future uploads until Settings toggle is flipped
- Existing users see the consent sheet at round end (pre-save gate), not at app launch
- Settings toggle accurately reflects and controls consent state
