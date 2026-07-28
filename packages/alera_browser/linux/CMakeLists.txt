cmake_minimum_required(VERSION 3.13)
set(PROJECT_NAME "alera_browser")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "alera_browser_plugin")

find_package(PkgConfig REQUIRED)
find_package(OpenSSL REQUIRED)
pkg_check_modules(WEBKIT2GTK REQUIRED IMPORTED_TARGET webkit2gtk-4.1>=2.42)
pkg_check_modules(JSON_GLIB REQUIRED IMPORTED_TARGET json-glib-1.0)
pkg_check_modules(LIBSECRET REQUIRED IMPORTED_TARGET libsecret-1)
pkg_check_modules(SQLITE3 REQUIRED IMPORTED_TARGET sqlite3)

add_library(${PLUGIN_NAME} SHARED
  "alera_browser_plugin.cc"
  "browser_capture.cc"
  "browser_cookies.cc"
  "browser_decisions.cc"
  "browser_import.cc"
  "browser_import_chromium.cc"
  "browser_import_firefox.cc"
  "browser_import_json.cc"
  "browser_import_profile_selection.cc"
  "browser_import_profile_selection.h"
  "browser_import_sources.cc"
  "browser_javascript.cc"
  "browser_methods.cc"
  "browser_pages.cc"
  "browser_page_events.cc"
  "browser_page_methods.cc"
  "browser_profile_methods.cc"
  "browser_profiles.cc"
  "browser_values.cc"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)
target_compile_features(${PLUGIN_NAME} PUBLIC cxx_std_17)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  OpenSSL::Crypto
  PkgConfig::JSON_GLIB
  PkgConfig::LIBSECRET
  PkgConfig::SQLITE3
  PkgConfig::WEBKIT2GTK
)

set(alera_browser_bundled_libraries "" PARENT_SCOPE)
