# Leaderboard Consent Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add explicit opt-in consent for leaderboard uploads to satisfy Apple Guideline 5.1.2.

**Architecture:** A `LeaderboardConsentManager` singleton (persisted to UserDefaults) gates all uploads. New users see a consent sheet at the end of `SplashView`; existing users see it just before their first leaderboard save. A Settings toggle allows changing the choice at any time. Denied state shows a nudge pill in Round Complete.

**Tech Stack:** Swift, SwiftUI, iOS 17, `@Observable`, `UserDefaults`

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `MyApp/LeaderboardConsentManager.swift` | Create | Enum + `@Observable` singleton for consent state |
| `MyApp/LeaderboardConsentSheet.swift` | Create | Reusable bottom-sheet consent UI |
| `MyApp/Styles.swift` | Modify | Add `.disabled` case to `ScoreSaveStatus`; render nudge pill in `ScoreSaveStatusRow` |
| `MyApp/LeaderboardService.swift` | Modify | Add consent guard at top of `recordGame()` |
| `MyApp/SplashView.swift` | Modify | Present consent sheet after DeckAndDealPage before calling `onComplete` |
| `MyApp/ComputerGameView.swift` | Modify | Add consent gate before `saveRoundToLeaderboardIfNeeded` |
| `MyApp/OnlineGameView.swift` | Modify | Add consent gate before `saveLatestCompletedRoundToLeaderboardIfNeeded` |
| `MyApp/BluetoothGameView.swift` | Modify | Add consent gate before `saveLatestCompletedRoundToLeaderboardIfNeeded` |
| `MyApp/SettingsView.swift` | Modify | Add LEADERBOARD section with opt-in toggle |

---

### Task 1: Create `LeaderboardConsentManager.swift`

**Files:**
- Create: `MyApp/MyApp/LeaderboardConsentManager.swift`

- [ ] **Step 1: Create the file**

```swift
import Foundation
import Observation

enum LeaderboardConsentState: String {
    case undecided
    case granted
    case denied
}

@Observable
@MainActor
final class LeaderboardConsentManager {
    static let shared = LeaderboardConsentManager()

    private let key = "leaderboardConsentState"

    private(set) var state: LeaderboardConsentState = .undecided

    private init() {
        if let raw = UserDefaults.standard.string(forKey: key),
           let s = LeaderboardConsentState(rawValue: raw) {
            state = s
        }
    }

    var isGranted: Bool { state == .granted }

    func grant() {
        state = .granted
        UserDefaults.standard.set(state.rawValue, forKey: key)
    }

    func deny() {
        state = .denied
        UserDefaults.standard.set(state.rawValue, forKey: key)
    }
}
```

- [ ] **Step 2: Add the file to the Xcode project**

New Swift files must be registered in `project.pbxproj` to be compiled. Open Xcode → right-click the `MyApp` group in the Project Navigator → "Add Files to 'MyApp'" → select `LeaderboardConsentManager.swift` → ensure "Add to target: MyApp" is checked → Add.

Verify it appears in the Compile Sources build phase: Xcode → MyApp target → Build Phases → Compile Sources → confirm `LeaderboardConsentManager.swift` is listed.

- [ ] **Step 3: Verify the file compiles**

```bash
cd /Users/vijaygoyal/MyiOSApp/MyApp
xcodebuild -quiet -project MyApp.xcodeproj -scheme MyApp -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MyApp/LeaderboardConsentManager.swift MyApp/MyApp.xcodeproj/project.pbxproj
git commit -m "Add LeaderboardConsentManager — consent state enum and observable singleton"
```

---

### Task 2: Add `.disabled` case to `ScoreSaveStatus` and render nudge pill

**Files:**
- Modify: `MyApp/MyApp/Styles.swift` (lines 12-20 for the enum, lines 491-576 for `ScoreSaveStatusRow`)

- [ ] **Step 1: Add `.disabled` case to the `ScoreSaveStatus` enum**

In `Styles.swift`, find:
```swift
enum ScoreSaveStatus: Equatable {
    case idle
    case saving
    case saved
    case pending        // queued locally, will sync when online
    case notSaved(String)
    case handledByHost(String)
    case failed(String)
}
```

