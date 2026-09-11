# Stop iPadOS delivering the game controller twice.
#
# Every app on iPadOS gets a connected controller through UIKit as well as
# through GameController, unless it says otherwise: the D-pad and the left
# stick arrive as arrow key presses, and the sticks push the system pointer.
# SDL turns both into input -- keys through pressesBegan in SDL_uikitview.m,
# pointer movement through the indirect-touch path -- and RTCW's stock
# bindings then act on them on top of the pad the engine is already reading.
#
# The damage is worse than "twice". LEFTARROW and RIGHTARROW are bound to +left
# and +right, which turn rather than strafe, and a key turns at cl_yawspeed --
# a fixed 140 degrees a second no matter how gently the stick is leaning. A
# player pushing the movement stick forward and a little to the side therefore
# walked forward while the view span at full speed, which is to say he walked
# in circles.
#
# Apple's switch for this is GCEventViewController.controllerUserInteractionEnabled,
# and the way to reach it is to have one as the root view controller. SDL2 does
# that on tvOS only; SDL3 does it on iOS as well, and this is that change,
# backported to the 2.32 branch we build against.
#
# Written as an idempotent rewrite rather than a .patch so that it survives
# being run again on an already-patched tree -- which is what happens on every
# reconfigure -- and so that it fails loudly if a future SDL moves the code out
# from under it instead of silently doing nothing.

if(NOT DEFINED IORTCW_SDL_SOURCE_DIR)
    message(FATAL_ERROR "patch-sdl.cmake: IORTCW_SDL_SOURCE_DIR is not set")
endif()

set(_marker "iortcw: GCEventViewController on iOS too")

# ---------------------------------------------------------------------------
# 1. Make the root view controller a GCEventViewController on iOS, not just tvOS
# ---------------------------------------------------------------------------
set(_hdr "${IORTCW_SDL_SOURCE_DIR}/src/video/uikit/SDL_uikitviewcontroller.h")
file(READ "${_hdr}" _text)

if(NOT _text MATCHES "${_marker}")
    set(_before "#if TARGET_OS_TV\n#import <GameController/GameController.h>\n#define SDLRootViewController GCEventViewController")
    set(_after  "/* ${_marker} -- see ios/cmake/patch-sdl.cmake. */\n#if TARGET_OS_TV || TARGET_OS_IOS\n#import <GameController/GameController.h>\n#define SDLRootViewController GCEventViewController")

    string(FIND "${_text}" "${_before}" _at)
    if(_at EQUAL -1)
        message(FATAL_ERROR
            "patch-sdl.cmake: SDL_uikitviewcontroller.h no longer contains the "
            "TARGET_OS_TV root view controller block this patch rewrites. "
            "Check what SDL changed before bumping the tag.")
    endif()

    string(REPLACE "${_before}" "${_after}" _text "${_text}")
    file(WRITE "${_hdr}" "${_text}")
    message(STATUS "Patched SDL: GCEventViewController is the root view controller on iOS")
endif()

# ---------------------------------------------------------------------------
# 2. And tell it not to pass controller input on to UIKit
# ---------------------------------------------------------------------------
set(_src "${IORTCW_SDL_SOURCE_DIR}/src/video/uikit/SDL_uikitviewcontroller.m")
file(READ "${_src}" _text)

if(NOT _text MATCHES "${_marker}")
    set(_before "        self.window = _window;\n")
    set(_after  "        self.window = _window;\n\n#if !TARGET_OS_TV\n        /* iortcw: GCEventViewController on iOS too -- see ios/cmake/patch-sdl.cmake.\n           NO stops the system sending the controller through UIKit as well:\n           arrow key presses from the D-pad and sticks, and pointer movement.\n           It is the documented default, and it is set anyway, because what it\n           switches off is not something to leave resting on a default. */\n        self.controllerUserInteractionEnabled = NO;\n#endif\n")

    string(FIND "${_text}" "${_before}" _at)
    if(_at EQUAL -1)
        message(FATAL_ERROR
            "patch-sdl.cmake: SDL_uikitviewcontroller.m no longer assigns "
            "self.window where this patch expects it.")
    endif()

    string(REPLACE "${_before}" "${_after}" _text "${_text}")
    file(WRITE "${_src}" "${_text}")
    message(STATUS "Patched SDL: controller input no longer flows through UIKit")
endif()
