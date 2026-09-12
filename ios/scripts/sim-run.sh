#!/bin/sh
# Build, install and launch on the iPad Pro 13" (M5) simulator, with the retail
# data linked into the app container.
#
#   ios/scripts/sim-run.sh [extra engine args...]
#
# Set IORTCW_TREE=MP for the multiplayer application. It needs a different set
# of pk3s (mp_pak0..5 rather than sp_pak1..4) and installs under its own bundle
# identifier, so the two can sit on the simulator side by side.
#
# Reinstalling gives the app a fresh data container, so the pk3 links have to be
# re-made each time; that is what most of this script is for. The pk3s are
# symlinked rather than copied so 637 MB does not get duplicated per install.

set -e

DEVICE="${IORTCW_SIM_DEVICE:-iortcw-ipad}"
TREE="${IORTCW_TREE:-SP}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DATA_SRC="${IORTCW_DATA_DIR:-$ROOT/res}"

case "$TREE" in
    SP)
        BUNDLE_ID="com.iortcw.sp"
        BUILD_DIR="$ROOT/build/ios-sim"
        APP="$BUILD_DIR/Release-iphonesimulator/iORTCW.app"
        PAKS="pak0.pk3 sp_pak1.pk3 sp_pak2.pk3 sp_pak3.pk3 sp_pak4.pk3"
        ;;
    MP)
        BUNDLE_ID="com.iortcw.mp"
        BUILD_DIR="$ROOT/build/ios-sim-mp"
        APP="$BUILD_DIR/Release-iphonesimulator/iORTCW-MP.app"
        PAKS="pak0.pk3 mp_pak0.pk3 mp_pak1.pk3 mp_pak2.pk3 mp_pak3.pk3 mp_pak4.pk3 mp_pak5.pk3"
        ;;
    *)
        echo "error: IORTCW_TREE must be SP or MP, got '''$TREE'''" >&2
        exit 1
        ;;
esac

if [ -z "$DEVELOPER_DIR" ] && [ -d /Applications/Xcode.app ]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    export DEVELOPER_DIR
fi

echo "==> Building"
cmake --build "$BUILD_DIR" --config Release -- \
      -quiet CODE_SIGNING_ALLOWED=NO

echo "==> Booting $DEVICE"
xcrun simctl boot "$DEVICE" 2>/dev/null || true

echo "==> Installing"
xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$DEVICE" "$APP"

CONTAINER=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data)
MAIN="$CONTAINER/Documents/main"
mkdir -p "$MAIN"

echo "==> Copying game data from $DATA_SRC"
# Copied, not symlinked. A symlink pointing outside the app container is not
# resolved inside the simulator's sandbox, so the engine sees no data at all --
# which looks exactly like a bug in the port and is not one.
for f in $PAKS; do
    if [ ! -f "$DATA_SRC/$f" ]; then
        echo "   warning: $DATA_SRC/$f not found"
        continue
    fi
    if [ -f "$MAIN/$f" ] && [ ! -L "$MAIN/$f" ]; then
        continue    # already copied
    fi
    rm -f "$MAIN/$f"
    echo "   $f"
    cp "$DATA_SRC/$f" "$MAIN/$f"
done

# The Russian localisation, when it is in res/. Optional -- the launcher's
# language switch parks these as *.pk3.off rather than needing them gone.
for f in sp_zpak_russian_text.pk3 sp_zpak_russian_sound.pk3 \
         mp_zpak_russian_text.pk3; do
    [ -f "$DATA_SRC/$f" ] || continue
    [ -f "$MAIN/$f" ] || { echo "   $f"; cp "$DATA_SRC/$f" "$MAIN/$f"; }
done

if [ -f "$DATA_SRC/scripts/translation.cfg" ]; then
    mkdir -p "$MAIN/scripts"
    cp "$DATA_SRC/scripts/translation.cfg" "$MAIN/scripts/translation.cfg"
fi

# Extra campaigns, named rather than all of them: the set is 1.2 GB and a
# simulator install copies rather than links (see above).
#
#   IORTCW_SIM_CAMPAIGNS="time_gate project_x" ios/scripts/sim-run.sh
for c in $IORTCW_SIM_CAMPAIGNS; do
    src="$DATA_SRC/campaigns/$c"
    if [ ! -d "$src" ]; then
        echo "   warning: campaign $c not in $DATA_SRC/campaigns"
        continue
    fi
    mkdir -p "$CONTAINER/Documents/$c"
    for f in "$src"/*; do
        target="$CONTAINER/Documents/$c/$(basename "$f")"
        [ -f "$target" ] || { echo "   campaign $c/$(basename "$f")"; cp "$f" "$target"; }
    done
done

echo "==> Launching"
xcrun simctl launch "$DEVICE" "$BUNDLE_ID" +set logfile 2 "$@"

echo
echo "Engine log: $MAIN/rtcwconsole.log"
echo "Screenshot: xcrun simctl io $DEVICE screenshot shot.png"
