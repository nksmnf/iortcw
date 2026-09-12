# Engine.cmake -- build one game tree into a single relocatable object.
#
# The application carries both games. SP/ and MP/ are two copies of the same
# engine: 2132 of their ~2200 global symbols have identical names, so they
# cannot simply be linked side by side.
#
# The way out is the one already used for the three game modules, scaled up to
# the whole engine. Each tree is compiled into its own set of static libraries,
# those are collapsed with `ld -r -all_load` into one object, and an explicit
# export list leaves exactly the handful of symbols the outside needs:
#
#     SP_EngineMain          the entry point, aliased from the tree's main
#     SP_IOSBridge_*         the launcher bridge, one copy per tree
#
# Everything else -- all 2200 of them -- is demoted to a local symbol by ld,
# which is what makes two copies able to coexist. `ios_dispatch.c` then defines
# the unprefixed IOSBridge_* the launcher calls and forwards to whichever game
# is running.
#
# Why the bridge is duplicated rather than shared: it talks to the engine
# (Cvar_Set, Cbuf_AddText, Key_SetBinding, com_fullyInitialized), and those are
# exactly the symbols being hidden. One copy per engine, chosen at runtime, is
# far less invasive than rewriting the bridge against a function table.

include(${CMAKE_CURRENT_LIST_DIR}/StaticVM.cmake)

# The bridge functions the launcher calls, read from the header so the two
# cannot drift. Anything declared there is exported from each tree under its
# prefix and forwarded by ios_dispatch.c.
function(iortcw_bridge_symbols out_var)
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ios_bridge.h" _hdr)
    string(REGEX MATCHALL "\n[A-Za-z_][A-Za-z0-9_ *]*[ *](IOSBridge_[A-Za-z0-9_]+|Sys_IOS_Launcher[A-Za-z0-9_]+)[ ]*\\(" _matches "${_hdr}")

    set(_names "")
    foreach(_m ${_matches})
        string(REGEX MATCH "(IOSBridge_[A-Za-z0-9_]+|Sys_IOS_Launcher[A-Za-z0-9_]+)" _n "${_m}")
        if(_n)
            list(APPEND _names "${_n}")
        endif()
    endforeach()

    list(REMOVE_DUPLICATES _names)
    list(SORT _names)
    set(${out_var} ${_names} PARENT_SCOPE)
endfunction()

