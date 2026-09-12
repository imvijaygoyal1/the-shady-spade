# Agent instructions — The Shady Spade

**Read `CLAUDE.md` first, then its "Current Handoff Snapshot".** `CLAUDE.md` is the authoritative
guide and is deliberately not duplicated here; a second copy would drift from it.

`AUDIT_REPORT.md` is the single source for findings — one entry per defect with ID, file, issue,
status and fix. Never restate a finding somewhere else. If a previous agent split one defect across
two documents, consolidate rather than extend: the next reader may act on the stale copy.

## The rules this project has actually been burned by

1. **Do not claim device behaviour from a green suite.** Paired iPhone↔Watch sync, Camera/Messages
   universal links and AirPlay are not reachable from tests. The Group A device pass (2026-09-04)
   was the first hardware verification of universal links in this project's history, and Group B is
   still the only thing blocking v2.0.
2. **Tag every submission, at submission time.** `git tag -a v<version>-build<n> <commit>`. This
   rule exists because the v1.10 boundary turned out to be *underivable* — no tags, version bumps
   swept into unrelated commits, and build `8` absent from git entirely.
3. **Measure AI changes, never tune by feel.** `MyAppTests/AISelfPlay.swift` plays full headless
   hands against seeded deals. Two findings this session were produced by it, and one *wrong*
   diagnosis of mine was caught by it — see AI-07/AI-08 in `AUDIT_REPORT.md`. Run
   `-only-testing:MyAppTests/AISelfPlayTests` and the `AIPersonality` / `AIPartnerRevealTiming` /
   `AIConcealmentCost` suites; they print their ledgers.
4. **Separate forced from chosen before reading any AI metric.** Both headline numbers here were
   wrong on the first pass: "48.5% of feeds go to the opposition" was really ~70% forced follows,
   and reveal timing needed the same split. A raw count over card plays is almost always
   measuring the rules, not the bot.
5. **`xcodebuild` can hang before compiling** — a pipe-buffer deadlock in `SWBBuildService`, not a
   wedged toolchain. `CLAUDE.md` carries the diagnosis, the watchdog and what has already been
   eliminated by test. **0% CPU is not evidence of a wedge**; `sample` the process first.
6. **UI tests are unstable under repeated launches.** Use
   `scripts/run_full_ui_regression.sh`, or pass
   `-default-test-execution-time-allowance 90 -maximum-test-execution-time-allowance 120`. A UI
   failure that passes in isolation, with a diff touching no UI code, is very likely this.

## Before finishing any piece of work

Update `CLAUDE.md` (changelog entry + the Handoff Snapshot if state moved), add the finding to
`AUDIT_REPORT.md`, run the suite, and commit. Check `APPSTORE_PRIVACY.md` before anything touching
data collection, Firebase, camera, notifications or third-party services.
