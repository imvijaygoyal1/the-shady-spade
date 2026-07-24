# Card Deal Theme + Join Prompt Label

Date: 2026-07-23
App: The Shady Spade

## Report

Two UI issues were reported before continuing with new feature work:

- The card distribution animation screen did not react to app theme changes.
- The Join a Game avatar/name prompt showed `Start Game`, which was misleading because that flow joins an existing session.

## Root Cause

`CardDealAnimationView` still contained fixed green, blue, white, and gold colors from the original theme. Because the view is used as a transition screen, the fixed colors made it visually detach from Midnight Blue, Parchment, and any future themes.

`NamePromptSheet.startButton` rendered a hardcoded `Start Game` label for every mode, even though the same reusable sheet is launched by New Game, Local / Bluetooth, and Join a Game.

## Implementation

- Injected `ThemeManager` into `CardDealAnimationView`.
- Replaced the fixed felt background with the active theme screen background and `ThemedBackground`.
- Replaced hardcoded status, progress, player-card, checkmark, count, deck, flying-card, border, and texture colors with active theme tokens.
- Added `cardBackFill` to respect the current theme's solid, gradient, or patterned card-back style.
- Added a UI-test-only launch hook, `-SHADYSPADE_OPEN_CARD_DEAL_FOR_UI_TESTS`, to present the deal animation directly.
- Added mode-aware name prompt action text:
  - `New Game` -> `Start Game`
  - `Join a Game` -> `Join Game`
  - `Local / Bluetooth` -> `Continue`
- Added UI regression coverage for Join prompt labeling and the card-deal animation catalog.

## Verification

Targeted UI regression passed on the iPhone 17 simulator:

```sh
xcodebuild test -project MyApp.xcodeproj -scheme MyApp \
  -destination 'id=58521AC2-0750-4B57-A033-6DD2D725B2A0' \
  -only-testing:MyAppUITests/AppLaunchFlowUITests/testJoinGameNamePromptUsesJoinActionLabel \
  -only-testing:MyAppUITests/GameplayScreenCatalogUITests/testCardDealAnimationScreenCatalog \
  -resultBundlePath build/fix-theme-join-carddeal-tests-final.xcresult
```

Result: `2` tests executed, `0` failures, `0` skips.

`git diff --check` also passed.

## Privacy Impact

None. This is layout, styling, and test-hook work only. It does not change data collection, upload, Firebase, camera, SMS, contacts, analytics, or third-party service behavior.
