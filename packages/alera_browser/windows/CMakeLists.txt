cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "alera_browser")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "alera_browser_plugin")
set(ALERA_BROWSER_WEBVIEW_VERSION "1.0.4078.44")
set(ALERA_BROWSER_NUGET_URL
  "https://dist.nuget.org/win-x86-commandline/v5.10.0/nuget.exe")
set(ALERA_BROWSER_NUGET_SHA256
  "852b71cc8c8c2d40d09ea49d321ff56fd2397b9d6ea9f96e532530307bbbafd3")

find_program(ALERA_BROWSER_NUGET nuget)
if(NOT ALERA_BROWSER_NUGET)
  set(ALERA_BROWSER_NUGET "${CMAKE_BINARY_DIR}/nuget.exe")
  if(NOT EXISTS "${ALERA_BROWSER_NUGET}")
    file(DOWNLOAD
      "${ALERA_BROWSER_NUGET_URL}"
      "${ALERA_BROWSER_NUGET}"
      EXPECTED_HASH "SHA256=${ALERA_BROWSER_NUGET_SHA256}")
  endif()
endif()

set(ALERA_BROWSER_DEPS "alera_browser_windows_deps")
add_custom_target(${ALERA_BROWSER_DEPS} ALL)
add_custom_command(
  TARGET ${ALERA_BROWSER_DEPS} PRE_BUILD
  COMMAND "${ALERA_BROWSER_NUGET}" install Microsoft.Web.WebView2
    -Version "${ALERA_BROWSER_WEBVIEW_VERSION}"
    -OutputDirectory "${CMAKE_BINARY_DIR}/packages"
  COMMENT "Preparing the WebView2 SDK for alera_browser"
  VERBATIM
)

add_library(${PLUGIN_NAME} SHARED
  "alera_browser_plugin.cpp"
  "alera_browser_plugin.h"
  "alera_browser_plugin_c_api.cpp"
  "browser_capture_methods.cpp"
  "browser_cookie.cpp"
  "browser_cookie.h"
  "browser_cookie_methods.cpp"
  "browser_decisions.cpp"
  "browser_decision_timeout.h"
  "browser_downloads.cpp"
  "browser_import_methods.cpp"
  "browser_import_profile_selection.cpp"
  "browser_import_profile_selection.h"
  "browser_import_chromium.cpp"
  "browser_import_crypto.cpp"
  "browser_import_database.cpp"
  "browser_import_firefox.cpp"
  "browser_import_internal.h"
  "browser_import_json.cpp"
  "browser_import_limits.h"
  "browser_import_sources.cpp"
  "browser_json.cpp"
  "browser_json.h"
  "browser_page.cpp"
  "browser_page.h"
  "browser_page_events.cpp"
  "browser_page_methods.cpp"
  "browser_platform_dispatcher.cpp"
  "browser_platform_dispatcher.h"
  "browser_popup.cpp"
  "browser_profile.cpp"
  "browser_profile.h"
  "browser_profile_methods.cpp"
  "browser_value.cpp"
  "browser_value.h"
  "include/alera_browser/alera_browser_plugin_c_api.h"
)
add_dependencies(${PLUGIN_NAME} ${ALERA_BROWSER_DEPS})

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)
target_compile_features(${PLUGIN_NAME} PUBLIC cxx_std_17)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
if(DEFINED ALERA_APP_NAME)
  target_compile_definitions(${PLUGIN_NAME} PRIVATE
    ALERA_BROWSER_STORAGE_NAME=L"${ALERA_APP_NAME}")
endif()
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_link_libraries(${PLUGIN_NAME} PRIVATE
  "${CMAKE_BINARY_DIR}/packages/Microsoft.Web.WebView2.${ALERA_BROWSER_WEBVIEW_VERSION}/build/native/Microsoft.Web.WebView2.targets"
  flutter
  flutter_wrapper_plugin
  bcrypt
  crypt32
  ole32
  shlwapi
  winsqlite3
  ws2_32
)

set(alera_browser_bundled_libraries "" PARENT_SCOPE)
