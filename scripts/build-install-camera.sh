#!/bin/zsh

set -euo pipefail

SCRIPT_DIRECTORY=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIRECTORY:h}
DEVELOPER_DIRECTORY=/Applications/Xcode.app/Contents/Developer
INSTALL_APP="/Applications/Snapzy Camera.app"
ENTITLEMENTS="$PROJECT_ROOT/Snapzy/SnapzyCamera.entitlements"
EXPECTED_BUNDLE_IDENTIFIER="com.haileyliu.snapzy-camera"
DESIGNATED_REQUIREMENT="designated => identifier \"$EXPECTED_BUNDLE_IDENTIFIER\""
BUILD_ROOT=$(mktemp -d /tmp/snapzy-camera-build.XXXXXX)
DERIVED_DATA="$BUILD_ROOT/DerivedData"

cleanup() {
  rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

if [[ ! -d "$DEVELOPER_DIRECTORY" ]]; then
  print -u2 "Xcode was not found at /Applications/Xcode.app"
  exit 1
fi

DEVELOPER_DIR="$DEVELOPER_DIRECTORY" xcodebuild \
  -quiet \
  -project "$PROJECT_ROOT/Snapzy.xcodeproj" \
  -scheme Snapzy \
  -configuration Debug \
  -destination platform=macOS \
  -derivedDataPath "$DERIVED_DATA" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  SNAPZY_BUNDLE_NAME="Snapzy Camera" \
  INFOPLIST_KEY_CFBundleDisplayName="Snapzy Camera" \
  PRODUCT_BUNDLE_IDENTIFIER="$EXPECTED_BUNDLE_IDENTIFIER" \
  SNAPZY_URL_NAME="$EXPECTED_BUNDLE_IDENTIFIER" \
  SNAPZY_URL_SCHEME=snapzy-camera \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) DEBUG SNAPZY_CAMERA'

BUILT_APP="$DERIVED_DATA/Build/Products/Debug/Snapzy Debug.app"
if [[ ! -d "$BUILT_APP" ]]; then
  print -u2 "Build completed without the expected app bundle: $BUILT_APP"
  exit 1
fi

/usr/libexec/PlistBuddy -c 'Set :CFBundleName Snapzy Camera' "$BUILT_APP/Contents/Info.plist"

BUILT_IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUILT_APP/Contents/Info.plist")
BUILT_SCHEME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$BUILT_APP/Contents/Info.plist")
if [[ "$BUILT_IDENTIFIER" != "$EXPECTED_BUNDLE_IDENTIFIER" || "$BUILT_SCHEME" != "snapzy-camera" ]]; then
  print -u2 "Refusing to install an app with unexpected identity: $BUILT_IDENTIFIER / $BUILT_SCHEME"
  exit 1
fi

# First sign nested code, then re-sign only the outer bundle with a stable
# designated requirement. A default ad-hoc signature uses the build's cdhash
# as its requirement, so macOS TCC keeps showing an enabled Screen Recording
# toggle while rejecting the next locally rebuilt app as a different identity.
/usr/bin/codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$BUILT_APP"
/usr/bin/codesign \
  --force \
  --sign - \
  --entitlements "$ENTITLEMENTS" \
  --requirements "=$DESIGNATED_REQUIREMENT" \
  "$BUILT_APP"
/usr/bin/codesign --verify --deep --strict "$BUILT_APP"

BUILT_REQUIREMENT=$(/usr/bin/codesign -d -r- "$BUILT_APP" 2>&1 | tail -1)
if [[ "$BUILT_REQUIREMENT" != "$DESIGNATED_REQUIREMENT" ]]; then
  print -u2 "Refusing to install an app with an unstable designated requirement: $BUILT_REQUIREMENT"
  exit 1
fi

if [[ -e "$INSTALL_APP" ]]; then
  BACKUP_APP="$HOME/.Trash/Snapzy Camera previous $(date +%Y%m%d-%H%M%S).app"
  mv "$INSTALL_APP" "$BACKUP_APP"
  print "Previous custom build moved to: $BACKUP_APP"
fi

/usr/bin/ditto "$BUILT_APP" "$INSTALL_APP"
/usr/bin/codesign --verify --deep --strict "$INSTALL_APP"

INSTALLED_REQUIREMENT=$(/usr/bin/codesign -d -r- "$INSTALL_APP" 2>&1 | tail -1)
if [[ "$INSTALLED_REQUIREMENT" != "$DESIGNATED_REQUIREMENT" ]]; then
  print -u2 "Installed app has an unexpected designated requirement: $INSTALLED_REQUIREMENT"
  exit 1
fi

print "Installed: $INSTALL_APP"
print "Bundle ID: $BUILT_IDENTIFIER"
print "URL scheme: $BUILT_SCHEME://"
print "Designated requirement: $INSTALLED_REQUIREMENT"
