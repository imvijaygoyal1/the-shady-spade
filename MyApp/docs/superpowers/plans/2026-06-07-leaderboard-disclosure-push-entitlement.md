# Leaderboard Disclosure and Push Entitlement Audit

## Goal
Close two App Store review audit items:
- Show clear in-app disclosure near leaderboard save points.
- Remove push notification entitlements if push notifications are not used.

## Findings
- `ScoreSaveStatusRow` is the shared UI shown around leaderboard saves in Solo,
  Online, Bluetooth, Pass & Play, final standings, and the leaderboard screen.
- The app had `aps-environment` in both `MyApp.entitlements` and
  `MyAppDebug.entitlements`.
- Search found no `UNUserNotificationCenter` permission request, no
  `registerForRemoteNotifications`, and no APNs registration callbacks.
- Local `NotificationCenter` and haptic `UINotificationFeedbackGenerator` usage
  are not push notification usage.

## Implementation
- Added disclosure copy to `ScoreSaveStatusRow` for leaderboard save states:
  completed rounds may upload avatar names, scores, bid results, and game mode
  to the global leaderboard.
- Suppressed that disclosure for `.notSaved` states, where no leaderboard upload
  is expected.
- Removed `aps-environment` from Debug and Release entitlement files.
- Preserved Associated Domains entitlements for universal links.

## Verification
- `rg` found no `aps-environment`, `UNUserNotification`,
  `registerForRemoteNotifications`, remote-notification authorization request,
  or APNs registration callback in app/project files.
- `git diff --check` passed.
- `plutil -p MyApp/MyApp.entitlements` and
  `plutil -p MyApp/MyAppDebug.entitlements` confirmed both entitlement files
  only contain Associated Domains.
- `xcodebuild -quiet -project MyApp.xcodeproj -scheme MyApp -destination 'generic/platform=iOS Simulator' build` passed.
