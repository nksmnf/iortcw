#!/bin/sh
# Build, install and launch on the iPad Pro 13" (M5) simulator, with the retail
# data linked into the app container.
#
#   ios/scripts/sim-run.sh [extra engine args...]
#
# Reinstalling gives the app a fresh data container, so the pk3 links have to be
# re-made each time; that is what most of this script is for. The pk3s are
# symlinked rather than copied so 637 MB does not get duplicated per install.

set -e

DEVICE="${IORTCW_SIM_DEVICE:-iortcw-ipad}"
BUNDLE_ID="com.iortcw.sp"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DATA_SRC="${IORTCW_DATA_DIR:-$ROOT/res}"
APP="$ROOT/build/ios-sim/Release-iphonesimulator/iORTCW.app"

if [ -z "$DEVELOPER_DIR" ] && [ -d /Applications/Xcode.app ]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    export DEVELOPER_DIR
fi

echo "==> Building"
cmake --build "$ROOT/build/ios-sim" --config Release -- \
      -quiet CODE_SIGNING_ALLOWED=NO

echo "==> Booting $DEVICE"
xcrun simctl boot "$DEVICE" 2>/dev/null || true

echo "==> Installing"
xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$DEVICE" "$APP"

CONTAINER=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data)
MAIN="$CONTAINER/Documents/main"
mkdir -p "$MAIN"

echo "==> Linking game data from $DATA_SRC"
for f in pak0.pk3 sp_pak1.pk3 sp_pak2.pk3 sp_pak3.pk3 sp_pak4.pk3; do
    if [ -f "$DATA_SRC/$f" ]; then
        ln -sf "$DATA_SRC/$f" "$MAIN/$f"
    else
        echo "   warning: $DATA_SRC/$f not found"
    fi
done

echo "==> Launching"
xcrun simctl launch "$DEVICE" "$BUNDLE_ID" +set logfile 2 "$@"

echo
echo "Engine log: $MAIN/rtcwconsole.log"
echo "Screenshot: xcrun simctl io $DEVICE screenshot shot.png"
