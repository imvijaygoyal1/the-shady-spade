# Scorekeeper Add Round Simplification

## Goal

Simplify the Real-Life Scorekeeper Add Round screen while keeping existing scoring behavior intact.

## UX Decision

- Dealer is derived round context, so it should not be a primary field in normal entry.
- Dealer remains editable through an explicit `Adjust` action for correction cases.
- The form is grouped by the user's mental model:
  - `Round Context`: dealer and bid starter.
  - `Bid Details`: bidder, partners, bid amount, trump.
  - `Outcome`: made/failed plus score impact.
  - `Review`: human-readable summary before saving.

## Implementation

- Removed the normal `Dealer` picker from `ScorekeeperRoundEntryView`.
- Added a compact Round Context panel with:
  - current dealer,
  - calculated bid starter,
  - `Adjust` button.
- Added an `Adjust Dealer` sheet that lists all six players and recalculates bid starter after selection.
- Grouped winning bidder, partners, bid amount, quick bid chips, and trump buttons under Bid Details.
- Watch score entry was intentionally left unchanged.
- Kept bidder validation aligned with existing game rules:
  - dealer cannot be selected as winning bidder,
  - bidder cannot be selected as either partner,
  - Partner 1 and Partner 2 cannot duplicate each other.
- Added Outcome score preview pills for offense and defense score deltas.
- Added a Review sentence summarizing the round before save.

## Regression Coverage

- Updated `ScorekeeperFlowUITests.testAddRoundTrumpSelectorUsesRealSuitButtons` to assert:
  - Round Context appears,
  - Dealer picker is no longer exposed as a normal field,
  - Bid Details, Outcome, and Review sections appear,
  - Adjust Dealer sheet opens and dismisses,
  - real-color trump buttons still exist and remain tappable.

## Verification

- Focused Add Round UI test passed:
  - `build/add-round-redesign-ui-rerun.xcresult`
  - `1` test, `0` failures, `0` skips.
- Broader scorekeeper UI slice passed:
  - `build/add-round-redesign-scorekeeper-ui.xcresult`
  - `3` tests, `0` failures, `0` skips.
- `git diff --check` passed.

## Privacy Impact

No privacy impact. This is local UI behavior only and does not change data collection, local persistence, Firebase, WatchConnectivity, camera, SMS, contacts, analytics, or third-party service behavior.
