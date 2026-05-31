# 2026-05-31 Physical Device Debug Entitlements Fix

## Goal
Restore local Xcode install/run on Vijay's physical iPhone without changing Release/App Store signing.

## Symptom
- Xcode target was set to `Vijay G. iPhone`, but the app would not install on the phone.
- It had worked on Friday, May 29, 2026 and failed on Sunday, May 31, 2026.
- Device discovery showed the phone was available:
  - `Vijay G. iPhone (26.5)`
  - UDID `00008140-000135EE3432801C`
  - paired, wired, Developer Mode enabled, `Install Application` capability available.

## Root Cause
- The app target used the same entitlements file for both Debug and Release:
  - `CODE_SIGN_ENTITLEMENTS = MyApp/MyApp.entitlements`
- `MyApp.entitlements` requested:
  - `aps-environment = production`
- The local development provisioning profile for `com.vijaygoyal.theshadyspade` includes Vijay's phone, but its Push Notifications entitlement is:
  - `aps-environment = development`
- Debug physical-device installs must match the development provisioning profile. A production push entitlement belongs to Release/App Store distribution, not local Debug install.

## Fix
- Added `MyApp/MyAppDebug.entitlements`.
- `MyAppDebug.entitlements` uses:
  - `aps-environment = development`
  - same Associated Domains as Release.
- Updated the Xcode project:
  - Debug `CODE_SIGN_ENTITLEMENTS = MyApp/MyAppDebug.entitlements`
  - Release `CODE_SIGN_ENTITLEMENTS = MyApp/MyApp.entitlements`
- Kept `MyApp.entitlements` unchanged with `aps-environment = production` for App Store/TestFlight signing.

## Reusable Pattern
- Entitlements that differ between development and distribution must be configuration-specific.
- Do not share a production push entitlement file with Debug physical-device builds.
- Keep Associated Domains in both Debug and Release entitlements unless intentionally disabling Universal Links in local builds.
- When local phone install suddenly fails after previously working, inspect:
  - `xcrun devicectl list devices`
  - device Developer Mode/pairing
  - local provisioning profile entitlements
  - target `CODE_SIGN_ENTITLEMENTS` per configuration.

## Files Changed
- `MyApp/MyApp.xcodeproj/project.pbxproj`
- `MyApp/MyApp/MyAppDebug.entitlements`
- `MyApp/CLAUDE.md`
- `MyApp/docs/superpowers/plans/2026-05-31-device-debug-entitlements.md`

## Checklist
- [x] Confirm physical phone is visible to Xcode.
- [x] Confirm phone is paired, wired, and Developer Mode is enabled.
- [x] Confirm development provisioning profile includes the phone.
- [x] Confirm development profile uses `aps-environment = development`.
- [x] Add Debug-specific entitlements file.
- [x] Keep Release on production entitlements.
- [x] Update Claude log and plan file.
- [x] Verify Debug/Release effective build settings.
- [ ] Run physical-device Debug build/install from Xcode UI.

## Verification Plan
Run from Xcode:

1. Select scheme `MyApp`.
2. Select destination `Vijay G. iPhone`.
3. Confirm build configuration is Debug.
4. Run with `Product > Run`.

CLI equivalent:

```sh
xcodebuild -project MyApp/MyApp.xcodeproj -scheme MyApp -destination id=00008140-000135EE3432801C -configuration Debug -derivedDataPath /private/tmp/ShadySpadeDeviceDerivedData COMPILER_INDEX_STORE_ENABLE=NO build
```

Expected:
- Debug signing uses `MyApp/MyAppDebug.entitlements`.
- Resolved app entitlements contain `aps-environment = development`.
- The app installs and launches on `Vijay G. iPhone`.

## Verification Result
- `plutil` confirms:
  - `MyAppDebug.entitlements` uses `aps-environment = development`.
  - `MyApp.entitlements` remains `aps-environment = production`.
- `xcodebuild -showBuildSettings -configuration Debug` confirms:
  - `CODE_SIGN_ENTITLEMENTS = MyApp/MyAppDebug.entitlements`
- `xcodebuild -showBuildSettings -configuration Release` confirms:
  - `CODE_SIGN_ENTITLEMENTS = MyApp/MyApp.entitlements`
- CLI physical-device build was attempted with destination `00008140-000135EE3432801C`, but the local `xcodebuild` process repeatedly stalled in Xcode's SDK tool-probe phase before compile/signing. Use Xcode UI `Product > Run` for the final device install check.
