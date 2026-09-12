# StaticVM.cmake -- link qagame/cgame/ui into the executable instead of dlopen'ing them.
#
# iOS refuses to dlopen code outside the signed bundle, and arm64 has no QVM
# compiler, so the game modules have to be part of the binary. Three of them
# share a lot of source (q_math.c, q_shared.c, the bg_*.c family, and
# ui_shared.c is compiled into both cgame and ui), so linking them naively
# produces hundreds of duplicate symbols.
#
# The fix has three parts:
#   1. -fvisibility=hidden, so every symbol is emitted as .private_extern
#      except the two the engine needs, which carry Q_EXPORT
#      (__attribute__((visibility("default")))).
#   2. -DvmMain=<mod>_vmMain -DdllEntry=<mod>_dllEntry, so the three copies of
#      the entry points get distinct names.
#   3. `ld -r`, whose default behaviour is to demote private-extern symbols to
#      local. (-keep_private_externs is the flag that suppresses this.) After
#      the partial link each module exposes exactly its two renamed entries.
#
# vm_static.c holds the resulting registry; vm.c consults it in VM_Create.

# MOD is the module's name inside the engine (qagame, cgame, ui) and decides the
# renamed entry points. TARGET_PREFIX keeps the CMake target and object file
# names unique, because a build that carries both games compiles each module
# twice -- once per tree -- and two targets cannot share a name.
function(iortcw_add_vm_module MOD)
    cmake_parse_arguments(ARG "" "TARGET_PREFIX" "SOURCES;DEFINES;INCLUDES" ${ARGN})

    if(ARG_TARGET_PREFIX)
        set(_tgt "${ARG_TARGET_PREFIX}${MOD}")
    else()
        set(_tgt "${MOD}")
    endif()

    add_library(${_tgt}_static STATIC ${ARG_SOURCES})

    # -fno-common is not optional here. Tentative definitions (`int foo;` at file
    # scope) become common symbols, and the linker *merges* those across objects
    # instead of reporting a duplicate. cgame and ui both define Menus, menuStack
    # and friends, so leaving them common silently gives the two modules one
    # shared copy -- a link that succeeds and then misbehaves at runtime.
    # -fno-common turns them into ordinary definitions, which -fvisibility=hidden
    # can then hide and `ld -r` can localise.
    target_compile_options(${_tgt}_static PRIVATE -fvisibility=hidden -fno-common)
    target_compile_definitions(${_tgt}_static PRIVATE
        ${ARG_DEFINES}
        vmMain=${MOD}_vmMain
        dllEntry=${MOD}_dllEntry
    )
    target_include_directories(${_tgt}_static PRIVATE ${ARG_INCLUDES})

    set(_out ${CMAKE_CURRENT_BINARY_DIR}/${_tgt}.mod.o)

    if(IORTCW_IOS AND IORTCW_IOS_SIMULATOR)
        # The simulator is a distinct platform to ld: passing plain "ios" here
        # produces objects the simulator link then rejects as mismatched.
        set(_platform_args -platform_version ios-simulator
            ${CMAKE_OSX_DEPLOYMENT_TARGET} ${CMAKE_OSX_DEPLOYMENT_TARGET})
        set(_sdk iphonesimulator)
    elseif(IORTCW_IOS)
        set(_platform_args -platform_version ios
            ${CMAKE_OSX_DEPLOYMENT_TARGET} ${CMAKE_OSX_DEPLOYMENT_TARGET})
        set(_sdk iphoneos)
    else()
        set(_platform_args -platform_version macos
            ${CMAKE_OSX_DEPLOYMENT_TARGET} ${CMAKE_OSX_DEPLOYMENT_TARGET})
        set(_sdk macosx)
    endif()

    # -all_load pulls in every member of the archive; without it ld -r would
    # keep only the objects that resolve an undefined symbol, which is none of
    # them at this stage.
    add_custom_command(
        OUTPUT ${_out}
        COMMAND xcrun -sdk ${_sdk} ld -r
                -arch ${IORTCW_LD_ARCH}
                ${_platform_args}
                -o ${_out}
                -all_load $<TARGET_FILE:${_tgt}_static>
        DEPENDS ${_tgt}_static
        COMMENT "Partial-linking ${_tgt} into a single relocatable object"
        # No VERBATIM here on purpose. Under the Xcode generator TARGET_FILE
        # expands to a path containing a literal ${EFFECTIVE_PLATFORM_NAME},
        # which only Xcode's own build environment can resolve; VERBATIM would
        # quote it and ld would look for a directory with the braces in its name.
        COMMAND_EXPAND_LISTS
    )

    add_custom_target(${_tgt}_mod DEPENDS ${_out})
    set_source_files_properties(${_out} PROPERTIES
        EXTERNAL_OBJECT TRUE
        GENERATED TRUE
    )
    set(${_tgt}_MOD_OBJ ${_out} PARENT_SCOPE)
endfunction()
