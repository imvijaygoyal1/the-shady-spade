# Remove Email Auth Flow

## Goal
Align the app binary, privacy manifest, and hosted privacy policy before App
Store review. The app should not include account creation or email/password
sign-in because the current product uses Firebase Anonymous Authentication only.

## Implementation
- Deleted `AuthView.swift`.
- Deleted `AuthViewModel.swift`.
- Removed both files from `MyApp.xcodeproj/project.pbxproj`.
- Removed the legacy `MainView` auth sheet and email-verification gate.
- Removed unused auth environment wiring from `MyAppApp.swift`.
- Removed unused auth environment property from `ModeSelectionView.swift`.
- Removed `NSPrivacyCollectedDataTypeEmailAddress` from `PrivacyInfo.xcprivacy`.

## Kept
- Firebase anonymous sign-in in `MyAppApp.swift` for backend write security.
- `LeaderboardService.ensureAuthenticated()` for pending leaderboard flushes.
- Firebase Auth SDK dependency, because anonymous auth is still used.

## Verification
- Search confirmed no remaining email/password account strings or
  `NSPrivacyCollectedDataTypeEmailAddress` in app Swift, Xcode project, or
  privacy manifest files.
