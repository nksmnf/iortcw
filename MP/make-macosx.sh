#!/bin/bash
#

# Let's make the user give us a target build system

if [ $# -ne 1 ]; then
	echo "Usage:   $0 target_architecture"
	echo "Example: $0 x86"
	echo "other valid options are x86_64, ppc or arm64"
	echo
	echo "If you don't know or care about architectures please consider using make-macosx-ub.sh instead of this script."
	exit 1
fi

if [ "$1" == "x86" ]; then
	BUILDARCH=x86
elif [ "$1" == "x86_64" ]; then
	BUILDARCH=x86_64
elif [ "$1" == "ppc" ]; then
	BUILDARCH=ppc
elif [ "$1" == "arm64" ]; then
	BUILDARCH=arm64
else
	echo "Invalid architecture: $1"
	echo "Valid architectures are x86, x86_64, ppc or arm64"
	exit 1
fi

DESTDIR=build/release-darwin-${BUILDARCH}

cd `dirname $0`
if [ ! -f Makefile ]; then
	echo "This script must be run from the iortcw build directory"
	exit 1
fi

# we want to use the oldest available SDK for max compatibility. However 10.4 and older
# can not build 64bit binaries, making 10.5 the minimum version.   This has been tested
# with xcode 3.1 (xcode31_2199_developerdvd.dmg).  It contains the 10.5 SDK and a decent
# enough gcc to actually compile iortcw
# For PPC macs, G4's or better are required to run iortcw.
# Modern systems have no /Developer/SDKs at all, in which case the default SDK of
# whatever compiler CC points at (clang from Xcode or the Command Line Tools) is used.

unset ARCH_SDK
unset ARCH_CFLAGS
unset ARCH_MACOSX_VERSION_MIN

MACOS_VERSION=$(sw_vers -productVersion)
MACOS_MAJOR_VER=$(echo $MACOS_VERSION | awk -F. '{print $1}')
MACOS_MINOR_VER=$(echo $MACOS_VERSION | awk -F. '{print $2}')
# macOS 11 and later are versioned "26.1" or even just "26", so the minor
# version may be missing entirely
MACOS_MINOR_VER=${MACOS_MINOR_VER:-0}

# SDL 2.0.1 (ppc) supports MacOSX 10.5
# SDL 2.0.5+ (x86, x86_64) supports MacOSX 10.6 and later
# SDL 2.0.14+ (arm64) supports MacOSX 11.0 and later
if [ $BUILDARCH = "arm64" ]; then
	# Apple Silicon did not exist before macOS 11.0 and the toolchain clamps
	# anything older to it anyway
	ARCH_MACOSX_VERSION_MIN="11.0"
elif [ $BUILDARCH = "ppc" ]; then
	if [ -d /Developer/SDKs/MacOSX10.5.sdk ]; then
		ARCH_SDK=/Developer/SDKs/MacOSX10.5.sdk
		ARCH_CFLAGS="-isysroot /Developer/SDKs/MacOSX10.5.sdk"
	fi
	ARCH_MACOSX_VERSION_MIN="10.5"
elif [ -d /Developer/SDKs/MacOSX10.6.sdk ]; then
	ARCH_SDK=/Developer/SDKs/MacOSX10.6.sdk
	ARCH_CFLAGS="-isysroot /Developer/SDKs/MacOSX10.6.sdk"
	ARCH_MACOSX_VERSION_MIN="10.6"
elif [ $MACOS_MAJOR_VER -gt 10 ] || { [ $MACOS_MAJOR_VER -eq 10 ] && [ $MACOS_MINOR_VER -ge 9 ]; }; then
	ARCH_MACOSX_VERSION_MIN="10.9"
else
	ARCH_MACOSX_VERSION_MIN="10.7"
fi


echo "Building ${BUILDARCH} Client/Dedicated Server for macOS ${ARCH_MACOSX_VERSION_MIN} and later against ${ARCH_SDK:-the default SDK}"
sleep 3

if [ ! -d $DESTDIR ]; then
	mkdir -p $DESTDIR
fi

# For parallel make on multicore boxes...
NCPU=`sysctl -n hw.ncpu`


# intel client and server
#if [ -d build/release-darwin-${BUILDARCH} ]; then
#	rm -r build/release-darwin-${BUILDARCH}
#fi
(ARCH=${BUILDARCH} CFLAGS="$ARCH_CFLAGS" MACOSX_VERSION_MIN=$ARCH_MACOSX_VERSION_MIN make -j$NCPU) || exit 1;

# use the following shell script to build an application bundle
export MACOSX_DEPLOYMENT_TARGET="${ARCH_MACOSX_VERSION_MIN}"
export MACOSX_DEPLOYMENT_TARGET_PPC=
export MACOSX_DEPLOYMENT_TARGET_X86=
export MACOSX_DEPLOYMENT_TARGET_X86_64=
export MACOSX_DEPLOYMENT_TARGET_ARM64=
"./make-macosx-app.sh" release ${BUILDARCH}
