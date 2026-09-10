# iortcw SP -- CMake build for iPadOS, and for macOS as its test bed.
#
# SP/Makefile stays the authority for the plain macOS build. This file exists
# because iOS needs things the Makefile cannot express: a single statically
# linked binary (no dlopen), an app bundle, Swift, and an Xcode project.
#
# The source lists are not duplicated here -- ios/cmake/extract_sources.py asks
# the Makefile what it would build and writes sources.generated.cmake.
#
#   Regenerate:  python3 ios/cmake/extract_sources.py
#   Verify:      python3 ios/cmake/extract_sources.py --check
#
# Configure for macOS (fast iteration, fully playable):
#   cmake -S ios -B build/macos -GNinja
#
# Configure for iOS (device):
#   cmake -S ios -B build/ios -GXcode \
#         -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0

cmake_minimum_required(VERSION 3.24)
project(iortcw_sp LANGUAGES C CXX OBJC)

# Swift is only needed for the launcher UI, and only on iOS.
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    enable_language(Swift)
endif()

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 14)

set(SP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../SP")
cmake_path(NORMAL_PATH SP_DIR)

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(IORTCW_IOS ON)
else()
    set(IORTCW_IOS OFF)
endif()

if(IORTCW_IOS AND CMAKE_OSX_SYSROOT MATCHES "[Ss]imulator")
    set(IORTCW_IOS_SIMULATOR ON)
else()
    set(IORTCW_IOS_SIMULATOR OFF)
endif()

if(NOT CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES arm64)
endif()
list(GET CMAKE_OSX_ARCHITECTURES 0 IORTCW_LD_ARCH)

if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    if(IORTCW_IOS)
        set(CMAKE_OSX_DEPLOYMENT_TARGET 16.0)
    else()
        set(CMAKE_OSX_DEPLOYMENT_TARGET 11.0)
    endif()
endif()

include(cmake/sources.generated.cmake)
include(cmake/StaticVM.cmake)

# Turn the Makefile-relative paths from the generated file into absolute ones.
function(iortcw_abs out_var)
    set(_abs "")
    foreach(s ${ARGN})
        list(APPEND _abs "${SP_DIR}/${s}")
    endforeach()
    set(${out_var} ${_abs} PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# The port's own version, separate from the engine's. The engine is iortcw
# 1.51d-SP wherever it runs; this number is about the iPadOS build.
set(IORTCW_PORT_VERSION "0.2.0")

# Build number: the day it was built. Enough to tell two builds apart, which is
# all it is for, and it does not need a counter kept anywhere.
string(TIMESTAMP IORTCW_BUILD_NUMBER "%Y%m%d" UTC)

# Version string, mirroring the Makefile's PRODUCT_VERSION
# ---------------------------------------------------------------------------
file(STRINGS "${SP_DIR}/Makefile" _ver_line REGEX "^VERSION=")
string(REGEX REPLACE "^VERSION=[ \t]*" "" IORTCW_VERSION "${_ver_line}")
if(NOT IORTCW_VERSION)
    set(IORTCW_VERSION "1.51d-SP")
endif()

# ---------------------------------------------------------------------------
# Shared compile settings
# ---------------------------------------------------------------------------
add_library(iortcw_common INTERFACE)

target_compile_definitions(iortcw_common INTERFACE
    _THREAD_SAFE=1
    NO_VM_COMPILED          # arm64 has no QVM JIT; the interpreter is the fallback
    NO_GZIP
    USE_INTERNAL_JPEG
    BUILD_FREETYPE
    FT2_BUILD_LIBRARY
    USE_LOCAL_HEADERS
    USE_STATIC_VM           # game modules are linked in, see StaticVM.cmake
    PRODUCT_VERSION="${IORTCW_VERSION}"
)

target_include_directories(iortcw_common INTERFACE
    "${SP_DIR}/code/zlib-1.2.11"
    "${SP_DIR}/code/jpeg-8c"
    "${SP_DIR}/code/freetype-2.9/include"
)

# Guarded by language: swiftc rejects clang flags outright ("Driver threw
# unknown argument: '-fno-strict-aliasing'"), and the launcher is Swift.
target_compile_options(iortcw_common INTERFACE
    $<$<COMPILE_LANGUAGE:C,CXX,OBJC,OBJCXX>:-fno-strict-aliasing>
    $<$<COMPILE_LANGUAGE:C,CXX,OBJC,OBJCXX>:-fno-common>
    $<$<COMPILE_LANGUAGE:C,CXX,OBJC,OBJCXX>:-pipe>
    $<$<COMPILE_LANGUAGE:C,CXX,OBJC,OBJCXX>:-Wno-format-nonliteral>
    # The vendored libraries are from 2001-2018 and trip a lot of modern
    # diagnostics that we are not going to fix.
    $<$<COMPILE_LANGUAGE:C,CXX,OBJC,OBJCXX>:-Wno-deprecated-non-prototype>
    $<$<COMPILE_LANGUAGE:C,CXX,OBJC,OBJCXX>:-Wno-implicit-function-declaration>
)

if(IORTCW_IOS)
    target_compile_definitions(iortcw_common INTERFACE
        USE_OPENGLES
        GLES_SILENCE_DEPRECATION   # ES 1.1 is deprecated since iOS 12, not removed
    )
endif()

# ---------------------------------------------------------------------------
# SDL2
# ---------------------------------------------------------------------------
if(IORTCW_IOS)
    include(FetchContent)
    set(SDL_SHARED OFF CACHE BOOL "" FORCE)
    set(SDL_STATIC ON  CACHE BOOL "" FORCE)
    set(SDL_TEST   OFF CACHE BOOL "" FORCE)
    FetchContent_Declare(SDL2
        GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
        GIT_TAG        release-2.32.10
        GIT_SHALLOW    TRUE
    )
    FetchContent_MakeAvailable(SDL2)
    set(IORTCW_SDL_TARGET SDL2-static)
    set(IORTCW_SDL_MAIN   SDL2main)
else()
    # macOS reuses the prebuilt universal dylib the Makefile ships with.
    target_include_directories(iortcw_common INTERFACE "${SP_DIR}/code/SDL2/include")
    set(IORTCW_SDL_TARGET "${SP_DIR}/code/libs/macosx/libSDL2-2.0.0.dylib")
    set(IORTCW_SDL_MAIN "")
endif()

# ---------------------------------------------------------------------------
# Vendored libraries as their own targets, so their warnings stay contained
# ---------------------------------------------------------------------------
iortcw_abs(JPEG_SRC ${IORTCW_JPEG_SOURCES})
add_library(iortcw_jpeg STATIC ${JPEG_SRC})
target_link_libraries(iortcw_jpeg PRIVATE iortcw_common)

iortcw_abs(FT_SRC ${IORTCW_FREETYPE_SOURCES})
add_library(iortcw_freetype STATIC ${FT_SRC})
target_link_libraries(iortcw_freetype PRIVATE iortcw_common)

# ---------------------------------------------------------------------------
# Renderer (statically linked; USE_RENDERER_DLOPEN=0)
# ---------------------------------------------------------------------------
iortcw_abs(REND_SRC ${IORTCW_RENDERER_SOURCES})
add_library(iortcw_renderer STATIC ${REND_SRC})
target_link_libraries(iortcw_renderer PRIVATE iortcw_common)
target_compile_definitions(iortcw_renderer PRIVATE USE_BLOOM)
if(IORTCW_IOS)
    # GLimp lives in the renderer, so it needs SDL's headers. Linking the target
    # is the tidy way to inherit them from FetchContent.
    target_link_libraries(iortcw_renderer PRIVATE ${IORTCW_SDL_TARGET})
else()
    target_include_directories(iortcw_renderer PRIVATE "${SP_DIR}/code/SDL2/include")
endif()

# ---------------------------------------------------------------------------
# Engine (client + server + qcommon + botlib + sdl + sys)
# ---------------------------------------------------------------------------
iortcw_abs(ENGINE_SRC ${IORTCW_ENGINE_SOURCES})

# sys_osx.m is Cocoa/Carbon; con_tty.c wants a terminal. Both are replaced on iOS.
if(IORTCW_IOS)
    list(FILTER ENGINE_SRC EXCLUDE REGEX "code/sys/sys_osx\\.m$")
    list(FILTER ENGINE_SRC EXCLUDE REGEX "code/sys/con_tty\\.c$")
    list(APPEND ENGINE_SRC
        "${SP_DIR}/code/sys/con_passive.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/sys_ios.m"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ios_dualsense.m"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ios_touch.m"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ios_perf.m"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ios_bridge.c"
    )
endif()

# vm_static.c is new and therefore not in the Makefile-derived list.
list(APPEND ENGINE_SRC "${SP_DIR}/code/qcommon/vm_static.c")

# botlib only compiles with -DBOTLIB (its headers key their type definitions off
# it), so it needs its own target rather than riding along with the engine.
set(BOTLIB_SRC ${ENGINE_SRC})
list(FILTER BOTLIB_SRC INCLUDE REGEX "code/botlib/")
list(FILTER ENGINE_SRC EXCLUDE REGEX "code/botlib/")

add_library(iortcw_botlib STATIC ${BOTLIB_SRC})
target_link_libraries(iortcw_botlib PRIVATE iortcw_common)
target_compile_definitions(iortcw_botlib PRIVATE BOTLIB)

add_library(iortcw_engine STATIC ${ENGINE_SRC})
target_link_libraries(iortcw_engine PRIVATE iortcw_common)
target_compile_definitions(iortcw_engine PRIVATE
    USE_CODEC_VORBIS
    USE_BLOOM
)
target_include_directories(iortcw_engine PRIVATE
    "${SP_DIR}/code/libvorbis-1.3.6/include"
    "${SP_DIR}/code/libvorbis-1.3.6/lib"
    "${SP_DIR}/code/libogg-1.3.3/include"
)
if(IORTCW_IOS)
    target_link_libraries(iortcw_engine PRIVATE ${IORTCW_SDL_TARGET})
endif()

# ---------------------------------------------------------------------------
# Game modules, linked in rather than dlopen'd
# ---------------------------------------------------------------------------
set(VM_INCLUDES "${SP_DIR}/code/SDL2/include")
if(IORTCW_IOS)
    set(VM_INCLUDES "")
endif()

iortcw_abs(GAME_SRC  ${IORTCW_GAME_SOURCES})
iortcw_abs(CGAME_SRC ${IORTCW_CGAME_SOURCES})
iortcw_abs(UI_SRC    ${IORTCW_UI_SOURCES})

iortcw_add_vm_module(qagame SOURCES ${GAME_SRC}
    DEFINES GAMEDLL QAGAME PRODUCT_VERSION="${IORTCW_VERSION}"
    INCLUDES ${VM_INCLUDES})
iortcw_add_vm_module(cgame SOURCES ${CGAME_SRC}
    DEFINES CGAMEDLL CGAME PRODUCT_VERSION="${IORTCW_VERSION}"
    INCLUDES ${VM_INCLUDES})
iortcw_add_vm_module(ui SOURCES ${UI_SRC}
    DEFINES UI PRODUCT_VERSION="${IORTCW_VERSION}"
    INCLUDES ${VM_INCLUDES})

# ---------------------------------------------------------------------------
# Launcher (Swift). Kept in its own target so the Swift driver never sees the
# engine's clang flags, and reached from C purely through @_cdecl symbols, which
# avoids the generated -Swift.h header ordering problem entirely.
# ---------------------------------------------------------------------------
if(IORTCW_IOS)
    file(GLOB LAUNCHER_SWIFT "${CMAKE_CURRENT_SOURCE_DIR}/Launcher/*.swift")
    add_library(iortcw_launcher STATIC ${LAUNCHER_SWIFT})
    set_target_properties(iortcw_launcher PROPERTIES
        Swift_MODULE_NAME iortcwLauncher
        XCODE_ATTRIBUTE_SWIFT_VERSION "5.0"
        # A single narrow header rather than the engine's own, which does not
        # import into Swift cleanly.
        XCODE_ATTRIBUTE_SWIFT_OBJC_BRIDGING_HEADER
            "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ios_bridge.h"
    )
endif()

# ---------------------------------------------------------------------------
# The application
# ---------------------------------------------------------------------------
if(IORTCW_IOS)
    set(APP_NAME iORTCW)
    # The asset catalogue carries the app icon. It has to be a source of the
    # target, not just a bundle resource, so Xcode runs actool over it.
    set(ASSET_CATALOG "${CMAKE_CURRENT_SOURCE_DIR}/Resources/Assets.xcassets")
    set_source_files_properties(${ASSET_CATALOG} PROPERTIES
        MACOSX_PACKAGE_LOCATION Resources)

    add_executable(${APP_NAME} MACOSX_BUNDLE
        ${qagame_MOD_OBJ} ${cgame_MOD_OBJ} ${ui_MOD_OBJ}
        ${ASSET_CATALOG})

    set(IORTCW_BUNDLE_ID "com.iortcw.sp" CACHE STRING
        "Bundle identifier. Keep it stable: AltStore preserves the app's
         container -- and therefore the game data and saves -- only while the
         bundle ID and signing team stay the same.")

    set_target_properties(${APP_NAME} PROPERTIES
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Resources/Info.plist.in"
        MACOSX_BUNDLE_EXECUTABLE_NAME "${APP_NAME}"
        MACOSX_BUNDLE_GUI_IDENTIFIER "${IORTCW_BUNDLE_ID}"
        MACOSX_BUNDLE_BUNDLE_NAME "${APP_NAME}"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${IORTCW_PORT_VERSION}"
        MACOSX_BUNDLE_BUNDLE_VERSION "${IORTCW_BUILD_NUMBER}"
        XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${IORTCW_BUNDLE_ID}"
        XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "2"   # iPad
        XCODE_ATTRIBUTE_ENABLE_BITCODE NO
        XCODE_ATTRIBUTE_ASSETCATALOG_COMPILER_APPICON_NAME "AppIcon"
    )
else()
    set(APP_NAME iowolfsp_cmake)
    add_executable(${APP_NAME}
        ${qagame_MOD_OBJ} ${cgame_MOD_OBJ} ${ui_MOD_OBJ})
endif()

add_dependencies(${APP_NAME} qagame_mod cgame_mod ui_mod)

if(IORTCW_IOS)
    target_link_libraries(${APP_NAME} PRIVATE iortcw_launcher)
endif()

target_link_libraries(${APP_NAME} PRIVATE
    iortcw_engine
    iortcw_botlib
    iortcw_renderer
    iortcw_jpeg
    iortcw_freetype
    iortcw_common
)

if(IORTCW_IOS)
    target_link_libraries(${APP_NAME} PRIVATE
        ${IORTCW_SDL_TARGET} ${IORTCW_SDL_MAIN}
        "-framework OpenGLES"
        "-framework UIKit"
        "-framework GameController"
        "-framework CoreHaptics"
        "-framework AVFoundation"
        "-framework AudioToolbox"
        "-framework CoreMotion"
        "-framework QuartzCore"
        "-framework Metal"
        "-framework Foundation"
        "-framework CoreGraphics"
    )
else()
    target_link_libraries(${APP_NAME} PRIVATE
        ${IORTCW_SDL_TARGET}
        "-framework Cocoa"
        "-framework IOKit"
        "-framework OpenGL"
    )
endif()
