#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/MyApp.xcodeproj"
SCHEME="MyApp"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17}"
DEVICE_UDID="${DEVICE_UDID:-}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$PROJECT_ROOT/build/ui-regression/$(date +%Y%m%d-%H%M%S)}"
BATCH="${BATCH:-all}"
ENABLE_COVERAGE="${ENABLE_COVERAGE:-0}"
DEFAULT_ALLOWANCE="${DEFAULT_ALLOWANCE:-90}"
MAX_ALLOWANCE="${MAX_ALLOWANCE:-120}"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --device NAME          Simulator name. Default: iPhone 17
  --udid UDID            Simulator UDID. Preferred when multiple devices share a name
  --batch NAME           all, app-launch, gameplay, scorekeeper, screen-catalog
  --coverage             Enable Xcode code coverage for this run
  --artifact-dir PATH    Output directory for the .xcresult bundle
  --help                 Show this help

Environment overrides:
  DEVICE_NAME, DEVICE_UDID, ARTIFACT_DIR, BATCH, ENABLE_COVERAGE=1,
  DEFAULT_ALLOWANCE, MAX_ALLOWANCE

Artifacts:
  The XCTest result bundle is written under ARTIFACT_DIR.

Notes:
  Full UI regression needs the explicit 90/120 second execution-time allowance.
  Without it, Xcode can kill longer UI catalog tests even after assertions pass.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      DEVICE_NAME="$2"
      shift 2
      ;;
    --udid)
      DEVICE_UDID="$2"
      shift 2
      ;;
    --batch)
      BATCH="$2"
      shift 2
      ;;
    --coverage)
      ENABLE_COVERAGE=1
      shift
      ;;
    --artifact-dir)
      ARTIFACT_DIR="$2"
      shift 2
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

case "$BATCH" in
  all)
    ONLY_TESTING=("MyAppUITests")
    ;;
  app-launch)
    ONLY_TESTING=("MyAppUITests/AppLaunchFlowUITests")
    ;;
  gameplay)
    ONLY_TESTING=("MyAppUITests/GameplayScreenCatalogUITests")
    ;;
  scorekeeper)
    ONLY_TESTING=("MyAppUITests/ScorekeeperFlowUITests")
    ;;
  screen-catalog)
    ONLY_TESTING=("MyAppUITests/ScreenCatalogUITests")
    ;;
  *)
    echo "Unknown batch: $BATCH" >&2
    usage >&2
    exit 2
    ;;
esac

if [[ -n "$DEVICE_UDID" ]]; then
  DESTINATION="id=$DEVICE_UDID"
else
  DESTINATION="platform=iOS Simulator,name=$DEVICE_NAME"
fi

RESULT_BUNDLE="$ARTIFACT_DIR/${BATCH}-ui-regression.xcresult"
ONLY_TESTING_ARGS=()
for test_identifier in "${ONLY_TESTING[@]}"; do
  ONLY_TESTING_ARGS+=("-only-testing:$test_identifier")
done

cat <<SUMMARY
Running Shady Spade UI regression
  batch: $BATCH
  destination: $DESTINATION
  coverage: $ENABLE_COVERAGE
  default allowance: ${DEFAULT_ALLOWANCE}s
  maximum allowance: ${MAX_ALLOWANCE}s
  result bundle: $RESULT_BUNDLE
SUMMARY

XCODEBUILD_ARGS=(
  test
  -quiet
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -destination "$DESTINATION"
  -default-test-execution-time-allowance "$DEFAULT_ALLOWANCE"
  -maximum-test-execution-time-allowance "$MAX_ALLOWANCE"
)

if [[ "$ENABLE_COVERAGE" == "1" ]]; then
  XCODEBUILD_ARGS+=(-enableCodeCoverage YES)
fi

XCODEBUILD_ARGS+=(
  -resultBundlePath "$RESULT_BUNDLE"
  "${ONLY_TESTING_ARGS[@]}"
)

xcodebuild "${XCODEBUILD_ARGS[@]}"

cat <<SUMMARY

UI regression complete.

Result bundle:
  $RESULT_BUNDLE
SUMMARY