Replace with:
```swift
enum ScoreSaveStatus: Equatable {
    case idle
    case saving
    case saved
    case pending        // queued locally, will sync when online
    case notSaved(String)
    case handledByHost(String)
    case failed(String)
    case disabled       // leaderboard consent denied
}
```

- [ ] **Step 2: Render `.disabled` in `ScoreSaveStatusRow`**

In `ScoreSaveStatusRow.body`, find the `switch status {` block and add the `.disabled` case before the closing `}`:

```swift
case .disabled:
    statusPill(tint: .secondary, showsDisclosure: false) {
        Image(systemName: "hand.raised.slash.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.secondary)
        statusText("Leaderboard saving is off · Enable in Settings", color: .secondary)
    }
```

- [ ] **Step 3: Build to verify no switch exhaustiveness errors**

```bash
xcodebuild -quiet -project MyApp.xcodeproj -scheme MyApp -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MyApp/Styles.swift
git commit -m "Add ScoreSaveStatus.disabled case and nudge pill to ScoreSaveStatusRow"
```

---

### Task 3: Add consent guard to `LeaderboardService.recordGame()`

**Files:**
- Modify: `MyApp/MyApp/LeaderboardService.swift` (around line 352)

- [ ] **Step 1: Insert the guard after the opening of `recordGame`**

In `LeaderboardService.swift`, find the start of `recordGame`:
```swift
    func recordGame(
        gameMode: String,
        playerNames: [String],
        finalScores: [Int],
        winnerIndex: Int,
        aiSeats: [Int] = [],
        rounds: [HistoryRound],
        sessionCode: String = ""
    ) async {
        lbLog.info("recordGame called mode=\(gameMode) names=\(playerNames.count) rounds=\(rounds.count) winner=\(winnerIndex)")
        guard playerNames.count == 6 else {
```

Add the consent guard immediately after the opening log line and before the existing `guard playerNames.count == 6` guard:

```swift
    func recordGame(
        gameMode: String,
        playerNames: [String],
        finalScores: [Int],
        winnerIndex: Int,
        aiSeats: [Int] = [],
        rounds: [HistoryRound],
        sessionCode: String = ""
    ) async {
        lbLog.info("recordGame called mode=\(gameMode) names=\(playerNames.count) rounds=\(rounds.count) winner=\(winnerIndex)")
        guard LeaderboardConsentManager.shared.isGranted else {
            if LeaderboardConsentManager.shared.state == .denied {
                scoreSaveStatus = .disabled
            }
            lbLog.info("recordGame skipped — consent not granted (state=\(LeaderboardConsentManager.shared.state.rawValue))")
            return
        }
        guard playerNames.count == 6 else {
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -quiet -project MyApp.xcodeproj -scheme MyApp -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add MyApp/LeaderboardService.swift
git commit -m "Gate LeaderboardService.recordGame on leaderboard consent"
```

---

### Task 4: Create `LeaderboardConsentSheet.swift`

**Files:**
- Create: `MyApp/MyApp/LeaderboardConsentSheet.swift`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

struct LeaderboardConsentSheet: View {
    var onAllow: () -> Void
    var onDeny: () -> Void
    var disableInteractiveDismiss: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var choiceMade = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(ThemeManager.shared.colours.accentColor)
                    .padding(.top, 32)

                Text("Global Leaderboard")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.textPrimary)

                Text("When you complete a round, The Shady Spade can upload your player name, avatar, score, bid results, and game mode to the global leaderboard. No account is required and no other personal information is collected.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Comic.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                Link("Privacy Policy", destination: URL(string: "https://shadyspade.vijaygoyal.org/privacy")!)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(ThemeManager.shared.colours.accentColor)
            }
            .padding(.horizontal, 28)

            Spacer().frame(height: 32)

            VStack(spacing: 12) {
                Button("Allow") {
                    choiceMade = true
                    LeaderboardConsentManager.shared.grant()
                    dismiss()
                    onAllow()
                }
                .font(.system(size: 17, weight: .black, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .buttonStyle(ComicButtonStyle(
                    bg: Comic.yellow,
                    fg: Comic.black,
                    borderColor: Comic.black
                ))

                Button("Don't Allow") {
                    choiceMade = true
                    LeaderboardConsentManager.shared.deny()
                    dismiss()
                    onDeny()
                }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .buttonStyle(ComicButtonStyle(
                    bg: Comic.containerBG,
                    fg: Comic.textSecondary,
                    borderColor: Comic.containerBorder
                ))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
        }
        .background(Comic.bg)
        .interactiveDismissDisabled(disableInteractiveDismiss)
        .onDisappear {
            if !choiceMade {
                LeaderboardConsentManager.shared.deny()
                onDeny()
            }
        }
    }
}
```

- [ ] **Step 2: Add the file to the Xcode project**

Open Xcode → right-click the `MyApp` group → "Add Files to 'MyApp'" → select `LeaderboardConsentSheet.swift` → ensure "Add to target: MyApp" is checked → Add. Verify it appears in Build Phases → Compile Sources.

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -quiet -project MyApp.xcodeproj -scheme MyApp -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MyApp/LeaderboardConsentSheet.swift MyApp/MyApp.xcodeproj/project.pbxproj
git commit -m "Add reusable LeaderboardConsentSheet view"
```

