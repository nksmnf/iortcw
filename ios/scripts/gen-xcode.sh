#!/bin/sh
# Generate the Xcode project for the iPadOS build.
#
#   ios/scripts/gen-xcode.sh [device|simulator]
#
# Afterwards, open build/ios/iortcw_sp.xcodeproj (or build/ios-sim/...), pick
# the iORTCW scheme, set your signing team on the target, and run.
#
# The project is generated, not committed: the source lists come from
# SP/Makefile via ios/cmake/extract_sources.py, so they cannot drift from the
# macOS build. Re-run this after adding or removing source files.

set -e

TARGET="${1:-device}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# xcode-select often points at the Command Line Tools, which have no iOS SDK.
if [ -z "$DEVELOPER_DIR" ] && [ -d /Applications/Xcode.app ]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    export DEVELOPER_DIR
fi

case "$TARGET" in
    device)
        BUILD_DIR="$ROOT/build/ios"
        SYSROOT_ARG=""
        ;;
    simulator|sim)
        BUILD_DIR="$ROOT/build/ios-sim"
        SYSROOT_ARG="-DCMAKE_OSX_SYSROOT=iphonesimulator"
        ;;
    *)
        echo "usage: $0 [device|simulator]" >&2
        exit 1
        ;;
esac

echo "Generating Xcode project for $TARGET in $BUILD_DIR"

cmake -S "$ROOT/ios" -B "$BUILD_DIR" -GXcode \
      -DCMAKE_SYSTEM_NAME=iOS \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
      -DCMAKE_OSX_ARCHITECTURES=arm64 \
      $SYSROOT_ARG \
      "$@"

echo
echo "Done. Open:"
echo "  $BUILD_DIR/iortcw_sp.xcodeproj"
