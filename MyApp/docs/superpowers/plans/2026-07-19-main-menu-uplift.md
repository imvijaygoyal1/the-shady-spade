# Main Menu UI Uplift

## Goal

Redesign the root menu so `New Game` is the dominant primary action, `Local / Bluetooth` and `Join a Game` are secondary play actions, and scorekeeper flows are grouped as compact utility tools.

## Implemented

- Preserved the existing dark green themed background and gold/white typography.
- Kept the trophy button top-left and settings button top-right.
- Reduced the spade logo size and moved content below the safe-area/top buttons so it does not overlap the Dynamic Island/status bar.
- Kept title copy:
  - `The Shady Spade`
  - `Choose a game mode`
- Replaced the five equally weighted large cards with:
  - `New Game` filled gold hero card, existing play icon, chevron, subtitle `Solo or invite friends`.
  - `Local / Bluetooth` dark outlined card, existing radio icon, chevron, subtitle `Nearby play, no internet`.
  - `Join a Game` dark outlined card, existing arrow icon, chevron, subtitle `Enter a room code`.
  - `Scorekeeper Tools` compact section containing:
    - `Real-Life Scorekeeper`, subtitle `Track a physical card table`.
    - `Watch Live Scorecard`, subtitle `Follow with a code`.
- Scorekeeper tools render side-by-side on widths that fit cleanly and stack on narrower screens.
- Refined the scorekeeper area into one compact tertiary utility panel:
  - full-width dark green parent panel,
  - subtle gold border,
  - `Scorekeeper Tools` title with thin gold divider lines,
  - two contained compact tool cards,
  - smaller horizontal row layout with left icon, centered text, and right chevron,
  - thinner inner-card borders and shorter heights than the main action cards.
- Increased scorekeeper panel typography and icon sizes after simulator review showed the compact labels were too small; the section remains tertiary through containment, muted fill, and thinner borders.
- Follow-up simulator screenshot review showed the side-by-side tool cards were still truncating labels. The final tuning gives the text stack layout priority, allows titles/subtitles to wrap, avoids aggressive one-line shrinkage, and keeps the compact panel readable on iPhone 17.
- Restored the bottom copyright as a low-emphasis line below the scorekeeper panel:
  - `© 2026 Vijay Goyal. All rights reserved.`
- Preserved all existing navigation behavior by reusing the same action state transitions.
- Removed the now-unused private `ModeCard` component.
- Fixed a post-install tap regression where the scrollable menu layer sat above the top bar in the `ZStack`, making the visible trophy/settings buttons untappable. The top bar now has a higher `zIndex` than the menu content.
- Tightened `AppLaunchFlowUITests` to assert:
  - new menu copy exists,
  - trophy and settings buttons exist and are hittable,
  - all five action buttons exist,
  - all five action buttons are hittable on iPhone 17.

## Verification

- Build passed:
  - `xcodebuild -quiet -project MyApp/MyApp.xcodeproj -scheme MyApp -destination 'generic/platform=iOS Simulator' build`
- Focused iPhone 17 launch UI test passed:
  - `xcodebuild test -quiet -project MyApp/MyApp.xcodeproj -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyAppUITests/AppLaunchFlowUITests/testLaunchShowsModeSelectionWithoutNetworkBackedServices`
- Focused iPhone 17 launch UI test passed after compact scorekeeper-panel refinement with `1` test, `0` failures, `0` skips:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.20_16-39-34--0400.xcresult`
- Focused iPhone 17 launch UI test passed after scorekeeper readability tuning with `1` test, `0` failures, `0` skips:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.20_16-46-51--0400.xcresult`
- Built Debug for generic iOS Simulator, installed on both booted simulators, and launched both:
  - iPhone 17 Pro `DA97985A-F7CC-44F6-8281-9DD24C22B978`
  - iPhone 17 `11AFDD37-BF1B-4BAB-8679-1B570C5530EC`
- Screenshot verification after final readability/copyright fix:
  - `/private/tmp/shadyspade-copyright-bottom-check.png`
- Focused iPhone 17 launch UI test passed after adding the copyright assertion with `1` test, `0` failures, `0` skips:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.20_18-28-29--0400.xcresult`
- Post-fix visual QA on both booted simulators after commit `02afcc5`:
  - iPhone 17 portrait screenshot: `/private/tmp/shadyspade-qa-iphone17-portrait.png`
  - iPhone 17 Pro portrait screenshot: `/private/tmp/shadyspade-qa-iphone17pro-portrait.png`
  - Verified all five actions are visible, scorekeeper tools are readable, top trophy/settings controls are visible, and the copyright footer sits at the bottom above the home indicator.
  - CLI note: this Xcode `simctl` exposes screenshot/video/display geometry but no direct orientation rotation command, so landscape was not screenshot-verified from CLI in this pass.
- Full scheme with coverage passed after the final footer/readability fix with `114` tests, `0` failures, `0` skips:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.20_18-41-06--0400.xcresult`
- Coverage script output from the final full bundle:
  - Raw app coverage: 11.88% (7851/66097)
  - Logic-focused coverage: 35.16% (3709/10550)
- Full scheme with coverage passed after the top-button fix with `110` tests, `0` failures, `0` skips:
  - `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.20_16-18-26--0400.xcresult`
- Coverage target rows from the final bundle:
  - `MyApp.app` 11.68% (7694/65901)
  - `MyAppTests.xctest` 98.18% (3554/3620)
  - `MyAppUITests.xctest` 94.51% (155/164)
- Coverage script output:
  - Raw app coverage: 11.68% (7694/65901)
  - Logic-focused coverage: 34.84% (3637/10439)
- Direct `simctl` screenshot capture was attempted at `/private/tmp/shadyspade-main-menu-uplift.png`, but CoreSimulatorService was unavailable from the sandbox. The focused iPhone 17 UI test is the completed simulator-size verification.

## Privacy Impact

- No new data collection, storage, upload, Firebase field, analytics, third-party service, camera, contacts, photos, notifications, or account behavior.
- No privacy policy or App Store privacy-label update required.

## Deferred

- No main-menu uplift items currently deferred.