---

### Task 5: Add consent step to `SplashView.swift`

**Files:**
- Modify: `MyApp/MyApp/SplashView.swift`

The `DeckAndDealPage` currently calls `onComplete` directly (which sets `hasCompletedSetup = true`). We intercept this: `DeckAndDealPage` now calls a local handler that shows the consent sheet, and both sheet buttons call `onComplete`.

- [ ] **Step 1: Add `showingConsentSheet` state and sheet modifier to `SplashView`**

In `SplashView`, find:
```swift
struct SplashView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    var onComplete: () -> Void

    enum Page { case splash, playerSetup, deckAndDeal }
    @State private var page: Page = .splash
    @State private var savedNames: [String] = (1...6).map { "Player \($0)" }

    var body: some View {
```

Replace with:
```swift
struct SplashView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    var onComplete: () -> Void

    enum Page { case splash, playerSetup, deckAndDeal }
    @State private var page: Page = .splash
    @State private var savedNames: [String] = (1...6).map { "Player \($0)" }
    @State private var showingConsentSheet = false

    var body: some View {
```

- [ ] **Step 2: Change `DeckAndDealPage`'s `onComplete` to show the sheet**

Find:
```swift
            case .deckAndDeal:
                DeckAndDealPage(playerNames: savedNames, onComplete: onComplete)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .opacity))
```

Replace with:
```swift
            case .deckAndDeal:
                DeckAndDealPage(playerNames: savedNames, onComplete: {
                    showingConsentSheet = true
                })
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .opacity))
```

- [ ] **Step 3: Add the sheet modifier to the `ZStack` closing**

Find the closing of the `ZStack` + `.animation(...)`:
```swift
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: page)
    }
}
```

Replace with:
```swift
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: page)
        .sheet(isPresented: $showingConsentSheet) {
            LeaderboardConsentSheet(
                onAllow: { onComplete() },
                onDeny:  { onComplete() },
                disableInteractiveDismiss: true
            )
            .presentationDetents([.medium])
        }
    }
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
git add MyApp/SplashView.swift
git commit -m "Show leaderboard consent sheet at end of first-launch setup flow"
```

---

### Task 6: Add pre-save consent gate to `ComputerGameView.swift`

**Files:**
- Modify: `MyApp/MyApp/ComputerGameView.swift`

- [ ] **Step 1: Add consent state vars to `ComputerGameView`**

Find the existing state vars block (around line 14–27):
```swift
    @State private var savedLeaderboardRoundNumbers = Set<Int>()
```

Add after it:
```swift
    @State private var showingConsentSheet = false
    @State private var pendingConsentRound: (round: HistoryRound, mode: String)? = nil
```

- [ ] **Step 2: Add consent gate inside `saveRoundToLeaderboardIfNeeded`**

Find:
```swift
    private func saveRoundToLeaderboardIfNeeded(_ round: HistoryRound, mode: String) {
        guard !guidedFirstGame else { return }
        guard !savedLeaderboardRoundNumbers.contains(round.roundNumber) else { return }
        savedLeaderboardRoundNumbers.insert(round.roundNumber)
```

Replace with:
```swift
    private func saveRoundToLeaderboardIfNeeded(_ round: HistoryRound, mode: String) {
        guard !guidedFirstGame else { return }
        guard !savedLeaderboardRoundNumbers.contains(round.roundNumber) else { return }
        if LeaderboardConsentManager.shared.state == .undecided {
            pendingConsentRound = (round, mode)
            showingConsentSheet = true
            return
        }
        savedLeaderboardRoundNumbers.insert(round.roundNumber)
```

