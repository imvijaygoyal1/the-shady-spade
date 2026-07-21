# Expanded UI Regression Catalog

Date: 2026-07-21
App: The Shady Spade

## Goal

Increase automated UI regression coverage beyond the main menu and scorekeeper flows without turning the routine suite into a flaky full gameplay simulator.

## Implemented

- Added UI-test launch hooks for:
  - How To Play
  - Leaderboard consent sheet
  - Seeded game history detail
  - Seeded Solo gameplay catalog
  - Seeded Online gameplay catalog
  - Seeded Bluetooth gameplay catalog
- Added seeded gameplay catalog harnesses in the same files as the private gameplay phase views so they can render real Bidding, Calling, Playing, Round Complete, and Final Standing surfaces.
- Added shared `UITestCatalogPhaseBar`.
- Added stable catalog accessibility identifiers.
- Expanded `ScreenCatalogUITests` for How To Play, leaderboard consent, and game history detail.
- Added `GameplayScreenCatalogUITests` for Solo, Online, and Bluetooth seeded gameplay entry/bidding surfaces with screenshot attachments.
- Gated gameplay repeat-forever decorative animations during UI tests to reduce XCTest idle waits.
- Added an accessibility identifier to the leaderboard consent privacy link.

## Verification

- Generic iOS build with signing disabled passed:
  `xcodebuild build -quiet -project MyApp/MyApp.xcodeproj -scheme MyApp -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`
- Focused gameplay catalog passed:
  `xcodebuild test -quiet -project MyApp/MyApp.xcodeproj -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyAppUITests/GameplayScreenCatalogUITests`
- Combined catalog passed with `14` tests, `0` failures, `0` skips:
  `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.21_17-39-15--0400.xcresult`
- Full UI target passed with `18` tests, `0` failures, `0` skips:
  `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.21_17-43-45--0400.xcresult`
- Full scheme with code coverage passed with `130` tests, `0` failures, `0` skips:
  `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/MyApp-elxlvmrzwbclzobtlfohtvgqzosy/Logs/Test/Test-MyApp-2026.07.21_17-49-37--0400.xcresult`
- Coverage baseline from that bundle:
  - Raw app coverage: `23.77% (15928/67009)`
  - Logic-focused coverage: `37.52% (3969/10578)`

## Notes

- Earlier full phase tap-through tests passed but took too long because gameplay screens and simulator accessibility idling are expensive. The routine UI suite now verifies each seeded harness opens and captures screenshots, while the harnesses still support future manual or targeted phase checks.
- One retry failed before app assertions with `Timed out while loading Accessibility` after repeated simulator UI-test launches. CoreSimulator was temporarily unhealthy; booting/recovering the simulator allowed subsequent Xcode UI tests to pass.

## Remaining

- Add a landscape viewport matrix once simulator reliability is stable.
- Add true screenshot diff baselines if the project adopts image-comparison tooling.
- Keep deeper gameplay behavior coverage primarily in unit tests around game rules and scoring; use UI only for layout smoke and high-value interaction flows.
