#!/bin/bash

cd `dirname $0`
if [ ! -f Makefile ]; then
	echo "This script must be run from the iortcw build directory"
	exit 1
fi

# A universal binary means x86_64 + arm64 nowadays.  The ppc and 32 bit x86
# slices this script used to build need the 10.5/10.6 SDKs from the Xcode 3
# install disk (xcode31_2199_developerdvd.dmg) and a toolchain that can still
# emit code for them, neither of which exists on a machine new enough to run
# Apple Silicon binaries.  The bundled libraries in code/libs/macosx are fat
# and do still carry ppc/i386 slices, so run make-macosx.sh on such an old
# machine if that is what you need.

UB_ARCHS="x86_64 arm64"
LIBSDIR=code/libs/macosx
UB_LIBS="$LIBSDIR/libSDL2-2.0.0.dylib $LIBSDIR/libSDL2main.a $LIBSDIR/libopenal.dylib"

# 11.0 is the first macOS release that runs on Apple Silicon and the toolchain
# clamps anything older to it anyway.  x86_64 uses the same minimum version as
# make-macosx.sh does.
X86_64_MACOSX_VERSION_MIN="10.9"
ARM64_MACOSX_VERSION_MIN="11.0"

CC=${CC:-cc}

# make-macosx.sh wants the same architecture names the Makefile uses, but
# uname -m says "i386" on 32 bit Intel and "Power Macintosh" on PPC
HOST_ARCH=`uname -m`
case "${HOST_ARCH}" in
	i?86)			HOST_ARCH="x86" ;;
	ppc*|*Power*)		HOST_ARCH="ppc" ;;
esac

if ! command -v lipo > /dev/null; then
	echo "\
ERROR: lipo is required to build a universal binary but it was not found.
       Install the Xcode Command Line Tools with 'xcode-select --install',
       or run 'make-macosx.sh ${HOST_ARCH}' to build for this machine only."
	exit 1
fi

# Only promise an architecture we can actually deliver: the compiler has to be
# able to target it and the bundled libraries have to contain a matching slice.
unset MISSING_ARCHS
TESTDIR=`mktemp -d /tmp/iortcw-ub.XXXXXX` || exit 1

for ARCH in $UB_ARCHS; do
	if ! echo 'int main(void){return 0;}' | $CC -arch $ARCH -x c - -o "$TESTDIR/conftest" > /dev/null 2>&1; then
		MISSING_ARCHS="${MISSING_ARCHS}
       ${ARCH}: ${CC} can not build for this architecture"
		continue
	fi

	for LIB in $UB_LIBS; do
		if ! lipo -archs "$LIB" 2> /dev/null | grep -qw $ARCH; then
			MISSING_ARCHS="${MISSING_ARCHS}
       ${ARCH}: ${LIB} has no ${ARCH} slice"
			break
		fi
	done
done

rm -rf "$TESTDIR"

if [ -n "$MISSING_ARCHS" ]; then
	echo "\
ERROR: This script is for building a Universal Binary and it needs every one
       of these architectures: $UB_ARCHS
       The following are not available on this system:$MISSING_ARCHS

       If you just want to compile for your own system run
       'make-macosx.sh ${HOST_ARCH}' instead of this script."

	exit 1
fi

echo "Building a Universal Binary for: $UB_ARCHS"
echo

# For parallel make on multicore boxes...
NCPU=`sysctl -n hw.ncpu`

for ARCH in $UB_ARCHS; do
	if [ $ARCH = "arm64" ]; then
		ARCH_MACOSX_VERSION_MIN="$ARM64_MACOSX_VERSION_MIN"
	else
		ARCH_MACOSX_VERSION_MIN="$X86_64_MACOSX_VERSION_MIN"
	fi

	echo "Building ${ARCH} Client/Dedicated Server for macOS ${ARCH_MACOSX_VERSION_MIN} and later against the default SDK"

	#if [ -d build/release-darwin-${ARCH} ]; then
	#	rm -r build/release-darwin-${ARCH}
	#fi
	(ARCH=${ARCH} MACOSX_VERSION_MIN=$ARCH_MACOSX_VERSION_MIN make -j$NCPU) || exit 1;

	echo;echo
done

# use the following shell script to build a universal application bundle
export MACOSX_DEPLOYMENT_TARGET="$X86_64_MACOSX_VERSION_MIN"
export MACOSX_DEPLOYMENT_TARGET_PPC=
export MACOSX_DEPLOYMENT_TARGET_X86=
export MACOSX_DEPLOYMENT_TARGET_X86_64="$X86_64_MACOSX_VERSION_MIN"
export MACOSX_DEPLOYMENT_TARGET_ARM64="$ARM64_MACOSX_VERSION_MIN"
"./make-macosx-app.sh" release