- [ ] **Step 3: Add the consent sheet modifier to `ComputerGameView.body`**

Find the last `.animation(...)` or `.onChange(...)` modifier on the outermost view in `ComputerGameView.body`, just before the closing `}` of `var body: some View`. Add:

```swift
        .sheet(isPresented: $showingConsentSheet) {
            if let pending = pendingConsentRound {
                LeaderboardConsentSheet(
                    onAllow: {
                        saveRoundToLeaderboardIfNeeded(pending.round, mode: pending.mode)
                        pendingConsentRound = nil
                    },
                    onDeny: {
                        pendingConsentRound = nil
                    },
                    disableInteractiveDismiss: false
                )
                .presentationDetents([.medium])
            }
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
git add MyApp/ComputerGameView.swift
git commit -m "Add leaderboard consent gate to ComputerGameView solo save path"
```

---

### Task 7: Add pre-save consent gate to `OnlineGameView.swift`

**Files:**
- Modify: `MyApp/MyApp/OnlineGameView.swift`

- [ ] **Step 1: Add consent state vars to `OnlineGameView`**

Find:
```swift
    @State private var savedLeaderboardRoundNumbers = Set<Int>()
```

Add after it:
```swift
    @State private var showingConsentSheet = false
    @State private var pendingConsentRound: HistoryRound? = nil
```

- [ ] **Step 2: Add consent gate inside `saveLatestCompletedRoundToLeaderboardIfNeeded`**

Find:
```swift
    private func saveLatestCompletedRoundToLeaderboardIfNeeded() {
        guard game.isHost else { return }
        guard let round = game.completedRounds.sorted(by: { $0.roundNumber < $1.roundNumber }).last else { return }
        guard !savedLeaderboardRoundNumbers.contains(round.roundNumber) else { return }
        savedLeaderboardRoundNumbers.insert(round.roundNumber)
```

Replace with:
```swift
    private func saveLatestCompletedRoundToLeaderboardIfNeeded() {
        guard game.isHost else { return }
        guard let round = game.completedRounds.sorted(by: { $0.roundNumber < $1.roundNumber }).last else { return }
        guard !savedLeaderboardRoundNumbers.contains(round.roundNumber) else { return }
        if LeaderboardConsentManager.shared.state == .undecided {
            pendingConsentRound = round
            showingConsentSheet = true
            return
        }
        savedLeaderboardRoundNumbers.insert(round.roundNumber)
```

- [ ] **Step 3: Add the `onAllow` save logic helper**

After `saveLatestCompletedRoundToLeaderboardIfNeeded`, add:

```swift
    private func saveConsentApprovedRound(_ round: HistoryRound) {
        guard !savedLeaderboardRoundNumbers.contains(round.roundNumber) else { return }
        savedLeaderboardRoundNumbers.insert(round.roundNumber)
        let finalScores = round.runningScores
        let winnerIndex = (0..<6).max(by: { finalScores[$0] < finalScores[$1] }) ?? 0
        let mode = game.aiSeats.isEmpty ? "Online" : "Multiplayer"
        let capturedAISeats = game.aiSeats
        let capturedCode = game.sessionCode
        let names = game.playerNames
        Task {
            await LeaderboardService.shared.recordGame(
                gameMode:    mode,
                playerNames: names,
                finalScores: finalScores,
                winnerIndex: winnerIndex,
                aiSeats:     capturedAISeats,
                rounds:      [round],
                sessionCode: capturedCode
            )
        }
    }
```

- [ ] **Step 4: Add the consent sheet modifier to `OnlineGameView.body`**

Find the last modifier before the closing `}` of `OnlineGameView.body` and add:

```swift
        .sheet(isPresented: $showingConsentSheet) {
            if let pending = pendingConsentRound {
                LeaderboardConsentSheet(
                    onAllow: {
                        saveConsentApprovedRound(pending)
                        pendingConsentRound = nil
                    },
                    onDeny: {
                        pendingConsentRound = nil
                    },
                    disableInteractiveDismiss: false
                )
                .presentationDetents([.medium])
            }
        }
```

- [ ] **Step 5: Build to verify**

