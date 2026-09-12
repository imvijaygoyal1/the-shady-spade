# AI-08 regression harness — 2026-09-12

## Goal

Keep the hidden-partner fix measurable and prevent a later AI card-selection change from silently
reintroducing early reveals.

## Approach

`AISelfPlay` already deals deterministic hands with SplitMix64. Its batch summary now reports:

- first partner reveal on trick 1;
- both called cards played by trick 3;
- the share of reveals that were forced by having no legal alternative;
- illegal card selections.

The regression test runs concealment on and off over the same 200 seeds (`5000...5199`). It requires
both configurations to remain legal and requires concealment to improve each early-exposure metric
by more than 10 percentage points. It does not assert exact counts, so harmless heuristic changes do
not make the test brittle.

## Verification

Run:

```bash
xcodebuild test -project MyApp.xcodeproj -scheme MyApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyAppTests/AIPartnerRevealTimingTests
```

Also run `AIConcealmentCostTests` and `AvatarRoleRevealTests` when changing concealment or role
resolution.
