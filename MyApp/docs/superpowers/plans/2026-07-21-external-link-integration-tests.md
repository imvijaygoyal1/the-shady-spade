# External Link Integration Test Setup

Date: 2026-07-21
App: The Shady Spade

## Goal

Create a repeatable integration process for the new external-entry features:

- iPhone Camera QR scan opening branded join/scorekeeper links
- SMS/Messages invite links opening branded join/scorekeeper links
- manual Real-Life Scorekeeper entry and live viewer flows

## Implemented

- Added `scripts/run_external_link_integration.sh`.
- Added `docs/integration-tests/external-link-scorekeeper.md`.
- The script automates:
  - hosted AASA content-type/body checks
  - hosted join/scorekeeper fallback checks
  - focused app regression tests for link parsing, join normalization, scorekeeper service/viewer coverage, and join screen catalog
  - simulator build/install
  - `simctl openurl` for branded universal links and custom-scheme fallback links
  - screenshots for manual review of each handoff result

## Initial Run

Command:

```bash
MyApp/scripts/run_external_link_integration.sh
```

Result:

- Hosted AASA and fallback checks passed.
- Focused regression bundle completed.
- App built, installed, launched, and screenshots were captured under:
  `/Users/vijaygoyal/MyiOSApp/MyApp/build/integration-artifacts/20260721-181820`
- Simulator screenshots showed the branded universal join link opening Safari fallback, which is possible on simulator because Associated Domains are cached and `simctl openurl` is not equivalent to Camera/Messages on a physical install.
- Custom-scheme screenshots showed the iOS confirmation prompt path.

## Boundary

The script can prove hosted assets, app/link plumbing, focused XCTest coverage, and simulator handoff evidence. It cannot fully prove iPhone Camera or Messages behavior. Those are Apple system-app and universal-link association-cache behaviors, so the documentation includes a manual physical-device checklist.

## Commands

```bash
MyApp/scripts/run_external_link_integration.sh
MyApp/scripts/run_external_link_integration.sh --device "iPhone 17"
MyApp/scripts/run_external_link_integration.sh --join ABC123 --scorekeeper VIEW01
```

## Remaining

- Run the integration script on a clean simulator after each release candidate.
- Run the manual device checklist on TestFlight or a release-signed build before App Store submission.