```bash
xcodebuild -quiet -project MyApp.xcodeproj -scheme MyApp -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add MyApp/OnlineGameView.swift
git commit -m "Add leaderboard consent gate to OnlineGameView host save path"
```

---

### Task 8: Add pre-save consent gate to `BluetoothGameView.swift`

**Files:**
- Modify: `MyApp/MyApp/BluetoothGameView.swift`

- [ ] **Step 1: Add consent state vars to `BluetoothGameView`**

Find:
```swift
    @State private var savedLeaderboardRoundNumbers = Set<Int>()
```

Add after it:
```swift
    @State private var showingConsentSheet = false
    @State private var pendingConsentRound: HistoryRound? = nil
```

- [ ] **Step 2: Add consent gate inside `saveLatestCompletedRoundToLeaderboardIfNeeded`**

Find:
```swift
    private func saveLatestCompletedRoundToLeaderboardIfNeeded() {
        guard game.isHost else { return }
        guard let round = game.completedRounds.sorted(by: { $0.roundNumber < $1.roundNumber }).last else { return }
        guard !savedLeaderboardRoundNumbers.contains(round.roundNumber) else { return }
        savedLeaderboardRoundNumbers.insert(round.roundNumber)
```

Replace with:
```swift
    private func saveLatestCompletedRoundToLeaderboardIfNeeded() {
        guard game.isHost else { return }
        guard let round = game.completedRounds.sorted(by: { $0.roundNumber < $1.roundNumber }).last else { return }
        guard !savedLeaderboardRoundNumbers.contains(round.roundNumber) else { return }
        if LeaderboardConsentManager.shared.state == .undecided {
            pendingConsentRound = round
            showingConsentSheet = true
            return
        }
        savedLeaderboardRoundNumbers.insert(round.roundNumber)
```

- [ ] **Step 3: Add the `onAllow` save logic helper**

After `saveLatestCompletedRoundToLeaderboardIfNeeded`, add:

```swift
    private func saveConsentApprovedRound(_ round: HistoryRound) {
        guard !savedLeaderboardRoundNumbers.contains(round.roundNumber) else { return }
        savedLeaderboardRoundNumbers.insert(round.roundNumber)
        let finalScores = round.runningScores
        let winnerIndex = (0..<6).max(by: { finalScores[$0] < finalScores[$1] }) ?? 0
        let capturedAISeats = game.aiSeats
        let capturedCode = game.gameSessionId.isEmpty
            ? (UserDefaults.standard.string(forKey: "bt_active_game_session_id") ?? "")
            : game.gameSessionId
        let names = game.playerNames
        Task {
            await LeaderboardService.shared.recordGame(
                gameMode:    "Bluetooth",
                playerNames: names,
                finalScores: finalScores,
                winnerIndex: winnerIndex,
                aiSeats:     capturedAISeats,
                rounds:      [round],
                sessionCode: capturedCode
            )
        }
    }
```

- [ ] **Step 4: Add the consent sheet modifier to `BluetoothGameView.body`**

Find the last modifier before the closing `}` of `BluetoothGameView.body` and add:

```swift
        .sheet(isPresented: $showingConsentSheet) {
            if let pending = pendingConsentRound {
                LeaderboardConsentSheet(
                    onAllow: {
                        saveConsentApprovedRound(pending)
                        pendingConsentRound = nil
                    },
                    onDeny: {
                        pendingConsentRound = nil
                    },
                    disableInteractiveDismiss: false
                )
                .presentationDetents([.medium])
            }
        }
```

- [ ] **Step 5: Build to verify**

```bash
xcodebuild -quiet -project MyApp.xcodeproj -scheme MyApp -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add MyApp/BluetoothGameView.swift
git commit -m "Add leaderboard consent gate to BluetoothGameView host save path"
```

---

### Task 9: Add LEADERBOARD section to `SettingsView.swift`

**Files:**
- Modify: `MyApp/MyApp/SettingsView.swift`

- [ ] **Step 1: Add consent manager reference to `SettingsView`**

Find:
```swift
struct SettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
```

Replace with:
```swift
struct SettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var consentManager = LeaderboardConsentManager.shared

    var body: some View {
```

- [ ] **Step 2: Add the LEADERBOARD section**

Find the `// ── HOW TO PLAY ───────────────────────────────────────` comment and insert the new section immediately before it:

