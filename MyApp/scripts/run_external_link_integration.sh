#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/MyApp.xcodeproj"
SCHEME="MyApp"
BUNDLE_ID="com.vijaygoyal.theshadyspade"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PROJECT_ROOT/build/integration-derived-data}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$PROJECT_ROOT/build/integration-artifacts/$(date +%Y%m%d-%H%M%S)}"
HOST="${HOST:-https://shadyspade.vijaygoyal.org}"
JOIN_CODE="${JOIN_CODE:-SMS123}"
SCOREKEEPER_CODE="${SCOREKEEPER_CODE:-VIEW01}"
RUN_XCTESTS="${RUN_XCTESTS:-1}"
CHECK_HOSTED="${CHECK_HOSTED:-1}"
BUILD_AND_INSTALL="${BUILD_AND_INSTALL:-1}"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --device NAME          Simulator name. Default: iPhone 17
  --join CODE            Join room code. Default: SMS123
  --scorekeeper CODE     Scorekeeper code. Default: VIEW01
  --skip-xctests         Skip focused XCTest validation
  --skip-hosted          Skip hosted AASA/fallback checks
  --skip-build           Skip build/install and only drive openurl/screenshots
  --help                 Show this help

Environment overrides:
  DEVICE_NAME, JOIN_CODE, SCOREKEEPER_CODE, DERIVED_DATA_PATH, ARTIFACT_DIR,
  RUN_XCTESTS=0, CHECK_HOSTED=0, BUILD_AND_INSTALL=0

Artifacts:
  Screenshots and XCTest result bundles are written under ARTIFACT_DIR.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      DEVICE_NAME="$2"
      shift 2
      ;;
    --join)
      JOIN_CODE="$2"
      shift 2
      ;;
    --scorekeeper)
      SCOREKEEPER_CODE="$2"
      shift 2
      ;;
    --skip-xctests)
      RUN_XCTESTS=0
      shift
      ;;
    --skip-hosted)
      CHECK_HOSTED=0
      shift
      ;;
    --skip-build)
      BUILD_AND_INSTALL=0
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

normalize_code() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9' | cut -c 1-6
}

JOIN_CODE="$(normalize_code "$JOIN_CODE")"
SCOREKEEPER_CODE="$(normalize_code "$SCOREKEEPER_CODE")"
JOIN_URL="$HOST/join/$JOIN_CODE"
SCOREKEEPER_URL="$HOST/scorekeeper/$SCOREKEEPER_CODE"
CUSTOM_JOIN_URL="shadyspade://join/$JOIN_CODE"
CUSTOM_SCOREKEEPER_URL="shadyspade://scorekeeper/$SCOREKEEPER_CODE"

