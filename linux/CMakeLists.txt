# Project-level configuration.
cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# The on-disk name and GTK application identifier are driven by ALERA_FLAVOR
# so that a dev build coexists with an installed release build (XDG user-data
# dirs are keyed by APPLICATION_ID).
# https://wiki.gnome.org/HowDoI/ChooseApplicationID
set(BINARY_NAME "alera-dev")
set(APPLICATION_ID "dev.leynier.alera.dev")
set(ALERA_APP_NAME "Alera Dev")
if("$ENV{ALERA_FLAVOR}" STREQUAL "release")
  set(BINARY_NAME "alera")
  set(APPLICATION_ID "dev.leynier.alera")
  set(ALERA_APP_NAME "Alera")
endif()

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(SET CMP0063 NEW)

# Load bundled libraries from the lib/ directory relative to the binary.
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Root filesystem for cross-building.
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# Define build configuration options.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# System-level dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)
pkg_check_modules(mpv REQUIRED IMPORTED_TARGET mpv)
pkg_check_modules(epoxy REQUIRED IMPORTED_TARGET epoxy)

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

find_program(CARGO_EXECUTABLE cargo)
if(NOT CARGO_EXECUTABLE)
  message(FATAL_ERROR "cargo executable is required to build the Alera CLI sidecar")
endif()

# The sidecar is the Rust crate rust/alera-cli (binary `alera`). Cargo runs from
# the rust/ workspace so rust-toolchain.toml applies, and writes to the shared
# rust/target dir (git-ignored, CI-cached). The build profile mirrors the app:
# Release ships an optimized sidecar; other configs build debug for fast dev.
set(ALERA_CLI_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../rust")
if(CMAKE_BUILD_TYPE STREQUAL "Release")
  set(ALERA_CLI_CARGO_PROFILE_ARG "--release")
  set(ALERA_CLI_PROFILE_DIR "release")
else()
  set(ALERA_CLI_CARGO_PROFILE_ARG "")
  set(ALERA_CLI_PROFILE_DIR "debug")
endif()
set(ALERA_CLI_OUTPUT "${ALERA_CLI_DIR}/target/${ALERA_CLI_PROFILE_DIR}/alera")
add_custom_target(alera_cli_sidecar ALL
  COMMAND "${CARGO_EXECUTABLE}" build --locked -p alera-cli ${ALERA_CLI_CARGO_PROFILE_ARG}
  BYPRODUCTS "${ALERA_CLI_OUTPUT}"
  WORKING_DIRECTORY "${ALERA_CLI_DIR}"
  COMMENT "Building Alera CLI sidecar (Rust)"
  VERBATIM
)

set(ALERA_PROJECT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/..")
set(ALERA_NATIVE_HELPER_OUTPUT
  "${ALERA_PROJECT_DIR}/.dart_tool/alera_native_helpers/prepared/linux")
set(ALERA_DART_EXECUTABLE
  "$ENV{FLUTTER_ROOT}/bin/cache/dart-sdk/bin/dart")
if(NOT EXISTS "${ALERA_DART_EXECUTABLE}")
  unset(ALERA_DART_EXECUTABLE)
  unset(ALERA_DART_EXECUTABLE CACHE)
  find_program(ALERA_DART_EXECUTABLE NAMES dart)
endif()
if(NOT ALERA_DART_EXECUTABLE OR NOT EXISTS "${ALERA_DART_EXECUTABLE}")
  message(FATAL_ERROR "dart executable is required to prepare emulator helpers")
endif()
add_custom_target(alera_native_helpers ALL
  COMMAND "${ALERA_DART_EXECUTABLE}"
    "${ALERA_PROJECT_DIR}/tool/native_helpers/prepare_native_helpers.dart"
    --platform linux
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

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
add_dependencies(${BINARY_NAME} alera_cli_sidecar)
add_dependencies(${BINARY_NAME} alera_native_helpers)

# Only the install-generated bundle's copy of the executable will launch
# correctly, since the resources must in the right relative locations. To avoid
# people trying to run the unbundled copy, put it in a subdirectory instead of
# the default top-level location.
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
# media_kit defaults to replacing the process allocator with a downloaded
# static mimalloc object. A video surface does not justify changing Alera's
# process-wide allocator, and the helper supply chain must not rely on the
# plugin's MD5-only mimalloc download.
set(MIMALLOC_USE_STATIC_LIBS OFF CACHE BOOL
  "Do not replace Alera's process allocator for media playback" FORCE)
include(flutter/generated_plugins.cmake)


# === Installation ===
# By default, "installing" just makes a relocatable bundle in the build
# directory. Always force the prefix: a stale CMake cache can leave
# CMAKE_INSTALL_PREFIX at /usr/local, which makes `flutter run` try to
# install into the system tree and fail with Permission denied.
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)

# Start with a clean build bundle directory every time.
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

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

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
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
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
