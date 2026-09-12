#!/bin/sh
# Pull the per-campaign console logs off the iPad and summarise them.
#
#   ios/scripts/campaign-logs.sh [device-udid]
#
# The engine truncates rtcwconsole.log on every start, so the launcher keeps the
# previous run of each campaign under Documents/logs/ before it does -- two
# generations per campaign, named after the campaign folder. This fetches the
# lot into build/logs/ and prints one line per log: did the map load, did the
# navigation mesh come up, what was missing.
#
# Set IORTCW_TREE=MP for the multiplayer application's container.
set -e

TREE="${IORTCW_TREE:-SP}"
case "$TREE" in
    SP) BUNDLE="com.iortcw.sp" ;;
    MP) BUNDLE="com.iortcw.mp" ;;
    *)  echo "error: IORTCW_TREE must be SP or MP, got '$TREE'" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/logs"

if [ -z "$DEVELOPER_DIR" ] && [ -d /Applications/Xcode.app ]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    export DEVELOPER_DIR
fi

DEVICE="$1"
if [ -z "$DEVICE" ]; then
    # First paired device. With one iPad on the desk this is the one.
    DEVICE=$(xcrun devicectl list devices 2>/dev/null \
        | awk 'NR > 2 && $NF ~ /^\(/ { print $(NF-1); exit }')
fi

if [ -z "$DEVICE" ]; then
    echo "error: no device; pass its identifier as the first argument" >&2
    echo "       xcrun devicectl list devices" >&2
    exit 1
fi

mkdir -p "$OUT"
rm -rf "$OUT/logs"

echo "Fetching from $DEVICE ($BUNDLE) ..."
xcrun devicectl device copy from \
    --device "$DEVICE" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE" \
    --source Documents/logs \
    --destination "$OUT" > /dev/null

if [ ! -d "$OUT/logs" ]; then
    echo "No logs on the device yet -- play a campaign first."
    exit 0
fi

echo
printf '%-28s %6s %5s %5s %7s  %s\n' "log" "lines" "map" "aas" "errors" "first problem"

for log in "$OUT"/logs/*.log; do
    [ -f "$log" ] || continue
    name=$(basename "$log" .log)
    lines=$(wc -l < "$log" | tr -d ' ')
    map=$(grep -c "Map Loading" "$log" || true)
    aas=$(grep -c "AAS initialized" "$log" || true)
    errs=$(grep -ciE "^ERROR|Com_Error|RE_LoadWorldMap: |CM_LoadMap: |couldn't load .*bsp" "$log" || true)

    # The shader warnings the retail game prints on its own maps are noise here;
    # what matters is a file the campaign refers to and does not ship.
    first=$(grep -iE "^ERROR|Com_Error|couldn't load|could not find" "$log" \
        | grep -viE "rtcwhistory|GL_|extension|s3tc|compiled_vertex" \
        | head -1 | cut -c1-52 || true)

    printf '%-28s %6s %5s %5s %7s  %s\n' "$name" "$lines" "$map" "$aas" "$errs" "$first"
done

echo
echo "Logs in $OUT/logs"
