# Apple Watch Scorekeeper Regression

Date: 2026-07-21
App: The Shady Spade

## Purpose

The Apple Watch companion lets a real-life scorekeeper view the active scorecard, add a round, and undo the last round from the paired Watch.

The simulator can validate packaging, launch, and message/action logic. Final signoff still requires a real paired iPhone and Apple Watch because WatchConnectivity reachability and companion installation are device behaviors.

## Automated Regression

Run from the repo root:

```bash
MyApp/scripts/run_watch_scorekeeper_regression.sh
```

This validates:

- `watchOS 26.5` simulator runtime is installed
- `MyApp` builds with embedded Watch content
- `MyApp.app/Watch/MyApp Watch App.app` is present
- `ScorekeeperWatchBridgeTests` pass

Optional paired simulator install/launch:

```bash
MyApp/scripts/run_watch_scorekeeper_regression.sh \
  --phone-udid 58521AC2-0750-4B57-A033-6DD2D725B2A0 \
  --watch-udid 20EAF451-96B2-4635-89F6-32D61B6D6996 \
  --install
```

If the script reports a missing runtime, install it:

```bash
xcodebuild -downloadPlatform watchOS
```

## Manual Simulator Notes

Use simulator testing only as a smoke test. Keep only one paired iPhone and one paired Watch booted.

Current dedicated pair used during implementation:

- Phone: `Shady Spade Test iPhone 17`
- Watch: `Shady Spade Test Watch`

Expected simulator smoke flow:

1. Launch The Shady Spade on the paired iPhone simulator.
2. Launch the Watch app on the paired Watch simulator.
3. On the iPhone, open `Real-Life Scorekeeper`.
4. Enter or keep six player names.
5. Tap `Start Scorecard`.
6. On the Watch, tap `Refresh from iPhone` if it does not update automatically.
7. Confirm the Watch shows `Ready for Round 1`, player totals, `Add Round`, and `Undo Last Round`.

## Physical Device Checklist

Use a real iPhone with a paired Apple Watch.

1. Build/install The Shady Spade onto the iPhone.
2. Confirm the Watch companion app appears on the paired Apple Watch.
3. Open The Shady Spade on iPhone.
4. Open `Real-Life Scorekeeper`.
5. Enter player names and tap `Start Scorecard`.
6. Open The Shady Spade on Apple Watch.
7. Confirm the Watch shows the active scorecard and player totals.
8. Add one round from Watch.
9. Confirm the iPhone scorecard updates.
10. Undo the last round from Watch.
11. Confirm the iPhone scorecard updates again.
12. Close and reopen both apps.
13. Confirm the Watch can refresh the current iPhone scorecard.

## If the Watch App Does Not Appear

1. Make sure you are running the `MyApp` scheme after the Watch target was added to the scheme Build Action.
2. In Xcode, select the physical iPhone as the run destination, not a simulator.
3. Build/run the iPhone app again from Xcode.
4. Open the Apple Watch app on the iPhone.
5. Scroll to the app list and look for `The Shady Spade`.
6. If it appears there, enable `Show App on Apple Watch`.
7. If it does not appear, delete The Shady Spade from the iPhone, rebuild/run from Xcode, then wait for the companion app install to complete.
8. Confirm the Apple Watch is unlocked, paired, nearby, and running a watchOS version compatible with `WATCHOS_DEPLOYMENT_TARGET = 10.0`.
9. If Xcode reports a signing/provisioning issue for the Watch target, fix signing for both `MyApp` and `MyApp Watch App` under the same Apple development team.

## Known Constraints

- The Watch cannot start a real-life scorecard by itself in Phase 1. The iPhone owns scorecard creation and player-name entry.
- The Watch inactive state should show `No active scorecard` plus instructions and `Refresh from iPhone`.
- Watch simulator responsiveness depends heavily on CoreSimulator health and host memory pressure.
