#!/bin/sh
# Build an unsigned .ipa for sideloading with AltStore.
#
#   ios/scripts/build-ipa.sh
#
# The archive is deliberately unsigned: AltStore re-signs the payload with the
# user's own free developer certificate when it installs, and re-signs it again
# every 7 days to keep it alive. Signing here would just be overwritten.
#
# Installing an update this way keeps the app container, so the game data the
# user copied into Documents -- and their savegames -- survive. That only holds
# while the bundle identifier stays the same, which is why IORTCW_BUNDLE_ID is
# pinned rather than generated.

set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$ROOT/build/ios"
OUT_DIR="$ROOT/build/ipa"

if [ -z "$DEVELOPER_DIR" ] && [ -d /Applications/Xcode.app ]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    export DEVELOPER_DIR
fi

if [ ! -d "$BUILD_DIR" ]; then
    echo "No Xcode project yet -- running gen-xcode.sh first."
    "$ROOT/ios/scripts/gen-xcode.sh" device
fi

echo "Building iORTCW (Release, unsigned)..."
cmake --build "$BUILD_DIR" --config Release -- \
      -quiet \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGN_IDENTITY=""

APP="$BUILD_DIR/Release-iphoneos/iORTCW.app"
if [ ! -d "$APP" ]; then
    echo "error: $APP was not produced" >&2
    exit 1
fi

echo "Packaging..."
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/Payload"
cp -R "$APP" "$OUT_DIR/Payload/"

( cd "$OUT_DIR" && zip -qry iORTCW.ipa Payload )
rm -rf "$OUT_DIR/Payload"

SIZE=$(du -h "$OUT_DIR/iORTCW.ipa" | cut -f1)

cat <<EOF

Built $OUT_DIR/iORTCW.ipa ($SIZE)

To install:
  1. Send the .ipa to your iPad and open it with AltStore, or use AltServer.
  2. Launch iORTCW once. It will report that the game data is missing.
  3. In Files -> On My iPad -> iORTCW -> main, copy in from your RTCW install:
        pak0.pk3  sp_pak1.pk3  sp_pak2.pk3  sp_pak3.pk3  sp_pak4.pk3
     The launcher notices them as they arrive; no relaunch needed.
  4. Pair a DualSense over Bluetooth and set your bindings in the launcher.
EOF
