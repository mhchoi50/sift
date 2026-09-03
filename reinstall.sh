#!/bin/bash
# Rebuild Sift and put it back on the phone.
#
# A free Apple developer account signs apps for 7 days, after which Sift stops
# opening. Plug the phone in, run this, done. Nothing else expires.

set -euo pipefail

PROJECT_DIR="$HOME/sift/ios"
BUILD_DIR="$HOME/sift/.build"
BUNDLE_ID="com.mhchoi.sift"

echo "Looking for a connected iPhone…"
UDID=$(xcrun xctrace list devices 2>/dev/null \
    | sed -n '/^== Devices ==/,/^$/p' \
    | grep -iE "iphone" \
    | head -1 \
    | sed -E 's/.*\(([0-9A-Fa-f-]{25,})\)$/\1/')

if [ -z "${UDID:-}" ]; then
    echo
    echo "No iPhone found. Plug it in, unlock it, and tap Trust if asked."
    exit 1
fi

NAME=$(xcrun xctrace list devices 2>/dev/null | grep -i "$UDID" | sed -E 's/ \([0-9.]+\) \(.*//' | head -1)
echo "Found: ${NAME:-iPhone}"
echo

echo "Building…"
xcodebuild \
    -project "$PROJECT_DIR/Sift.xcodeproj" \
    -scheme Sift \
    -configuration Debug \
    -destination "platform=iOS,id=$UDID" \
    -derivedDataPath "$BUILD_DIR" \
    -allowProvisioningUpdates \
    build \
    > "$BUILD_DIR.log" 2>&1 || {
        echo "Build failed. Last lines:"
        grep -iE "error" "$BUILD_DIR.log" | tail -5
        echo
        echo "Full log: $BUILD_DIR.log"
        exit 1
    }

APP="$BUILD_DIR/Build/Products/Debug-iphoneos/Sift.app"
echo "Installing…"
xcrun devicectl device install app --device "$UDID" "$APP" > /dev/null

echo
echo "Done — Sift is good for another 7 days."
echo "If it refuses to open: Settings > General > VPN & Device Management > Trust."

xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" > /dev/null 2>&1 \
    && echo "Launched it for you." || true
