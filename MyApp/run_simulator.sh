#!/bin/zsh
# Build, install, reset onboarding flag, and launch on simulator
set -e

UDID="11AFDD37-BF1B-4BAB-8679-1B570C5530EC"
BUNDLE_ID="com.example.MyApp"
SCHEME="MyApp"

echo "▶ Building..."
xcodebuild \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" \
  -configuration Debug build 2>&1 \
  | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "MyApp.app" \
  -path "*/Debug-iphonesimulator/*" 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
  echo "✗ Could not find built MyApp.app"; exit 1
fi

echo "▶ Booting simulator..."
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator

echo "▶ Terminating running app..."
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
sleep 0.5

echo "▶ Installing..."
xcrun simctl install "$UDID" "$APP_PATH"

echo "▶ Resetting welcome screen..."
PLIST=$(find ~/Library/Developer/CoreSimulator/Devices/"$UDID"/data/Containers/Data/Application \
  -name "${BUNDLE_ID}.plist" 2>/dev/null | head -1)

if [ -n "$PLIST" ]; then
  /usr/libexec/PlistBuddy -c "Delete :hasCompletedSetup" "$PLIST" 2>/dev/null || true
  echo "  Reset hasCompletedSetup in $PLIST"
else
  echo "  (No plist found yet — first launch will show welcome screen)"
fi

echo "▶ Launching..."
xcrun simctl launch "$UDID" "$BUNDLE_ID"
echo "✓ Done"
