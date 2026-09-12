#!/bin/sh
# Build signed and install straight onto the paired iPad.
#
#   ios/scripts/install-device.sh
#   IORTCW_DEVICE=<udid|name> ios/scripts/install-device.sh
#
# The other route is ios/scripts/build-ipa.sh, which makes an unsigned .ipa for
# AltStore to re-sign. This one signs with the developer account already set up
# on this Mac and hands the app to the device over the CoreDevice tunnel, so
# there is no file to move and no 7-day re-sign to remember.
#
# Installing this way is an *update*: the app container survives, so the game
# data copied into Documents and every savegame stay where they are. That holds
# only while the bundle identifier does, which is why IORTCW_BUNDLE_ID is pinned.

set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$ROOT/build/ios"
APP_NAME="iORTCW"
BUNDLE="${IORTCW_BUNDLE_ID:-com.iortcw.sp}"

if [ -z "$DEVELOPER_DIR" ] && [ -d /Applications/Xcode.app ]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    export DEVELOPER_DIR
fi

# The team comes from the provisioning profile that is actually installed for
# this bundle identifier, not from a constant in the file: it is a property of
# whoever's Mac this is, not of the port. The id inside the signing identity's
# parentheses looks similar and is a different thing, so it is not used.
TEAM="${IORTCW_TEAM:-}"
if [ -z "$TEAM" ]; then
    for p in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.mobileprovision; do
        [ -f "$p" ] || continue
        plist=$(mktemp -t iortcwprof)
        security cms -D -i "$p" > "$plist" 2>/dev/null || { rm -f "$plist"; continue; }
        appid=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$plist" 2>/dev/null || true)
        case "$appid" in
            *".$BUNDLE")
                TEAM=$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$plist" 2>/dev/null || true)
                rm -f "$plist"
                break
                ;;
        esac
        rm -f "$plist"
    done
fi

if [ -z "$TEAM" ]; then
    echo "error: no provisioning profile for $BUNDLE on this Mac." >&2
    echo "       Open the project in Xcode once, pick the signing team, and" >&2
    echo "       let it create one -- or pass IORTCW_TEAM=<team id>." >&2
    exit 1
fi

# The identifier devicectl wants is the CoreDevice UUID in the first column of
# its own listing, not the hardware UDID.
DEVICE="${IORTCW_DEVICE:-}"
if [ -z "$DEVICE" ]; then
    DEVICE=$(xcrun devicectl list devices 2>/dev/null \
             | awk '/iPad/ { for (i = 1; i <= NF; i++)
                                 if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{4}-/) { print $i; exit } }')
fi

if [ -z "$DEVICE" ]; then
    echo "error: no paired iPad found -- plug it in, or check that it is" >&2
    echo "       trusted (it should show up in 'xcrun devicectl list devices')." >&2
    exit 1
fi

echo "==> Generating project"
"$ROOT/ios/scripts/gen-xcode.sh" device > /dev/null

echo "==> Building $APP_NAME (Release, signed, team $TEAM)"
cmake --build "$BUILD_DIR" --config Release -- \
      -quiet \
      -allowProvisioningUpdates \
      DEVELOPMENT_TEAM="$TEAM" \
      CODE_SIGN_STYLE=Automatic

APP="$BUILD_DIR/Release-iphoneos/$APP_NAME.app"
if [ ! -d "$APP" ]; then
    echo "error: $APP was not produced" >&2
    exit 1
fi

echo "==> Installing on $DEVICE"
xcrun devicectl device install app --device "$DEVICE" "$APP"

echo
echo "Installed. The app container was kept, so the game data and the saves"
echo "are where they were."