# iortcw_build_engine(SP) -> target iortcw_engine_SP, object ${SP_ENGINE_OBJ}
function(iortcw_build_engine TREE)
    set(_dir "${CMAKE_CURRENT_SOURCE_DIR}/../${TREE}")
    cmake_path(NORMAL_PATH _dir)

    # Source lists come from the tree's own Makefile, via extract_sources.py.
    if(TREE STREQUAL "MP")
        include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/sources.generated.mp.cmake)
    else()
        include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/sources.generated.cmake)
    endif()

    file(STRINGS "${_dir}/Makefile" _ver_line REGEX "^VERSION=")
    string(REGEX REPLACE "^VERSION=[ \t]*" "" _version "${_ver_line}")
    if(NOT _version)
        set(_version "1.51d-${TREE}")
    endif()

    # Absolute paths, relative to this tree.
    function(_abs out_var)
        set(_a "")
        foreach(s ${ARGN})
            list(APPEND _a "${_dir}/${s}")
        endforeach()
        set(${out_var} ${_a} PARENT_SCOPE)
    endfunction()

    # --- per-tree compile settings -----------------------------------------
    add_library(iortcw_common_${TREE} INTERFACE)
    target_link_libraries(iortcw_common_${TREE} INTERFACE iortcw_common)
    target_compile_definitions(iortcw_common_${TREE} INTERFACE
        PRODUCT_VERSION="${_version}")
    target_include_directories(iortcw_common_${TREE} INTERFACE
        "${_dir}/code/zlib-1.2.11"
        "${_dir}/code/jpeg-8c"
        "${_dir}/code/freetype-2.9/include")
    if(TREE STREQUAL "MP")
        target_compile_definitions(iortcw_common_${TREE} INTERFACE IORTCW_MP_BUILD)
    endif()

    # Objective-C classes are registered with the runtime by name, and `ld -r`
    # cannot localise that the way it does a C symbol. Both engines carry the
    # platform layer, so without this the runtime sees two IORTCWTouchOverlay
    # classes, keeps one, and the game ends up talking to the copy belonging to
    # the engine that is not running -- the on-screen controls appear and then
    # do nothing at all, which is exactly how it failed.
    #
    # Renaming through the preprocessor keeps the sources free of it.
    foreach(_cls IORTCWTouchOverlay IORTCWTouchStick IORTCWTouchButton
                 IORTCWTouchController IORTCWDisplayLinkTarget)
        target_compile_definitions(iortcw_common_${TREE} INTERFACE
            ${_cls}=${_cls}_${TREE})
    endforeach()

    # --- vendored ----------------------------------------------------------
    _abs(JPEG_SRC ${IORTCW_JPEG_SOURCES})
    add_library(iortcw_jpeg_${TREE} STATIC ${JPEG_SRC})
    target_link_libraries(iortcw_jpeg_${TREE} PRIVATE iortcw_common_${TREE})

    _abs(FT_SRC ${IORTCW_FREETYPE_SOURCES})
    add_library(iortcw_freetype_${TREE} STATIC ${FT_SRC})
    target_link_libraries(iortcw_freetype_${TREE} PRIVATE iortcw_common_${TREE})

    # --- renderer ----------------------------------------------------------
    _abs(REND_SRC ${IORTCW_RENDERER_SOURCES})
    add_library(iortcw_renderer_${TREE} STATIC ${REND_SRC})
    target_link_libraries(iortcw_renderer_${TREE} PRIVATE iortcw_common_${TREE})
    target_compile_definitions(iortcw_renderer_${TREE} PRIVATE USE_BLOOM)
    if(IORTCW_IOS)
        target_link_libraries(iortcw_renderer_${TREE} PRIVATE ${IORTCW_SDL_TARGET})
    else()
        target_include_directories(iortcw_renderer_${TREE} PRIVATE "${_dir}/code/SDL2/include")
    endif()

    # --- engine ------------------------------------------------------------
    _abs(ENGINE_SRC ${IORTCW_ENGINE_SOURCES})

    if(IORTCW_IOS)
        list(FILTER ENGINE_SRC EXCLUDE REGEX "code/sys/sys_osx\\.m$")
        list(FILTER ENGINE_SRC EXCLUDE REGEX "code/sys/con_tty\\.c$")
        list(APPEND ENGINE_SRC
            "${_dir}/code/sys/con_passive.c"
            "${CMAKE_CURRENT_SOURCE_DIR}/Sources/sys_ios.m"
            "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ios_dualsense.m"
            "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ios_touch.m"
            "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ios_perf.m"
            "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ios_gyro.m"
            "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ios_bridge.c"
            "${CMAKE_CURRENT_SOURCE_DIR}/Sources/ios_keepalive.m"
        )
    endif()

    list(APPEND ENGINE_SRC "${_dir}/code/qcommon/vm_static.c")

    set(BOTLIB_SRC ${ENGINE_SRC})
    list(FILTER BOTLIB_SRC INCLUDE REGEX "code/botlib/")
    list(FILTER ENGINE_SRC EXCLUDE REGEX "code/botlib/")

    add_library(iortcw_botlib_${TREE} STATIC ${BOTLIB_SRC})
    target_link_libraries(iortcw_botlib_${TREE} PRIVATE iortcw_common_${TREE})
    target_compile_definitions(iortcw_botlib_${TREE} PRIVATE BOTLIB)

    add_library(iortcw_engine_${TREE} STATIC ${ENGINE_SRC})
    target_link_libraries(iortcw_engine_${TREE} PRIVATE iortcw_common_${TREE})
    target_compile_definitions(iortcw_engine_${TREE} PRIVATE USE_CODEC_VORBIS USE_BLOOM)
    target_include_directories(iortcw_engine_${TREE} PRIVATE
        "${_dir}/code/libvorbis-1.3.6/include"
        "${_dir}/code/libvorbis-1.3.6/lib"
        "${_dir}/code/libogg-1.3.3/include")
    if(IORTCW_IOS)
        target_link_libraries(iortcw_engine_${TREE} PRIVATE ${IORTCW_SDL_TARGET})
    endif()

    # --- game modules ------------------------------------------------------
    set(VM_INCLUDES "${_dir}/code/SDL2/include")
    if(IORTCW_IOS)
        set(VM_INCLUDES "")
    endif()

    _abs(GAME_SRC  ${IORTCW_GAME_SOURCES})
    _abs(CGAME_SRC ${IORTCW_CGAME_SOURCES})
    _abs(UI_SRC    ${IORTCW_UI_SOURCES})

    set(_defs PRODUCT_VERSION="${_version}")
    if(TREE STREQUAL "MP")
        list(APPEND _defs IORTCW_MP_BUILD)
    endif()

    iortcw_add_vm_module(qagame TARGET_PREFIX ${TREE}_ SOURCES ${GAME_SRC}
        DEFINES GAMEDLL QAGAME ${_defs} INCLUDES ${VM_INCLUDES})
    iortcw_add_vm_module(cgame TARGET_PREFIX ${TREE}_ SOURCES ${CGAME_SRC}
        DEFINES CGAMEDLL CGAME ${_defs} INCLUDES ${VM_INCLUDES})
    iortcw_add_vm_module(ui TARGET_PREFIX ${TREE}_ SOURCES ${UI_SRC}
        DEFINES UI ${_defs} INCLUDES ${VM_INCLUDES})

    # --- collapse into one object -------------------------------------------
    iortcw_bridge_symbols(_bridge)

    set(_exports "_${TREE}_EngineMain")
    set(_aliases -alias ${IORTCW_ENTRY_SYMBOL} _${TREE}_EngineMain)
    foreach(_fn ${_bridge})
        list(APPEND _exports "_${TREE}_${_fn}")
        list(APPEND _aliases -alias "_${_fn}" "_${TREE}_${_fn}")
    endforeach()

    set(_exp_file "${CMAKE_CURRENT_BINARY_DIR}/${TREE}_exports.txt")
    string(REPLACE ";" "\n" _exp_text "${_exports}")
    file(GENERATE OUTPUT "${_exp_file}" CONTENT "${_exp_text}\n")

    set(_out "${CMAKE_CURRENT_BINARY_DIR}/${TREE}_engine.o")

    add_custom_command(
        OUTPUT ${_out}
        COMMAND xcrun -sdk ${IORTCW_LD_SDK} ld -r
                -arch ${IORTCW_LD_ARCH}
                ${IORTCW_LD_PLATFORM_ARGS}
                -o ${_out}
                -all_load
                $<TARGET_FILE:iortcw_engine_${TREE}>
                $<TARGET_FILE:iortcw_botlib_${TREE}>
                $<TARGET_FILE:iortcw_renderer_${TREE}>
                $<TARGET_FILE:iortcw_jpeg_${TREE}>
                $<TARGET_FILE:iortcw_freetype_${TREE}>
                ${${TREE}_qagame_MOD_OBJ}
                ${${TREE}_cgame_MOD_OBJ}
                ${${TREE}_ui_MOD_OBJ}
                ${_aliases}
                -exported_symbols_list ${_exp_file}
        DEPENDS iortcw_engine_${TREE} iortcw_botlib_${TREE}
                iortcw_renderer_${TREE} iortcw_jpeg_${TREE} iortcw_freetype_${TREE}
                ${TREE}_qagame_mod ${TREE}_cgame_mod ${TREE}_ui_mod
                ${_exp_file}
        COMMENT "Collapsing the ${TREE} engine into one object (${TREE}_EngineMain)"
        COMMAND_EXPAND_LISTS
    )

    add_custom_target(${TREE}_engine_obj DEPENDS ${_out})
    set_source_files_properties(${_out} PROPERTIES EXTERNAL_OBJECT TRUE GENERATED TRUE)
    set(${TREE}_ENGINE_OBJ ${_out} PARENT_SCOPE)
endfunction()
