# App-Wide Theme System Implementation Record

**Goal:** Finish the existing theme engine enough for users to switch app appearance from Settings without rewriting the app's visual system.

**Status:** Implemented core option 2 on 2026-06-06.

## Root Cause

`ThemeManager`, `AppTheme`, and `ThemeColours` already existed, but the app was effectively locked to one dark theme because `ClassicGreenTheme.fixedColorScheme` returned `.dark`. `ThemeManager.preferredColorScheme` was also non-optional, so it could not represent SwiftUI's System appearance mode. Settings had no appearance UI, `availableThemes` contained only Casino Night, and several visible components still read raw `@Environment(\.colorScheme)`, `UIColor` adaptive closures, or hardcoded colors instead of theme tokens.

## Implementation

- Added `ThemeMode` in `ThemeEngine.swift` with `.dark`, `.light`, and `.system`.
- Updated `ThemeManager` to persist `themeMode` in `UserDefaults["preferredMode"]`, expose `preferredColorScheme: ColorScheme?`, apply themes via `applyTheme(_:)`, and sync system color changes through `updateSystemColorScheme(_:)`.
- Updated `MyAppApp` to pass optional `.preferredColorScheme(...)` and feed environment color-scheme changes back to `ThemeManager` for System mode token lookups.
- Changed Casino Night (`ClassicGreenTheme`) to adaptive by returning `nil` for `fixedColorScheme` and added a warm light palette.
- Added `MidnightBlueTheme` and `ParchmentTheme` with dark and light palettes, then registered both in `ThemeManager.availableThemes`.
- Added a Settings APPEARANCE section with a Dark/Light/System segmented picker and horizontal theme swatch buttons.
- Moved the primary visible bypasses to theme tokens:
  - `Styles.swift` static color aliases (`masterGold`, `offenseBlue`, `defenseRose`, adaptive text/divider/subtle colors).
  - `Styles.swift` trump/called suit display colors, PASS red, and avatar picker inactive background.
  - `ComicTheme.HalftoneBackground`.
  - `AdaptiveColours.ThemedScreenBackground`.
  - `PlayerScoreBarChart` accents, surface, and border.
  - `SettingsView` tint.
  - `TVGameView` optional preferred color scheme.

## Verification

Passed:

```bash
xcodebuild -quiet -project MyApp.xcodeproj -scheme MyApp -destination 'generic/platform=iOS Simulator' build
```

The first sandboxed build failed before compile due Xcode package/CoreSimulator sandbox restrictions. The escalated build succeeded.

## Follow-Up

- Run visual simulator QA through Settings, mode selection, solo gameplay, online/bluetooth screens, score charts, and TV display.
- Confirm `selectedTheme` and `preferredMode` persist across app restart.
- Continue the broader cleanup for decorative hardcoded colors in `CardDealAnimationView`, `TVGameView`, `LeaderboardView`, and remaining card highlight constants.
- Consider adding dedicated `ThemeColours` tokens for success/waiting/pass/called-card/trump-card states if those elements need per-theme tuning beyond the current aliases.
