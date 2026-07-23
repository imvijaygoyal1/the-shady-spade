#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/MyApp.xcodeproj"
SCHEME="MyApp"
BUNDLE_ID="com.vijaygoyal.theshadyspade"
WATCH_BUNDLE_ID="com.vijaygoyal.theshadyspade.watchkitapp"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PROJECT_ROOT/build/watch-derived-data}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$PROJECT_ROOT/build/watch-artifacts/$(date +%Y%m%d-%H%M%S)}"
PHONE_UDID="${PHONE_UDID:-}"
WATCH_UDID="${WATCH_UDID:-}"
INSTALL_AND_LAUNCH="${INSTALL_AND_LAUNCH:-0}"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --device NAME          iPhone simulator name for build/test. Default: iPhone 17 Pro
  --phone-udid UDID      Paired iPhone simulator UDID for optional install/launch
  --watch-udid UDID      Paired Apple Watch simulator UDID for optional install/launch
  --install              Install and launch on the supplied paired simulator UDIDs
  --help                 Show this help

Environment overrides:
  DEVICE_NAME, DERIVED_DATA_PATH, ARTIFACT_DIR, PHONE_UDID, WATCH_UDID,
  INSTALL_AND_LAUNCH=1

What this validates:
  - Matching watchOS simulator runtime is installed
  - MyApp builds with embedded Watch content
  - ScorekeeperWatchBridgeTests pass
  - Optional paired simulator install/launch works
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      DEVICE_NAME="$2"
      shift 2
      ;;
    --phone-udid)
      PHONE_UDID="$2"
      shift 2
      ;;
    --watch-udid)
      WATCH_UDID="$2"
      shift 2
      ;;
    --install)
      INSTALL_AND_LAUNCH=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

mkdir -p "$ARTIFACT_DIR"

log() {
  printf '\n==> %s\n' "$*"
}

if ! xcrun simctl list runtimes | rg -q "watchOS 26.5"; then
  cat >&2 <<'MISSING_RUNTIME'
Missing watchOS 26.5 simulator runtime.

Install it with:
  xcodebuild -downloadPlatform watchOS

Embedded Watch builds require the watchOS simulator runtime to match the installed
Xcode watchsimulator SDK.
MISSING_RUNTIME
  exit 1
fi

log "Building MyApp with embedded Watch content"
xcodebuild build -quiet \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
  -derivedDataPath "$DERIVED_DATA_PATH"

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/MyApp.app"
WATCH_APP_PATH="$APP_PATH/Watch/MyApp Watch App.app"

if [[ ! -d "$WATCH_APP_PATH" ]]; then
  echo "Embedded Watch app not found at: $WATCH_APP_PATH" >&2
  exit 1
fi

log "Running focused Watch scorekeeper tests"
xcodebuild test -quiet \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -resultBundlePath "$ARTIFACT_DIR/watch-scorekeeper.xcresult" \
  -only-testing:MyAppTests/ScorekeeperWatchBridgeTests

if [[ "$INSTALL_AND_LAUNCH" == "1" ]]; then
  if [[ -z "$PHONE_UDID" || -z "$WATCH_UDID" ]]; then
    echo "--install requires both --phone-udid and --watch-udid." >&2
    exit 2
  fi

  log "Booting paired simulators if needed"
  xcrun simctl boot "$PHONE_UDID" 2>/dev/null || true
  xcrun simctl boot "$WATCH_UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$PHONE_UDID" -b
  xcrun simctl bootstatus "$WATCH_UDID" -b

  log "Installing and launching iPhone app"
  xcrun simctl install "$PHONE_UDID" "$APP_PATH"
  xcrun simctl launch --terminate-running-process "$PHONE_UDID" "$BUNDLE_ID" >/dev/null

  log "Installing and launching Watch app"
  xcrun simctl install "$WATCH_UDID" "$WATCH_APP_PATH"
  xcrun simctl launch --terminate-running-process "$WATCH_UDID" "$WATCH_BUNDLE_ID" >/dev/null
fi

cat <<SUMMARY

Watch scorekeeper regression complete.

Artifacts:
  $ARTIFACT_DIR

Manual physical-device validation is still required for final signoff:
  iPhone Real-Life Scorekeeper -> Apple Watch Add Round -> iPhone update -> Watch Undo Last Round.
SUMMARY
