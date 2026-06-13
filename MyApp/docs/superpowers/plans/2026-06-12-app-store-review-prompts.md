# App Store Review Prompts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Request an App Store review after the player completes their 3rd round across any game mode.

**Architecture:** `@AppStorage("completedRoundCount")` tracks rounds across all game views. `@Environment(\.requestReview)` fires once when the count hits 3, with a 1-second delay so Round Complete renders first. Guided first-game rounds are excluded. StoreKit's own rate-limiter (3 prompts/year) handles recurrence.

**Tech Stack:** Swift, SwiftUI, iOS 17, StoreKit (`@Environment(\.requestReview)`)

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `MyApp/ComputerGameView.swift` | Modify | Add review counter + trigger in `finishAfterCompletedRound()` |
| `MyApp/OnlineGameView.swift` | Modify | Add review counter + trigger in `.onChange(of: game.phase)` |
| `MyApp/BluetoothGameView.swift` | Modify | Add review counter + trigger in `.onChange(of: game.phase)` |

No new files. StoreKit is already available at iOS 17.

---

### Task 1: Add review trigger to `ComputerGameView.swift`

**Files:**
- Modify: `MyApp/MyApp/ComputerGameView.swift`

- [ ] **Step 1: Add `import StoreKit` if not already present**

Check if `import StoreKit` exists at the top of `ComputerGameView.swift`:
```bash
grep -n "import StoreKit" MyApp/ComputerGameView.swift
```

If not present, add it after the existing imports at the top of the file:
```swift
import StoreKit
```

- [ ] **Step 2: Add `@Environment(\.requestReview)` and `@AppStorage` to `ComputerGameView`**

Find the block of `@State` and `@Environment` declarations at the top of `struct ComputerGameView: View` (around lines 7–27). Add after `@Environment(\.modelContext)`:

```swift
    @Environment(\.requestReview) private var requestReview
    @AppStorage("completedRoundCount") private var completedRoundCount = 0
```

- [ ] **Step 3: Add the review trigger inside `finishAfterCompletedRound()`**

Find `finishAfterCompletedRound()`:
```swift
    private func finishAfterCompletedRound() {
        let (hr, updated) = appendCurrentRoundIfNeeded()
        let mode = currentGameMode()
        saveRoundToLeaderboardIfNeeded(hr, mode: mode)
        soloGameSaved = true
```

Add the review increment immediately after `saveRoundToLeaderboardIfNeeded`:
```swift
    private func finishAfterCompletedRound() {
        let (hr, updated) = appendCurrentRoundIfNeeded()
        let mode = currentGameMode()
        saveRoundToLeaderboardIfNeeded(hr, mode: mode)
        if !guidedFirstGame {
            completedRoundCount += 1
            if completedRoundCount == 3 {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    requestReview()
                }
            }
        }
        soloGameSaved = true
```

- [ ] **Step 4: Build to verify**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp
xcodebuild -quiet -project MyApp.xcodeproj -scheme MyApp -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MyApp/ComputerGameView.swift
git commit -m "Add App Store review prompt trigger to solo game (round 3)"
```

---

### Task 2: Add review trigger to `OnlineGameView.swift`

**Files:**
- Modify: `MyApp/MyApp/OnlineGameView.swift`

- [ ] **Step 1: Add `import StoreKit` if not already present**

```bash
grep -n "import StoreKit" MyApp/OnlineGameView.swift
```

If not found, add after existing imports.

- [ ] **Step 2: Add `@Environment(\.requestReview)` and `@AppStorage` to `OnlineGameView`**

Find the state vars block at the top of `struct OnlineGameView: View` (around lines 10–20). Add after `@Environment(\.modelContext)`:

```swift
    @Environment(\.requestReview) private var requestReview
    @AppStorage("completedRoundCount") private var completedRoundCount = 0
```

- [ ] **Step 3: Add the review trigger inside `.onChange(of: game.phase)`**

Find:
```swift
        .onChange(of: game.phase) { _, newPhase in
            if newPhase == .roundComplete {
                saveLatestCompletedRoundToLeaderboardIfNeeded()
                HapticManager.success()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showRoundResultBanner = true
                }
```

Replace with:
```swift
        .onChange(of: game.phase) { _, newPhase in
            if newPhase == .roundComplete {
                saveLatestCompletedRoundToLeaderboardIfNeeded()
                completedRoundCount += 1
                if completedRoundCount == 3 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        requestReview()
                    }
                }
                HapticManager.success()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showRoundResultBanner = true
                }
