cmake_minimum_required(VERSION 3.13)
project(alera_browser_linux_tests LANGUAGES CXX)

find_package(PkgConfig REQUIRED)

enable_testing()

add_executable(alera_browser_linux_navigation_state_tests
  "browser_navigation_state_test.cc"
)
target_compile_features(
  alera_browser_linux_navigation_state_tests PRIVATE cxx_std_17)
target_compile_options(alera_browser_linux_navigation_state_tests PRIVATE
  -Wall
  -Wextra
  -Werror
)
add_test(
  NAME alera_browser_linux_navigation_state_tests
  COMMAND alera_browser_linux_navigation_state_tests
)

add_executable(alera_browser_linux_profile_selection_tests
  "../browser_import_profile_selection.cc"
  "browser_import_profile_selection_test.cc"
)
target_compile_features(
  alera_browser_linux_profile_selection_tests PRIVATE cxx_std_17)
target_compile_options(alera_browser_linux_profile_selection_tests PRIVATE
  -Wall
  -Wextra
  -Werror
)
target_include_directories(
  alera_browser_linux_profile_selection_tests PRIVATE "..")
add_test(
  NAME alera_browser_linux_profile_selection_tests
  COMMAND alera_browser_linux_profile_selection_tests
)

pkg_check_modules(JSON_GLIB QUIET IMPORTED_TARGET json-glib-1.0)
pkg_check_modules(LIBSOUP QUIET IMPORTED_TARGET libsoup-3.0)
if(JSON_GLIB_FOUND AND LIBSOUP_FOUND)
add_executable(alera_browser_linux_import_tests
  "../browser_import_json.cc"
  "../browser_import_profile_selection.cc"
  "../browser_import_sources.cc"
  "browser_import_helpers_test.cc"
)
target_compile_features(alera_browser_linux_import_tests PRIVATE cxx_std_17)
target_compile_options(alera_browser_linux_import_tests PRIVATE
  -Wall
  -Wextra
  -Werror
)
target_include_directories(alera_browser_linux_import_tests PRIVATE "..")
target_link_libraries(alera_browser_linux_import_tests PRIVATE
  PkgConfig::JSON_GLIB
  PkgConfig::LIBSOUP
)

add_test(
  NAME alera_browser_linux_import_tests
  COMMAND alera_browser_linux_import_tests
)
endif()
