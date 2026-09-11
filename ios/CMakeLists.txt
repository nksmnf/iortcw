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

# Which game this build is: SP is the single-player campaign, MP is Return to
# Castle Wolfenstein Multiplayer. They are two independent source trees that
# share an engine lineage but not their symbols, so a build is one or the other
# -- never both in one binary. Set before project() because the project name,
# and therefore the .xcodeproj filename, follows it.
set(IORTCW_TREE "SP" CACHE STRING "Which source tree to build: SP or MP")
set_property(CACHE IORTCW_TREE PROPERTY STRINGS SP MP)
if(NOT IORTCW_TREE MATCHES "^(SP|MP)$")
    message(FATAL_ERROR "IORTCW_TREE must be SP or MP, got '${IORTCW_TREE}'")
endif()

if(IORTCW_TREE STREQUAL "MP")
    set(IORTCW_IS_MP ON)
    project(iortcw_mp LANGUAGES C CXX OBJC)
else()
    set(IORTCW_IS_MP OFF)
    project(iortcw_sp LANGUAGES C CXX OBJC)
endif()

# Swift is only needed for the launcher UI, and only on iOS.
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    enable_language(Swift)
endif()

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 14)

set(TREE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../${IORTCW_TREE}")
cmake_path(NORMAL_PATH TREE_DIR)

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

if(IORTCW_IS_MP)
    include(cmake/sources.generated.mp.cmake)
else()
    include(cmake/sources.generated.cmake)
endif()
include(cmake/StaticVM.cmake)

# Turn the Makefile-relative paths from the generated file into absolute ones.
function(iortcw_abs out_var)
    set(_abs "")
    foreach(s ${ARGN})
        list(APPEND _abs "${TREE_DIR}/${s}")
    endforeach()
    set(${out_var} ${_abs} PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# The port's own version, separate from the engine's. The engine is iortcw
# 1.51d-SP wherever it runs; this number is about the iPadOS build.
set(IORTCW_PORT_VERSION "0.6.6")

# Build number and commit, both read from git.
#
# The number used to be the date, which could not do the one job it had: two
# builds made on the same day -- exactly the pair worth telling apart -- came
# out identical. The commit count grows with the history instead. Nothing has
# to be kept in the tree for it, unlike a counter file, which would show up as
# a local change after every build, and it is derived rather than stored, so
# the same source always gives the same number.
#
# CFBundleVersion has to stay an integer, so the commit itself rides along
# separately in IORTCWGitHash. The number says which build, the hash says which
# code.
find_package(Git QUIET)

# No git -- a source archive, or a machine without it installed -- is not worth
# failing a configure over. 0 and an empty hash read as "unknown", which is
# exactly what is known in that case.
set(IORTCW_BUILD_NUMBER "0")
set(IORTCW_GIT_HASH "")

if(Git_FOUND)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" rev-list --count HEAD
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        OUTPUT_VARIABLE _git_count
        RESULT_VARIABLE _git_result
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET)
endif()

# Outside a repository, and in one that has no commits yet, git answers with an
# error rather than a number; the fallback above then stands.
if(_git_result EQUAL 0 AND _git_count MATCHES "^[0-9]+$")
    set(IORTCW_BUILD_NUMBER "${_git_count}")

    execute_process(
        COMMAND "${GIT_EXECUTABLE}" rev-parse --short HEAD
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        OUTPUT_VARIABLE IORTCW_GIT_HASH
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET)

    # --no-optional-locks so that looking at the tree does not write to it:
    # plain git status refreshes and rewrites the index as a side effect, which
    # is not something a build should be doing to someone's repository.
    #
    # Untracked files count as dirty on purpose. The launcher's sources are
    # globbed, so a file that is in no commit can still be in the binary;
    # everything a build produces is gitignored and stays out of this.
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" --no-optional-locks status --porcelain
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        OUTPUT_VARIABLE _git_dirty
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET)
    if(NOT _git_dirty STREQUAL "")
        string(APPEND IORTCW_GIT_HASH "-dirty")
    endif()

    # Both values are read once, while cmake runs. A build tree left to itself
    # would therefore keep reporting the commit it was generated on, and a
    # build number that lies is worse than none at all. git rewrites HEAD on a
    # checkout and appends to logs/HEAD whenever HEAD moves at all, so watching
    # those two makes the generated build system re-run cmake by itself exactly
    # when the number changes -- on the next build, before anything is linked.
    #
    # An edit that is not committed touches neither file, so -dirty appears at
    # the next configure rather than at the moment of the edit.
    # ios/scripts/build-ipa.sh configures on every run, so what ships is never
    # stale.
    foreach(_git_file HEAD logs/HEAD)
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" rev-parse --git-path ${_git_file}
            WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
            OUTPUT_VARIABLE _git_watch
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET)
        # --git-path answers relative to the working directory in a plain
        # checkout and absolutely in a linked worktree. Reflogs can also be
        # switched off, in which case logs/HEAD is simply not there.
        get_filename_component(_git_watch "${_git_watch}"
            ABSOLUTE BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
        if(EXISTS "${_git_watch}")
            set_property(DIRECTORY APPEND PROPERTY
                CMAKE_CONFIGURE_DEPENDS "${_git_watch}")
        endif()
    endforeach()
endif()

message(STATUS
    "iORTCW port ${IORTCW_PORT_VERSION}, build ${IORTCW_BUILD_NUMBER} ${IORTCW_GIT_HASH}")

# Version string, mirroring the Makefile's PRODUCT_VERSION
# ---------------------------------------------------------------------------
file(STRINGS "${TREE_DIR}/Makefile" _ver_line REGEX "^VERSION=")
string(REGEX REPLACE "^VERSION=[ \t]*" "" IORTCW_VERSION "${_ver_line}")
if(NOT IORTCW_VERSION)
    set(IORTCW_VERSION "1.51d-${IORTCW_TREE}")
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

if(IORTCW_IS_MP)
    # Lets the shared launcher and bridge sources tell which game they are in.
    target_compile_definitions(iortcw_common INTERFACE IORTCW_MP_BUILD)
endif()

# ---------------------------------------------------------------------------
# Info.plist keys that only the multiplayer build needs.
#
# Substituted into Resources/Info.plist.in, which is shared by both apps. Empty
# for SP: a single-player game that asks for the local network on first launch
# looks exactly like something to be suspicious of.
# ---------------------------------------------------------------------------
if(IORTCW_IS_MP)
    set(IORTCW_PLIST_MP_KEYS
"\t<!-- Hosting has to survive the app leaving the screen. There is no
\t     background mode for a listening socket, so we use the audio one and
\t     render silence; see Sources/ios_keepalive.m for the full reasoning. -->
\t<key>UIBackgroundModes</key>
\t<array>
\t\t<string>audio</string>
\t</array>

\t<!-- iOS 14+ gates LAN traffic behind an explicit prompt. Without this key
\t     the engine's broadcast and IPv6 multicast scan are dropped silently,
\t     and the LAN tab of the server browser is simply always empty. -->
\t<key>NSLocalNetworkUsageDescription</key>
\t<string>Поиск серверов Return to Castle Wolfenstein в локальной сети и размещение своего сервера.</string>
\t<key>NSBonjourServices</key>
\t<array>
\t\t<string>_wolfmp._udp</string>
\t</array>
")
else()
    set(IORTCW_PLIST_MP_KEYS "")
endif()

target_include_directories(iortcw_common INTERFACE
    "${TREE_DIR}/code/zlib-1.2.11"
    "${TREE_DIR}/code/jpeg-8c"
    "${TREE_DIR}/code/freetype-2.9/include"
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

    # Applied here rather than as a PATCH_COMMAND so that it also reaches a
    # tree that was fetched before the patch existed. It only edits sources, so
    # running after SDL has been configured is soon enough; the compiler picks
    # the change up on the next build. See the file for what it does and why.
    set(IORTCW_SDL_SOURCE_DIR "${sdl2_SOURCE_DIR}")
    include(cmake/patch-sdl.cmake)

    set(IORTCW_SDL_TARGET SDL2-static)
    set(IORTCW_SDL_MAIN   SDL2main)
else()
    # macOS reuses the prebuilt universal dylib the Makefile ships with.
    target_include_directories(iortcw_common INTERFACE "${TREE_DIR}/code/SDL2/include")
    set(IORTCW_SDL_TARGET "${TREE_DIR}/code/libs/macosx/libSDL2-2.0.0.dylib")
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
    target_include_directories(iortcw_renderer PRIVATE "${TREE_DIR}/code/SDL2/include")
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
        "${TREE_DIR}/code/sys/con_passive.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/sys_ios.m"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ios_dualsense.m"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ios_touch.m"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ios_perf.m"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ios_gyro.m"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ios_bridge.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ios_keepalive.m"
    )
endif()

# vm_static.c is new and therefore not in the Makefile-derived list.
list(APPEND ENGINE_SRC "${TREE_DIR}/code/qcommon/vm_static.c")

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
    "${TREE_DIR}/code/libvorbis-1.3.6/include"
    "${TREE_DIR}/code/libvorbis-1.3.6/lib"
    "${TREE_DIR}/code/libogg-1.3.3/include"
)
if(IORTCW_IOS)
    target_link_libraries(iortcw_engine PRIVATE ${IORTCW_SDL_TARGET})
endif()

# ---------------------------------------------------------------------------
# Game modules, linked in rather than dlopen'd
# ---------------------------------------------------------------------------
set(VM_INCLUDES "${TREE_DIR}/code/SDL2/include")
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
    # CONFIGURE_DEPENDS so that a file added to the launcher later is picked up
    # by an existing build tree, rather than silently left out of the link.
    file(GLOB LAUNCHER_SWIFT CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/Launcher/*.swift")
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
    # No space in the product name: it becomes the .app filename and the
    # executable inside it, and both are handled by shell scripts. The name the
    # player sees is CFBundleDisplayName, set just below.
    if(IORTCW_IS_MP)
        set(APP_NAME iORTCW-MP)
        set(IORTCW_DISPLAY_NAME "iORTCW MP")
    else()
        set(APP_NAME iORTCW)
        set(IORTCW_DISPLAY_NAME "iORTCW")
    endif()
    # The asset catalogue carries the app icon. It has to be a source of the
    # target, not just a bundle resource, so Xcode runs actool over it.
    set(ASSET_CATALOG "${CMAKE_CURRENT_SOURCE_DIR}/Resources/Assets.xcassets")
    set_source_files_properties(${ASSET_CATALOG} PROPERTIES
        MACOSX_PACKAGE_LOCATION Resources)

    add_executable(${APP_NAME} MACOSX_BUNDLE
        ${qagame_MOD_OBJ} ${cgame_MOD_OBJ} ${ui_MOD_OBJ}
        ${ASSET_CATALOG})

    if(IORTCW_IS_MP)
        set(IORTCW_DEFAULT_BUNDLE_ID "com.iortcw.mp")
    else()
        set(IORTCW_DEFAULT_BUNDLE_ID "com.iortcw.sp")
    endif()
    set(IORTCW_BUNDLE_ID "${IORTCW_DEFAULT_BUNDLE_ID}" CACHE STRING
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
    if(IORTCW_IS_MP)
        set(APP_NAME iowolfmp_cmake)
    else()
        set(APP_NAME iowolfsp_cmake)
    endif()
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
