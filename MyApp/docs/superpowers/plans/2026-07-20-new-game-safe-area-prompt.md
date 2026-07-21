# New Game Prompt Safe-Area Fix

Date: 2026-07-20

## Issue

After tapping `New Game`, the reusable name/avatar prompt placed the selected avatar card too close to the top edge on iPhone simulator screens with a Dynamic Island/status area.

## Cause

`NamePromptSheet` is presented through the app's custom `NoAnimationCover`. The prompt background intentionally ignores the safe area, and in this presentation context `GeometryProxy.safeAreaInsets.top` can report `0`. The iPhone portrait layout therefore used only the old fixed `28pt` top padding, which was not enough for Dynamic Island devices.

## Fix

The iPhone portrait prompt now uses:

```swift
let topContentPadding = max(72, geo.safeAreaInsets.top + 12)
```

This keeps the reusable prompt clear of the unsafe top area even when the geometry safe-area inset is unavailable, while still allowing larger reported insets to win.

## Verification

- Added `AppLaunchFlowUITests.testNewGameNamePromptAvatarClearsDynamicIslandArea`.
- Targeted regression test passed on iPhone 17.
- Full `AppLaunchFlowUITests` class passed on iPhone 17.
