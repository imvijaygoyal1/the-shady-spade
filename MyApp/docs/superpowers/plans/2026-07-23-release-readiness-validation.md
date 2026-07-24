# Release Readiness Validation - 2026-07-23

## Goal

Validate the current The Shady Spade state after live scorekeeper polish across regression, external links, Watch packaging, privacy/App Store review surfaces, and archive/export packaging.

## Automated Results

- Full UI regression runner added on 2026-07-24:
  - Script: `scripts/run_full_ui_regression.sh`
  - Default scope: `MyAppUITests`
  - Batch scopes: `app-launch`, `gameplay`, `scorekeeper`, `screen-catalog`
  - Stable timeout settings: `-default-test-execution-time-allowance 90` and `-maximum-test-execution-time-allowance 120`
  - Optional coverage: `--coverage`
  - Run examples:
    - `DEVICE_UDID=58521AC2-0750-4B57-A033-6DD2D725B2A0 scripts/run_full_ui_regression.sh`
    - `scripts/run_full_ui_regression.sh --device "iPhone 17" --batch scorekeeper`
    - `scripts/run_full_ui_regression.sh --udid 58521AC2-0750-4B57-A033-6DD2D725B2A0 --coverage`
- 2026-07-24 full UI validation:
  - First no-allowance full UI run failed with `7` failures, all `Test crashed with signal kill`.
  - The failing subset passed after adding the 90/120 second execution-time allowance:
    - Result bundle: `build/full-ui-failing-subset-2026-07-24.xcresult`
    - Tests: `7`, failures `0`, skips `0`
  - Full `MyAppUITests` then passed with the same allowance:
    - Result bundle: `build/full-ui-suite-2026-07-24-with-allowance.xcresult`
    - Tests: `21`, failures `0`, skips `0`
  - Script verification passed:
    - Command: `DEVICE_UDID=58521AC2-0750-4B57-A033-6DD2D725B2A0 ARTIFACT_DIR=build/ui-regression/script-verification-20260724-final scripts/run_full_ui_regression.sh`
    - Result bundle: `build/ui-regression/script-verification-20260724-final/all-ui-regression.xcresult`
    - Tests: `21`, no failure issues in `.xcresult`
  - Conclusion: use the script or include the allowance flags for full UI regression. The no-allowance failure was XCTest runner timeout/kill behavior, not a UI assertion failure.
- Full regression with coverage passed:
  - Command target: `xcodebuild test -project MyApp.xcodeproj -scheme MyApp -destination id=58521AC2-0750-4B57-A033-6DD2D725B2A0 -enableCodeCoverage YES`
  - Result bundle: `build/release-readiness/full-regression-coverage-udid.xcresult`
  - Unit tests: `127`, failures `0`, skips `0`
  - UI tests: `18`, failures `0`, skips `0`
  - Total: `145` tests, failures `0`, skips `0`
- Coverage baseline:
  - Raw app coverage: `24.13%`
  - Logic-focused coverage: `38.80%`
  - Main uncovered areas remain large SwiftUI/gameplay screens: `ComputerGameView.swift`, `OnlineGameView.swift`, `BluetoothGameView.swift`, `Styles.swift`, `OnlineSessionView.swift`, `BluetoothGameViewModel.swift`, `SplashView.swift`, `OnlineGameViewModel.swift`, and `ScorekeeperView.swift`.
- External link integration passed:
  - Script: `scripts/run_external_link_integration.sh --join SMS123 --scorekeeper VIEW01`
  - Artifacts: `build/release-readiness/external-link-integration`
  - Covered hosted AASA/fallback pages, focused link/scorekeeper XCTest coverage, simulator install, and screenshots for:
    - `https://shadyspade.vijaygoyal.org/join/SMS123`
    - `https://shadyspade.vijaygoyal.org/scorekeeper/VIEW01`
    - `shadyspade://join/SMS123`
    - `shadyspade://scorekeeper/VIEW01`
- Watch regression passed:
  - Script: `scripts/run_watch_scorekeeper_regression.sh`
  - Result bundle: `build/release-readiness/watch-regression/watch-scorekeeper.xcresult`
  - Confirms Watch scorekeeper build/package path and focused bridge tests.
- Archive/export passed:
  - Archive: `build/release-readiness/MyApp-release-readiness.xcarchive`
  - Export: `build/release-readiness/export/MyApp.ipa`
  - Export summary shows Cloud Managed Apple Distribution signing, iPhone app version `1.10` build `10`, Watch app version `1.10` build `10`, Associated Domains, `get-task-allow = false`, and embedded Watch app architectures `arm64_32` and `arm64`.
  - IPA contains app `PrivacyInfo.xcprivacy`, Firebase privacy manifests, embedded Watch app, Watch `Assets.car`, Watch `Info.plist`, and Watch `embedded.mobileprovision`.

## Privacy And Capability Review

- `PrivacyInfo.xcprivacy` declares:
  - Tracking disabled.
  - UserDefaults accessed API reason `CA92.1`.
  - Name and gameplay content collected for app functionality.
- Current app entitlements contain Associated Domains only:
  - `applinks:shadyspade.vijaygoyal.org`
  - `applinks:shadyspade-d6b84.web.app`
  - `applinks:shadyspade-d6b84.firebaseapp.com`
- Built app `Info.plist` contains:
  - `NSCameraUsageDescription` for QR scanning.
  - `NSLocalNetworkUsageDescription` for nearby local/Bluetooth multiplayer.
  - Bonjour services `_shady-spade._tcp` and `_shady-spade._udp`.
  - Custom URL scheme `shadyspade`.
- `APPSTORE_PRIVACY.md` already covers:
  - Firebase leaderboard/online/live scorekeeper data.
  - Explicit live scorekeeper sharing.
  - Camera QR scan.
  - Local-network TV/dashboard data.
  - Theme/display preferences.

## Remaining Manual Release Checks

- Physical iPhone Camera scan opens the installed app for generated join and scorekeeper QR links.
- Messages/SMS tap opens the installed app for join and scorekeeper links.
- Real paired iPhone and Apple Watch validation:
  - Start Real-Life Scorekeeper on iPhone.
  - Confirm Watch receives active scorecard.
  - Add Round from Watch.
  - Confirm iPhone updates.
  - Undo Last Round from Watch.
  - Confirm iPhone updates again.

## Notes

- Simulator universal links can still open Safari fallback pages because Associated Domains are cached and `simctl openurl` does not fully model Camera/Messages physical-device handoff.
- The pre-export archive was development-signed by Xcode, then the export step re-signed the IPA for App Store distribution. Use `build/release-readiness/export/DistributionSummary.plist` as the source of truth for exported signing.
