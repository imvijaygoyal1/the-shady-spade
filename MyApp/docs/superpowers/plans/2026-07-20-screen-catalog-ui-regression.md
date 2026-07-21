# Screen Catalog UI Regression

Date: 2026-07-20

## Goal

Add a practical UI regression layer that opens major screens directly, verifies their key visible controls, checks important content against safe top/bottom bounds, and keeps screenshot attachments in `.xcresult`.

## Implementation

Added UI-test launch hooks gated by `-SHADYSPADE_UI_TESTING`:

- `-SHADYSPADE_OPEN_SETTINGS_FOR_UI_TESTS`
- `-SHADYSPADE_OPEN_LEADERBOARD_FOR_UI_TESTS`
- `-SHADYSPADE_OPEN_NAME_PROMPT_FOR_UI_TESTS`
- `-SHADYSPADE_OPEN_PLAYER_COUNT_FOR_UI_TESTS`
- `-SHADYSPADE_OPEN_GUIDED_SOLO_CHOICE_FOR_UI_TESTS`
- `-SHADYSPADE_OPEN_JOIN_GAME_FOR_UI_TESTS`
- `-SHADYSPADE_OPEN_BLUETOOTH_FOR_UI_TESTS`

Existing scorekeeper hooks remain in use:

- `-SHADYSPADE_OPEN_SCOREKEEPER_FOR_UI_TESTS`
- `-SHADYSPADE_OPEN_SCOREKEEPER_VIEWER_FOR_UI_TESTS`
- scorekeeper seed/reset arguments

Added `ScreenCatalogUITests` in `AppLaunchFlowUITests.swift` with coverage for:

- Settings
- Leaderboard
- New Game name/avatar prompt
- Player count picker
- Guided solo choice
- Join game entry
- Local / Bluetooth entry
- Real-Life Scorekeeper setup

Added shared UI-test helpers for:

- consistent app launch with UI-test arguments
- visible element assertions
- frame bounds assertions
- kept screenshot attachments

## Verification

- `AppLaunchFlowUITests` passed on iPhone 17.
- `ScreenCatalogUITests` passed on iPhone 17.
- Full UI test target passed with `12` passed, `0` failed, `0` skipped.
- Full scheme passed with `124` passed, `0` failed, `0` skipped.
- Full scheme result bundle:
  `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.20_21-45-29--0400.xcresult`

## Remaining Scope

This is the screen-catalog layer, not exhaustive seeded gameplay-state coverage.

Still worth adding later:

- seeded Solo bidding/play/result screens
- seeded Online game screens
- seeded Bluetooth game screens
- landscape-specific screen catalog checks
- screenshot diffing against approved baselines instead of screenshot attachment capture only
