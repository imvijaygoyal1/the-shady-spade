# App Store Submission Checklist

Use this before every App Store upload or resubmission.

## Build

- [ ] Confirm the branch and commit intended for submission.
- [ ] Run the app test suite.
- [ ] Archive the latest app build.
- [ ] Upload the build to App Store Connect.
- [ ] Select the uploaded build for the app version.

## Privacy

- [ ] Review `APPSTORE_PRIVACY.md`.
- [ ] Confirm `Settings > Privacy Policy` opens `https://shadyspade.vijaygoyal.org/privacy`.
- [ ] Verify the live privacy policy URL after any policy edit.
- [ ] Confirm App Store Connect privacy labels match current app behavior.
- [ ] Confirm no privacy policy wording describes consent-gated uploads as automatic.
- [ ] Confirm any data-sensitive feature changes are reflected in the privacy data map.

## Leaderboard Consent

- [ ] Open Settings.
- [ ] Toggle `Save rounds to global leaderboard`.
- [ ] Confirm the app shows the leaderboard consent sheet.
- [ ] Confirm the sheet says leaderboard data uploads to the Firebase server.
- [ ] Confirm `Play Without Uploading Scores` leaves uploads disabled.
- [ ] Confirm `Allow Score Uploads` enables uploads.
- [ ] Confirm completed-round save paths are still gated by consent.

## App Review Metadata

- [ ] Privacy Policy URL is set in App Store Connect.
- [ ] App Review contact information is current.
- [ ] Demo account is provided only if the app requires one.
- [ ] Review notes explain how to verify leaderboard consent.
- [ ] Screenshots are uploaded for every required device class.
- [ ] Version metadata, category, keywords, support URL, and copyright are complete.

## Security

- [ ] No reviewer passwords, API keys, service-role keys, tokens, or secrets are committed.
- [ ] Test credentials in App Review Notes are rotated if exposed.
- [ ] Production Firebase/Cloudflare/Supabase keys are expected public client keys only.

## Final Verification

- [ ] `git status` reviewed.
- [ ] Known unrelated untracked files are ignored intentionally.
- [ ] App launches fresh on simulator or device.
- [ ] App Review Notes include the current rejection-specific verification path.
