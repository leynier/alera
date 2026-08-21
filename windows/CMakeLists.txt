# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(alera LANGUAGES CXX)

# The on-disk name of the executable. Driven by ALERA_FLAVOR so that a dev
# build coexists with an installed release build.
set(BINARY_NAME "alera-dev")
set(ALERA_APP_NAME "Alera Dev")
if("$ENV{ALERA_FLAVOR}" STREQUAL "release")
  set(BINARY_NAME "Alera")
  set(ALERA_APP_NAME "Alera")
endif()

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

find_program(CARGO_EXECUTABLE cargo)
if(NOT CARGO_EXECUTABLE)
  message(FATAL_ERROR "cargo executable is required to build the Alera CLI sidecar")
endif()

# The sidecar is the Rust crate rust/alera-cli (binary `alera.exe`); see
# linux/CMakeLists.txt for rationale. Windows uses a multi-config generator, so
# the build profile is selected with generator expressions at build time.
set(ALERA_CLI_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../rust")
set(ALERA_CLI_PROFILE_DIR "$<IF:$<CONFIG:Release>,release,debug>")
set(ALERA_CLI_OUTPUT "${ALERA_CLI_DIR}/target/${ALERA_CLI_PROFILE_DIR}/alera.exe")
find_program(ALERA_NINJA_EXECUTABLE ninja)
if(NOT ALERA_NINJA_EXECUTABLE)
  message(FATAL_ERROR "Ninja is required to build the Windows Whisper backend")
endif()
add_custom_target(alera_cli_sidecar ALL
  # The sidecar shares whisper-rs-sys with the Flutter plugin. Use Ninja for
  # that nested CMake build to avoid MSBuild FileTracker's legacy path limit.
  COMMAND "${CMAKE_COMMAND}" -E env
    "CMAKE_GENERATOR_x86_64_pc_windows_msvc=Ninja"
    "CMAKE_MAKE_PROGRAM_x86_64_pc_windows_msvc=${ALERA_NINJA_EXECUTABLE}"
    "${CARGO_EXECUTABLE}" build --locked -p alera-cli
    --profile $<IF:$<CONFIG:Release>,release,dev>
  BYPRODUCTS "${ALERA_CLI_OUTPUT}"
  WORKING_DIRECTORY "${ALERA_CLI_DIR}"
  COMMENT "Building Alera CLI sidecar (Rust)"
  VERBATIM
)
add_dependencies(${BINARY_NAME} alera_cli_sidecar)

set(ALERA_PROJECT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/..")
set(ALERA_NATIVE_HELPER_OUTPUT
  "${ALERA_PROJECT_DIR}/.dart_tool/alera_native_helpers/prepared/windows")
set(ALERA_DART_EXECUTABLE
  "$ENV{FLUTTER_ROOT}/bin/cache/dart-sdk/bin/dart.exe")
if(NOT EXISTS "${ALERA_DART_EXECUTABLE}")
  unset(ALERA_DART_EXECUTABLE)
  unset(ALERA_DART_EXECUTABLE CACHE)
  find_program(ALERA_DART_EXECUTABLE NAMES dart.exe dart)
endif()
if(NOT ALERA_DART_EXECUTABLE OR NOT EXISTS "${ALERA_DART_EXECUTABLE}")
  message(FATAL_ERROR "dart executable is required to prepare emulator helpers")
endif()
add_custom_target(alera_native_helpers ALL
  COMMAND "${ALERA_DART_EXECUTABLE}"
    "${ALERA_PROJECT_DIR}/tool/native_helpers/prepare_native_helpers.dart"
    --platform windows
    --output "${ALERA_NATIVE_HELPER_OUTPUT}"
  BYPRODUCTS
    "${ALERA_NATIVE_HELPER_OUTPUT}/manifest.json"
    "${ALERA_NATIVE_HELPER_OUTPUT}/android/scrcpy/4.0/scrcpy-server"
  DEPENDS
    "${ALERA_PROJECT_DIR}/tool/native_helpers/native_helper_assets.json"
    "${ALERA_PROJECT_DIR}/tool/native_helpers/native_helper_manifest.dart"
    "${ALERA_PROJECT_DIR}/tool/native_helpers/native_helper_materializer.dart"
    "${ALERA_PROJECT_DIR}/tool/native_helpers/prepare_native_helpers.dart"
    "${ALERA_PROJECT_DIR}/third_party/native_helpers/NOTICE.md"
  WORKING_DIRECTORY "${ALERA_PROJECT_DIR}"
  COMMENT "Preparing verified emulator helpers"
  VERBATIM
)
add_dependencies(${BINARY_NAME} alera_native_helpers)

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

if(TARGET flutter_local_notifications_windows)
  # MSVC 14.51 treats this plugin's current experimental coroutine header usage
  # as a hard error unless the compatibility warning is explicitly silenced.
  target_compile_definitions(flutter_local_notifications_windows PRIVATE
    "_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS")
endif()

# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
# Always force the prefix so a stale CMake cache cannot leave
# CMAKE_INSTALL_PREFIX at a system path (e.g. Program Files).
set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(PROGRAMS "${ALERA_CLI_OUTPUT}"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/resources/alera"
  COMPONENT Runtime)

install(DIRECTORY "${ALERA_NATIVE_HELPER_OUTPUT}/"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/resources/alera/emulator"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
  foreach(ALERA_PLUGIN_LIBRARY ${PLUGIN_BUNDLED_LIBRARIES})
    get_filename_component(ALERA_PLUGIN_LIBRARY_NAME
      "${ALERA_PLUGIN_LIBRARY}" NAME)
    if(ALERA_PLUGIN_LIBRARY_NAME STREQUAL "vulkan-1.dll")
      install(FILES "${ALERA_PLUGIN_LIBRARY}"
        DESTINATION "${CMAKE_INSTALL_PREFIX}/resources/alera"
        COMPONENT Runtime)
    endif()
  endforeach()
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
