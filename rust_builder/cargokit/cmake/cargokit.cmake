SET(cargokit_cmake_root "${CMAKE_CURRENT_LIST_DIR}/..")

# Workaround for https://github.com/dart-lang/pub/issues/4010
get_filename_component(cargokit_cmake_root "${cargokit_cmake_root}" REALPATH)

if(WIN32)
    # REALPATH does not properly resolve symlinks on windows :-/
    execute_process(COMMAND powershell -ExecutionPolicy Bypass -File "${CMAKE_CURRENT_LIST_DIR}/resolve_symlinks.ps1" "${cargokit_cmake_root}" OUTPUT_VARIABLE cargokit_cmake_root OUTPUT_STRIP_TRAILING_WHITESPACE)
endif()

# Arguments
# - target: CMAKE target to which rust library is linked
# - manifest_dir: relative path from current folder to directory containing cargo manifest
# - lib_name: cargo package name
# - any_symbol_name: name of any exported symbol from the library.
#                    used on windows to force linking with library.
function(apply_cargokit target manifest_dir lib_name any_symbol_name)

    set(CARGOKIT_LIB_NAME "${lib_name}")
    set(CARGOKIT_LIB_FULL_NAME "${CMAKE_SHARED_MODULE_PREFIX}${CARGOKIT_LIB_NAME}${CMAKE_SHARED_MODULE_SUFFIX}")
    if (CMAKE_CONFIGURATION_TYPES)
        set(CARGOKIT_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/$<CONFIG>")
        set(OUTPUT_LIB "${CMAKE_CURRENT_BINARY_DIR}/$<CONFIG>/${CARGOKIT_LIB_FULL_NAME}")
    else()
        set(CARGOKIT_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}")
        set(OUTPUT_LIB "${CMAKE_CURRENT_BINARY_DIR}/${CARGOKIT_LIB_FULL_NAME}")
    endif()
    if(WIN32)
        # Native cargo --target-dir must stay a few characters. ggml-vulkan's
        # nested vulkan-shaders-gen TryCompile writes
        # .../CMakeScratch/TryCompile-XXXX/CMakeFiles/cmTC_XXXXXXXX.dir/testCCompiler.c.obj
        # (~245 characters under the cargo triple). R:\c\alera_native is 17
        # characters and that object is 263, so cl.exe fails with C1083 and an
        # empty generated-file name. Use a one-letter suffix; do not append
        # the crate name. The sidecar keeps a sibling /cli directory.
        if(DEFINED ENV{ALERA_CARGOKIT_TEMP_DIR} AND NOT "$ENV{ALERA_CARGOKIT_TEMP_DIR}" STREQUAL "")
            set(CARGOKIT_TEMP_DIR "$ENV{ALERA_CARGOKIT_TEMP_DIR}/n")
        else()
            set(CARGOKIT_TEMP_DIR "$ENV{SystemDrive}/c/n")
        endif()
    else()
        set(CARGOKIT_TEMP_DIR "${CMAKE_CURRENT_BINARY_DIR}/cargokit_build")
    endif()

    if (FLUTTER_TARGET_PLATFORM)
        set(CARGOKIT_TARGET_PLATFORM "${FLUTTER_TARGET_PLATFORM}")
    else()
        set(CARGOKIT_TARGET_PLATFORM "windows-x64")
    endif()

    set(CARGOKIT_ENV
        "CARGOKIT_CMAKE=${CMAKE_COMMAND}"
        "CARGOKIT_CONFIGURATION=$<CONFIG>"
        "CARGOKIT_MANIFEST_DIR=${CMAKE_CURRENT_SOURCE_DIR}/${manifest_dir}"
        "CARGOKIT_TARGET_TEMP_DIR=${CARGOKIT_TEMP_DIR}"
        "CARGOKIT_OUTPUT_DIR=${CARGOKIT_OUTPUT_DIR}"
        "CARGOKIT_TARGET_PLATFORM=${CARGOKIT_TARGET_PLATFORM}"
        "CARGOKIT_TOOL_TEMP_DIR=${CARGOKIT_TEMP_DIR}/tool"
        "CARGOKIT_ROOT_PROJECT_DIR=${CMAKE_SOURCE_DIR}"
    )

    if(WIN32 AND CARGOKIT_TARGET_PLATFORM STREQUAL "windows-x64")
        # whisper-rs-sys builds a nested Vulkan shader generator. Keep that
        # inner build on Ninja so MSBuild's legacy FileTracker path limit in
        # the outer Flutter build cannot reject its generated .tlog files.
        find_program(CARGOKIT_NINJA_EXECUTABLE ninja)
        if(NOT CARGOKIT_NINJA_EXECUTABLE)
            message(FATAL_ERROR "Ninja is required for Windows native Rust builds")
        endif()
        list(APPEND CARGOKIT_ENV
            # cmake-rs reads the target-specific generator. Nested
            # vulkan-shaders-gen ExternalProject invokes cmake without -G and
            # only sees CMAKE_GENERATOR, so both must be Ninja.
            "CMAKE_GENERATOR=Ninja"
            "CMAKE_GENERATOR_x86_64_pc_windows_msvc=Ninja"
            "CMAKE_MAKE_PROGRAM=${CARGOKIT_NINJA_EXECUTABLE}"
            "CMAKE_MAKE_PROGRAM_x86_64_pc_windows_msvc=${CARGOKIT_NINJA_EXECUTABLE}"
            # CFLAGS/CXXFLAGS reach cc-rs. Nested TryCompile calls cl.exe,
            # which reads CL (prepend) and _CL_ (append). /FS serializes PDB
            # writes; /Z7 prefers C7 debug info when CMake still passes /Zi.
            "CFLAGS=/FS"
            "CXXFLAGS=/FS"
            "CL=/FS"
            "_CL_=/Z7 /FS"
            # ggml enables ccache/sccache by default. CI puts sccache on PATH
            # for rustc, and RULE_LAUNCH_COMPILE sccache + Ninja + cl.exe
            # drops .obj files (LNK1181 ggml.c.obj). Keep sccache on rustc only.
            "GGML_CCACHE=OFF"
        )
    endif()

    if (WIN32)
        set(SCRIPT_EXTENSION ".cmd")
        set(IMPORT_LIB_EXTENSION ".lib")
    else()
        set(SCRIPT_EXTENSION ".sh")
        set(IMPORT_LIB_EXTENSION "")
        execute_process(COMMAND chmod +x "${cargokit_cmake_root}/run_build_tool${SCRIPT_EXTENSION}")
    endif()

    # Using generators in custom command is only supported in CMake 3.20+
    if (CMAKE_CONFIGURATION_TYPES AND ${CMAKE_VERSION} VERSION_LESS "3.20.0")
        foreach(CONFIG IN LISTS CMAKE_CONFIGURATION_TYPES)
            add_custom_command(
                OUTPUT
                "${CMAKE_CURRENT_BINARY_DIR}/${CONFIG}/${CARGOKIT_LIB_FULL_NAME}"
                "${CMAKE_CURRENT_BINARY_DIR}/_phony_"
                COMMAND ${CMAKE_COMMAND} -E env ${CARGOKIT_ENV}
                "${cargokit_cmake_root}/run_build_tool${SCRIPT_EXTENSION}" build-cmake
                VERBATIM
            )
        endforeach()
    else()
        add_custom_command(
            OUTPUT
            ${OUTPUT_LIB}
            "${CMAKE_CURRENT_BINARY_DIR}/_phony_"
            COMMAND ${CMAKE_COMMAND} -E env ${CARGOKIT_ENV}
            "${cargokit_cmake_root}/run_build_tool${SCRIPT_EXTENSION}" build-cmake
            VERBATIM
        )
    endif()


    set_source_files_properties("${CMAKE_CURRENT_BINARY_DIR}/_phony_" PROPERTIES SYMBOLIC TRUE)

    if (TARGET ${target})
        # If we have actual cmake target provided create target and make existing
        # target depend on it
        add_custom_target("${target}_cargokit" DEPENDS ${OUTPUT_LIB})
        add_dependencies("${target}" "${target}_cargokit")
        target_link_libraries("${target}" PRIVATE "${OUTPUT_LIB}${IMPORT_LIB_EXTENSION}")
        if(WIN32)
            target_link_options(${target} PRIVATE "/INCLUDE:${any_symbol_name}")
        endif()
    else()
        # Otherwise (FFI) just use ALL to force building always
        add_custom_target("${target}_cargokit" ALL DEPENDS ${OUTPUT_LIB})
    endif()

    # Allow adding the output library to plugin bundled libraries
    set("${target}_cargokit_lib" ${OUTPUT_LIB} PARENT_SCOPE)

endfunction()
