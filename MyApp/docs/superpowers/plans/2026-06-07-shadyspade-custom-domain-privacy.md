# Shady Spade Custom Domain Privacy Link

## Goal
Move the in-app Privacy Policy link from the old GitHub Pages URL to the new
Shady Spade custom domain while keeping existing online-game universal join
links unchanged.

## New Public URLs
- Home: `https://shadyspade.vijaygoyal.org/`
- Privacy: `https://shadyspade.vijaygoyal.org/privacy`
- Support: `https://shadyspade.vijaygoyal.org/support`

## Implementation
- Updated `SettingsView.swift` Privacy Policy link to
  `https://shadyspade.vijaygoyal.org/privacy`.
- Updated `CLAUDE.md` privacy/web-hosting notes to document the new custom
  domain, support page, and local static source folder.

## Intentional Non-Change
Existing online invite/universal links still use Firebase Hosting:
`https://shadyspade-d6b84.web.app/shadyspade/join/{ROOMCODE}`.
Moving those links to the custom domain would require a separate AASA,
Associated Domains, QR/share-text, and deep-link migration.

## Verification
- `curl -L -I https://shadyspade.vijaygoyal.org/` returned HTTP 200.
- `curl -L -I https://shadyspade.vijaygoyal.org/privacy` returned 307 to
  `/privacy/`, then HTTP 200.
- `curl -L -I https://shadyspade.vijaygoyal.org/support` returned 307 to
  `/support/`, then HTTP 200.
- Existing Firebase universal-link files still work:
  `/.well-known/apple-app-site-association` returned HTTP 200 and sample
  `/shadyspade/join/ABC123` returned HTTP 200.
- `git diff --check` passed.
- `xcodebuild -quiet -project MyApp.xcodeproj -scheme MyApp -destination 'generic/platform=iOS Simulator' build` passed.