if [[ ${#JOIN_CODE} -ne 6 || ${#SCOREKEEPER_CODE} -ne 6 ]]; then
  echo "Join and scorekeeper codes must normalize to exactly 6 alphanumeric characters." >&2
  exit 2
fi

booted_udid_for_device() {
  xcrun simctl list devices booted | awk -v name="$DEVICE_NAME" '
    index($0, name) && index($0, "(Booted)") {
      if (match($0, /\(([0-9A-F-]{36})\)/)) {
        print substr($0, RSTART + 1, RLENGTH - 2)
        exit
      }
    }
  '
}

available_udid_for_device() {
  xcrun simctl list devices available | awk -v name="$DEVICE_NAME" '
    index($0, name) && !index($0, "unavailable") {
      if (match($0, /\(([0-9A-F-]{36})\)/)) {
        print substr($0, RSTART + 1, RLENGTH - 2)
        exit
      }
    }
  '
}

ensure_booted_device() {
  local udid
  udid="$(booted_udid_for_device || true)"
  if [[ -n "$udid" ]]; then
    printf '%s' "$udid"
    return
  fi

  log "No booted '$DEVICE_NAME' simulator found; booting an available one"
  udid="$(available_udid_for_device || true)"
  if [[ -z "$udid" ]]; then
    echo "No available simulator named '$DEVICE_NAME' found." >&2
    exit 1
  fi

  xcrun simctl boot "$udid" || true
  xcrun simctl bootstatus "$udid" -b
  printf '%s' "$udid"
}

if [[ "$CHECK_HOSTED" == "1" ]]; then
  log "Checking hosted AASA and fallback pages"
  curl -fsSI "$HOST/.well-known/apple-app-site-association" \
    | tee "$ARTIFACT_DIR/aasa-headers.txt" \
    | grep -i "content-type: application/json" >/dev/null
  curl -fsS "$HOST/.well-known/apple-app-site-association" \
    | tee "$ARTIFACT_DIR/apple-app-site-association.json" \
    | grep "7B5U5LACV3.$BUNDLE_ID" >/dev/null
  curl -fsS "$JOIN_URL" | tee "$ARTIFACT_DIR/join-fallback.html" | grep "$JOIN_CODE" >/dev/null
  curl -fsS "$SCOREKEEPER_URL" | tee "$ARTIFACT_DIR/scorekeeper-fallback.html" | grep "$SCOREKEEPER_CODE" >/dev/null
fi

if [[ "$RUN_XCTESTS" == "1" ]]; then
  log "Running focused link and scorekeeper regression tests"
  xcodebuild test -quiet \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
    -resultBundlePath "$ARTIFACT_DIR/focused-regression.xcresult" \
    -only-testing:MyAppTests/AppRegressionTests \
    -only-testing:MyAppTests/OnlineSessionViewModelTests \
    -only-testing:MyAppTests/ScorekeeperSessionServiceTests \
    -only-testing:MyAppUITests/ScorekeeperFlowUITests \
    -only-testing:MyAppUITests/ScreenCatalogUITests/testJoinGameScreenCatalog
fi

DEVICE_UDID="$(ensure_booted_device)"
log "Using simulator '$DEVICE_NAME' ($DEVICE_UDID)"

if [[ "$BUILD_AND_INSTALL" == "1" ]]; then
  log "Building and installing app"
  xcodebuild build -quiet \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "id=$DEVICE_UDID" \
    -derivedDataPath "$DERIVED_DATA_PATH"

  APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/MyApp.app"
  if [[ ! -d "$APP_PATH" ]]; then
    echo "Built app not found at $APP_PATH" >&2
    exit 1
  fi
  xcrun simctl install "$DEVICE_UDID" "$APP_PATH"
fi

log "Launching app in UI-test-safe mode"
xcrun simctl launch --terminate-running-process "$DEVICE_UDID" "$BUNDLE_ID" -SHADYSPADE_UI_TESTING >/dev/null
sleep 2
xcrun simctl io "$DEVICE_UDID" screenshot "$ARTIFACT_DIR/00-launched.png" >/dev/null

open_and_capture() {
  local url="$1"
  local name="$2"

  log "Opening $url"
  xcrun simctl openurl "$DEVICE_UDID" "$url"
  sleep 3
  xcrun simctl io "$DEVICE_UDID" screenshot "$ARTIFACT_DIR/$name.png" >/dev/null
}

open_and_capture "$JOIN_URL" "01-universal-join-$JOIN_CODE"
open_and_capture "$SCOREKEEPER_URL" "02-universal-scorekeeper-$SCOREKEEPER_CODE"
open_and_capture "$CUSTOM_JOIN_URL" "03-custom-join-$JOIN_CODE"
open_and_capture "$CUSTOM_SCOREKEEPER_URL" "04-custom-scorekeeper-$SCOREKEEPER_CODE"

cat <<SUMMARY

Integration smoke complete.

Artifacts:
  $ARTIFACT_DIR

Automated checks covered:
  - Hosted AASA and fallback pages, unless skipped
  - Focused link/scorekeeper XCTest coverage, unless skipped
  - Simulator URL handoff screenshots for:
    - $JOIN_URL
    - $SCOREKEEPER_URL
    - $CUSTOM_JOIN_URL
    - $CUSTOM_SCOREKEEPER_URL

Review screenshots:
  - 01-universal-join-$JOIN_CODE.png records the branded join-link result.
  - 02-universal-scorekeeper-$SCOREKEEPER_CODE.png records the branded scorekeeper-link result.
  - 03-custom-join-$JOIN_CODE.png records the custom-scheme join result.
  - 04-custom-scorekeeper-$SCOREKEEPER_CODE.png records the custom-scheme scorekeeper result.

Important:
  Simulator universal links may open Safari fallback pages instead of the app
  because Associated Domains are cached and simulator behavior differs from
  Camera/Messages on a physical install. Treat screenshots as evidence to review,
  not as a replacement for the physical-device checklist.

Manual physical-device checks still required:
  - iPhone Camera scans a generated QR and opens the installed app
  - Messages/SMS tap opens the installed app
  - Live scorekeeper host/viewer sync works across two real devices or simulators
SUMMARY