```swift
                // ── LEADERBOARD ───────────────────────────────────────
                Section(header: Text("LEADERBOARD")) {
                    Toggle(isOn: Binding(
                        get: { consentManager.isGranted },
                        set: { granted in
                            if granted { consentManager.grant() }
                            else { consentManager.deny() }
                        }
                    )) {
                        HStack(spacing: 12) {
                            Image(systemName: "chart.bar.fill")
                                .foregroundColor(.accentColor)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Save rounds to global leaderboard")
                                    .foregroundColor(.primary)
                                Text("Uploads player names, scores, bid results, and game mode")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -quiet -project MyApp.xcodeproj -scheme MyApp -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MyApp/SettingsView.swift
git commit -m "Add LEADERBOARD consent toggle to Settings"
```

---

### Task 10: Install, smoke test, and update CLAUDE.md

- [ ] **Step 1: Find booted simulator and install**

```bash
xcrun simctl list devices booted
```

Note the booted simulator UDID, then:

```bash
xcrun simctl install booted \
  $(xcodebuild -project MyApp.xcodeproj -scheme MyApp -configuration Debug \
    -destination "generic/platform=iOS Simulator" \
    -disableAutomaticPackageResolution COMPILER_INDEX_STORE_ENABLE=NO \
    -showBuildSettings 2>/dev/null | grep " BUILT_PRODUCTS_DIR" | head -1 | awk '{print $3}')/MyApp.app
xcrun simctl launch booted com.vijaygoyal.theshadyspade
```

- [ ] **Step 2: Smoke test checklist**

- [ ] Reset consent: `xcrun simctl spawn booted defaults delete com.vijaygoyal.theshadyspade leaderboardConsentState` — verifies undecided state
- [ ] Fresh install → complete SplashView setup → consent sheet appears with "Allow" / "Don't Allow" — both buttons dismiss and proceed to ModeSelectionView
- [ ] "Allow" → play Solo round → round saves normally (saved pill appears)
- [ ] Reset consent to undecided again → play Solo round → consent sheet appears mid-game before first save
- [ ] "Don't Allow" → nudge pill "Leaderboard saving is off · Enable in Settings" appears in Round Complete
- [ ] Open Settings → LEADERBOARD toggle shows OFF → toggle ON → play another round → saves normally
- [ ] Toggle OFF again in Settings → round saves show nudge pill

- [ ] **Step 3: Update `CLAUDE.md`**

Add a changelog entry to the `## v2.0 Changelog` section at the top of `CLAUDE.md`:

```
- [2026-06-12] Add leaderboard consent flow (Apple 5.1.2 fix) — Symptom/motivation: Apple rejected v1.10 for Guideline 5.1.2; app uploaded scores without explicit consent. Root cause: `LeaderboardService.recordGame()` fired automatically with no consent check; existing `ScoreSaveStatusRow` disclosure text appeared after upload began. Fix: added `LeaderboardConsentManager` (`@Observable` singleton, UserDefaults key `leaderboardConsentState`); `recordGame()` guards on `isGranted` and sets `scoreSaveStatus = .disabled` when denied; new `LeaderboardConsentSheet` (bottom sheet, `.medium` detent, `shield.fill` icon, privacy policy link, Allow/Don't Allow buttons); new users see sheet at end of SplashView (`disableInteractiveDismiss: true`); existing users see sheet before first leaderboard save in Solo/Online/Bluetooth (swipe-to-dismiss = deny); Settings LEADERBOARD section toggle; `ScoreSaveStatus.disabled` nudge pill "Leaderboard saving is off · Enable in Settings". Reusable pattern: all leaderboard gates check `LeaderboardConsentManager.shared.isGranted`; consent sheet is fully reusable via `onAllow`/`onDeny` callbacks. Verification: build passed; installed on simulator; tested all three consent paths (new user, existing user pre-save gate, Settings toggle). (`LeaderboardConsentManager.swift`, `LeaderboardConsentSheet.swift`, `Styles.swift`, `LeaderboardService.swift`, `SplashView.swift`, `ComputerGameView.swift`, `OnlineGameView.swift`, `BluetoothGameView.swift`, `SettingsView.swift`, `CLAUDE.md`)
```

- [ ] **Step 4: Final commit**

```bash
git add MyApp/CLAUDE.md
git commit -m "Update CLAUDE.md — leaderboard consent flow (Apple 5.1.2 fix)"
```
