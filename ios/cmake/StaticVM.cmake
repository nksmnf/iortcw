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

function(iortcw_add_vm_module MOD)
    cmake_parse_arguments(ARG "" "" "SOURCES;DEFINES;INCLUDES" ${ARGN})

    add_library(${MOD}_static STATIC ${ARG_SOURCES})

    # -fno-common is not optional here. Tentative definitions (`int foo;` at file
    # scope) become common symbols, and the linker *merges* those across objects
    # instead of reporting a duplicate. cgame and ui both define Menus, menuStack
    # and friends, so leaving them common silently gives the two modules one
    # shared copy -- a link that succeeds and then misbehaves at runtime.
    # -fno-common turns them into ordinary definitions, which -fvisibility=hidden
    # can then hide and `ld -r` can localise.
    target_compile_options(${MOD}_static PRIVATE -fvisibility=hidden -fno-common)
    target_compile_definitions(${MOD}_static PRIVATE
        ${ARG_DEFINES}
        vmMain=${MOD}_vmMain
        dllEntry=${MOD}_dllEntry
    )
    target_include_directories(${MOD}_static PRIVATE ${ARG_INCLUDES})

    set(_out ${CMAKE_CURRENT_BINARY_DIR}/${MOD}.mod.o)

    if(IORTCW_IOS)
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
                -all_load $<TARGET_FILE:${MOD}_static>
        DEPENDS ${MOD}_static
        COMMENT "Partial-linking ${MOD} into a single relocatable object"
        VERBATIM
    )

    add_custom_target(${MOD}_mod DEPENDS ${_out})
    set_source_files_properties(${_out} PROPERTIES
        EXTERNAL_OBJECT TRUE
        GENERATED TRUE
    )
    set(${MOD}_MOD_OBJ ${_out} PARENT_SCOPE)
endfunction()