```

Note: No `guidedFirstGame` guard needed — Online mode has no guided tutorial path.

- [ ] **Step 4: Build to verify**

```bash
xcodebuild -quiet -project MyApp.xcodeproj -scheme MyApp -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MyApp/OnlineGameView.swift
git commit -m "Add App Store review prompt trigger to online game (round 3)"
```

---

### Task 3: Add review trigger to `BluetoothGameView.swift`

**Files:**
- Modify: `MyApp/MyApp/BluetoothGameView.swift`

- [ ] **Step 1: Add `import StoreKit` if not already present**

```bash
grep -n "import StoreKit" MyApp/BluetoothGameView.swift
```

If not found, add after existing imports.

- [ ] **Step 2: Add `@Environment(\.requestReview)` and `@AppStorage` to `BluetoothGameView`**

Find the state vars block at the top of `struct BluetoothGameView: View` (around lines 10–18). Add after `@Environment(\.modelContext)`:

```swift
    @Environment(\.requestReview) private var requestReview
    @AppStorage("completedRoundCount") private var completedRoundCount = 0
```

- [ ] **Step 3: Add the review trigger inside `.onChange(of: game.phase)`**

Find:
```swift
        .onChange(of: game.phase) { _, newPhase in
            if newPhase == .roundComplete {
                saveLatestCompletedRoundToLeaderboardIfNeeded()
                HapticManager.success()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showRoundResultBanner = true
                }
```

Replace with:
```swift
        .onChange(of: game.phase) { _, newPhase in
            if newPhase == .roundComplete {
                saveLatestCompletedRoundToLeaderboardIfNeeded()
                completedRoundCount += 1
                if completedRoundCount == 3 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        requestReview()
                    }
                }
                HapticManager.success()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showRoundResultBanner = true
                }
```

- [ ] **Step 4: Build to verify**

```bash
xcodebuild -quiet -project MyApp.xcodeproj -scheme MyApp -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MyApp/BluetoothGameView.swift
git commit -m "Add App Store review prompt trigger to Bluetooth game (round 3)"
```

---

### Task 4: Install, smoke test, and update CLAUDE.md

- [ ] **Step 1: Install on simulator**

```bash
xcrun simctl install booted \
  $(xcodebuild -project MyApp.xcodeproj -scheme MyApp -configuration Debug \
    -destination "generic/platform=iOS Simulator" \
    -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO \
    -showBuildSettings 2>/dev/null | grep " BUILT_PRODUCTS_DIR" | head -1 | awk '{print $3}')/MyApp.app
xcrun simctl launch booted com.vijaygoyal.theshadyspade
```

- [ ] **Step 2: Smoke test checklist**

- [ ] Reset counter: `xcrun simctl spawn booted defaults delete com.vijaygoyal.theshadyspade completedRoundCount`
- [ ] Complete 2 Solo rounds — no review prompt
- [ ] Complete 3rd Solo round — review prompt appears ~1 second after Round Complete screen
- [ ] Complete further rounds — no additional prompts from our side (Apple's limiter controls recurrence)
- [ ] Verify guided first-game round does NOT increment counter (play guided mode, check that `completedRoundCount` stays at its pre-guided value via `xcrun simctl spawn booted defaults read com.vijaygoyal.theshadyspade completedRoundCount`)

- [ ] **Step 3: Update `CLAUDE.md`**

Add a changelog entry to the `## v2.0 Changelog` section in `CLAUDE.md`:

```
- [2026-06-12] Add App Store review prompt after 3rd completed round — Symptom/motivation: app had no review prompt, reducing visibility in the App Store. Root cause: `SKStoreReviewController`/`requestReview` not implemented. Fix: added `@Environment(\.requestReview)` and `@AppStorage("completedRoundCount")` to `ComputerGameView`, `OnlineGameView`, and `BluetoothGameView`; counter increments at round-end for all players (host and non-host); fires `requestReview()` with a 1-second delay when count reaches 3; guided first-game rounds excluded via existing `!guidedFirstGame` guard in solo; Online/Bluetooth have no guided mode so no exclusion needed; Apple's rate-limiter (3 prompts/year) controls recurrence after the initial trigger. Reusable pattern: `@AppStorage("completedRoundCount")` is a shared key across all game views; do not reset it; only increment at genuine round-complete transitions. Verification: build passed; installed on simulator; completed 3 rounds and confirmed review dialog appeared ~1 second after Round Complete screen. (`ComputerGameView.swift`, `OnlineGameView.swift`, `BluetoothGameView.swift`, `CLAUDE.md`)
```

- [ ] **Step 4: Final commit**

```bash
git add MyApp/CLAUDE.md
git commit -m "Update CLAUDE.md — App Store review prompt after 3rd round"
```
