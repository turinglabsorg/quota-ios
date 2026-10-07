#!/bin/zsh
# Generates the Xcode project (XcodeGen) and builds the iOS app with its widgets.
#   scripts/build-ios.sh            build for the simulator (ad-hoc signed, so App Group and Keychain work)
#   scripts/build-ios.sh --device   build for iPhone, signed with QUOTA_TEAM_ID
#   scripts/build-ios.sh --install  build for iPhone and install it on the connected device
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
[[ -f quota/Package.swift ]] || git submodule update --init
xcodegen generate --spec project.yml --quiet

DERIVED="$ROOT/build/ios"
MODE="${1:-}"

if [[ -z "$MODE" ]]; then
  xcodebuild -quiet -project QuotaiOS.xcodeproj -scheme Quota -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
  echo "Built for the simulator in $DERIVED"
  exit 0
fi

: "${QUOTA_TEAM_ID:?Set QUOTA_TEAM_ID to your Apple Developer team ID}"
DESTINATION='generic/platform=iOS'
if [[ "$MODE" == "--install" ]]; then
  DEVICE="${QUOTA_DEVICE:-$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && (/connected/ || /available/) {for (i = 1; i <= NF; i++) if ($i == "(UDID)") {print $(i - 1); exit}}')}"
  : "${DEVICE:?No connected iPhone found: connect it or set QUOTA_DEVICE}"
  # Building for the device itself lets automatic signing register it in the provisioning profile.
  DESTINATION="id=$DEVICE"
fi

xcodebuild -project QuotaiOS.xcodeproj -scheme Quota -configuration Release \
  -destination "$DESTINATION" -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM="$QUOTA_TEAM_ID" build
APP="$DERIVED/Build/Products/Release-iphoneos/Quota.app"
echo "Built $APP"

if [[ "$MODE" == "--install" ]]; then
  xcrun devicectl device install app --device "$DEVICE" "$APP"
fi
