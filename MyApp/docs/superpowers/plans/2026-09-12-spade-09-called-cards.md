# SPADE-09 — Scorekeeper called-card recording

## Goal

Record both cards called by the scorekeeper bidder and preserve them across the phone, Watch,
local history, live Firestore sessions, and published scorecards.

## Compatibility

- Add `calledCard1` and `calledCard2` as optional fields.
- Do not backfill existing local rounds or Firestore documents.
- Decode older payloads/documents with missing fields as `nil`.
- Keep partners hand-picked; called cards do not infer who holds them.

## Implementation

- Add phone and Watch pickers with a “Not recorded” option.
- Carry the fields through `ScorekeeperRoundEntry`, Watch payloads, live DTOs, and published DTOs.
- Reject duplicate called cards.
- Show recorded cards in phone history and the Watch round summary.
- Update App Store and hosted privacy-policy data maps because scorekeeper data now includes called cards.

## Validation

Focused command:

```sh
xcodebuild test -project MyApp.xcodeproj -scheme MyApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:MyAppTests/ScorekeeperTests \
  -only-testing:MyAppTests/ScorekeeperSessionServiceTests \
  -only-testing:MyAppTests/ScorekeeperWatchBridgeTests
```

Result: 49 tests passed, 0 failures on 2026-09-12. Deploy the hosted privacy source with
`scripts/deploy_privacy_policy.sh` and verify the live page contains the revised date and called-card
wording.
