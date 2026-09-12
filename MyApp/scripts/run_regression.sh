#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/MyApp.xcodeproj"
SCHEME="MyApp"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$PROJECT_ROOT/build/regression/$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$ARTIFACT_DIR"

echo "==> Running all unit and integration tests"
xcodebuild test -quiet \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
  -enableCodeCoverage YES \
  -resultBundlePath "$ARTIFACT_DIR/unit-and-integration.xcresult" \
  -only-testing:MyAppTests

echo "==> Running all UI regression tests"
xcodebuild test -quiet \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
  -enableCodeCoverage YES \
  -default-test-execution-time-allowance 90 \
  -maximum-test-execution-time-allowance 120 \
  -resultBundlePath "$ARTIFACT_DIR/ui.xcresult" \
  -only-testing:MyAppUITests

echo
echo "Regression suite passed. Result bundles:"
echo "  $ARTIFACT_DIR/unit-and-integration.xcresult"
echo "  $ARTIFACT_DIR/ui.xcresult"
