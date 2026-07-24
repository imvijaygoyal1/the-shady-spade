# Scorekeeper Real Trump Selector

Date: 2026-07-23
App: The Shady Spade

## Request

Make trump selection on the Real-Life Scorekeeper `Add Round` screen use real playing-card suit colors.

## Root Cause

The Add Round form used a standard SwiftUI segmented `Picker` for `Trump`. That control is useful for simple text choices, but it flattened all suit choices into platform/theme tinting. For a card-game UI, users expect hearts and diamonds to be red, and spades and clubs to be black.

## Implementation

- Replaced the segmented trump picker with four compact `TrumpSuitButton` controls.
- Each option uses a white playing-card-like surface so black suits stay readable on dark and light themes.
- Spades/clubs render in near-black.
- Hearts/diamonds render in red.
- Selected state uses the active theme accent and a checkmark.
- Added stable accessibility labels for each option: `Spades trump`, `Hearts trump`, `Diamonds trump`, and `Clubs trump`.
- Added a UI-test-only launch argument, `-SHADYSPADE_OPEN_SCOREKEEPER_ADD_ROUND_FOR_UI_TESTS`, so the Add Round sheet can open directly during regression tests.
- Added a focused UI regression that verifies all four trump choices exist, taps Hearts, and keeps a screenshot attachment.

## Verification

```sh
xcodebuild test -project MyApp.xcodeproj -scheme MyApp \
  -destination 'id=58521AC2-0750-4B57-A033-6DD2D725B2A0' \
  -only-testing:MyAppUITests/ScorekeeperFlowUITests/testAddRoundTrumpSelectorUsesRealSuitButtons \
  -resultBundlePath build/scorekeeper-real-trump-selector-labels.xcresult
```

Result: `1` test executed, `0` failures, `0` skips.

`git diff --check` also passed.

Manual visual evidence was also captured at:

- `build/scorekeeper-add-round-direct-top.png`

## Privacy Impact

None. This changes local visual UI and UI-test hooks only. It does not change data collection, storage, upload, Firebase, camera, SMS, contacts, analytics, or third-party service behavior.
