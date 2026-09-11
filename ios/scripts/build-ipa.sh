#!/bin/sh
# Build an unsigned .ipa for sideloading with AltStore.
#
#   ios/scripts/build-ipa.sh            -- the campaign
#   IORTCW_TREE=MP ios/scripts/build-ipa.sh  -- multiplayer
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
TREE="${IORTCW_TREE:-SP}"
export IORTCW_TREE="$TREE"   # gen-xcode.sh reads it too

case "$TREE" in
    SP) SUFFIX=""; APP_NAME="iORTCW"; DATA="pak0.pk3  sp_pak1.pk3  sp_pak2.pk3  sp_pak3.pk3  sp_pak4.pk3" ;;
    MP) SUFFIX="-mp"; APP_NAME="iORTCW-MP"; DATA="pak0.pk3  mp_pak0.pk3 .. mp_pak5.pk3" ;;
    *)  echo "error: IORTCW_TREE must be SP or MP, got '$TREE'" >&2; exit 1 ;;
esac

BUILD_DIR="$ROOT/build/ios$SUFFIX"
OUT_DIR="$ROOT/build/ipa$SUFFIX"

if [ -z "$DEVELOPER_DIR" ] && [ -d /Applications/Xcode.app ]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    export DEVELOPER_DIR
fi

# Always regenerate. CMake only rewrites what changed, and skipping this when
# the directory already exists silently builds an out-of-date file list --
# which shows up much later as undefined symbols at link time.
echo "==> Generating project"
"$ROOT/ios/scripts/gen-xcode.sh" device > /dev/null

echo "Building $APP_NAME (Release, unsigned)..."
cmake --build "$BUILD_DIR" --config Release -- \
      -quiet \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGN_IDENTITY=""

APP="$BUILD_DIR/Release-iphoneos/$APP_NAME.app"
if [ ! -d "$APP" ]; then
    echo "error: $APP was not produced" >&2
    exit 1
fi

echo "Packaging..."
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/Payload"
cp -R "$APP" "$OUT_DIR/Payload/"

( cd "$OUT_DIR" && zip -qry "$APP_NAME.ipa" Payload )
rm -rf "$OUT_DIR/Payload"

SIZE=$(du -h "$OUT_DIR/$APP_NAME.ipa" | cut -f1)

cat <<EOF

Built $OUT_DIR/$APP_NAME.ipa ($SIZE)

To install:
  1. Send the .ipa to your iPad and open it with AltStore, or use AltServer.
  2. Launch $APP_NAME once. It will report that the game data is missing.
  3. In Files -> On My iPad -> $APP_NAME -> main, copy in from your RTCW install:
        $DATA
     The launcher notices them as they arrive; no relaunch needed.
  4. Pair a DualSense over Bluetooth and set your bindings in the launcher.
EOF
